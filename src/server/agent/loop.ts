// Agent-Loop: mehrstufiger Tool-Loop über die LLM-Runde hinweg.
//
//   LLM → (Text-Deltas gestreamt) → Tool-Calls
//     Read-Tools  → sofort ausgeführt, Ergebnis als Tool-Message zurück
//     Write-Tools → Pause: Approval-Event an den Client, Platzhalter-
//                   Tool-Messages, Loop hält. Resume (accept/reject)
//                   ersetzt die Platzhalter und setzt die Loop fort.
//
// Die Nachrichtenhistorie bleibt pro Session (in-memory) bestehen, damit
// der Kontext über mehrere Runden erhalten bleibt.

import { randomUUID } from 'node:crypto';
import type { AgentConfig } from '$lib/types';
import type {
	AgentEvent,
	AgentLoopResult,
	AgentSession,
	PendingApproval,
	PendingCall,
	ToolCall
} from './types';
import { AGENT_TOOLS, TOOL_BY_NAME, TOOL_LABELS } from './tools';
import { callLLM } from './upstream';
import {
	approvalSummary,
	loadContext,
	runReadTool,
	runWriteTool,
	toolEffect,
	toolResultText,
	type ExecContext,
	type ToolResult
} from './executor';
import { appendMessage, setPending } from './sessions';

const MAX_ROUNDS = 8;
const MAX_TOOL_CALLS_PER_TURN = 6;

type Send = (ev: AgentEvent) => boolean;

export interface LoopParams {
	session: AgentSession;
	config: AgentConfig;
	signal: AbortSignal;
	send: Send;
}

function placeholderContent(approvalId: string): string {
	return JSON.stringify({ pending: true, approvalId });
}

/**
 * Führt Runden aus, bis der Chat abgeschlossen ('completed'), auf eine
 * Bestätigung wartet ('awaiting_approval') oder abgebrochen wird ('aborted').
 */
export async function advance(params: LoopParams): Promise<AgentLoopResult> {
	const { session, config, signal, send } = params;
	const ctx = loadContext(session.userId);

	for (let round = 0; round < MAX_ROUNDS; round += 1) {
		if (signal.aborted) return 'aborted';

		let content: string;
		let toolCalls: ToolCall[];
		try {
			const res = await callLLM(config, session.messages, AGENT_TOOLS, {
				signal,
				onDelta: (t) => {
					send({ type: 'delta', text: t });
				}
			});
			content = res.content;
			toolCalls = res.toolCalls.slice(0, MAX_TOOL_CALLS_PER_TURN);
		} catch (e) {
			if (signal.aborted) return 'aborted';
			const msg = e instanceof Error ? e.message : 'Unbekannter Fehler beim LLM-Aufruf.';
			send({ type: 'error', error: msg });
			return 'completed';
		}

		if (signal.aborted) return 'aborted';

		appendMessage(session, { role: 'assistant', content, toolCalls });
		if (toolCalls.length === 0) {
			send({ type: 'done' });
			return 'completed';
		}

		// Rufe- und Schreib-Tools trennen. Bei einem Schreib-Tool pausieren
		// wir: vorangegangene Reads werden ausgeführt, alle ab dem ersten
		// Write erhalten Platzhalter, die bei Resume aufgelöst werden.
		const firstWriteIdx = toolCalls.findIndex((tc) => toolEffect(tc.name) === 'write');

		if (firstWriteIdx === -1) {
			// Nur Reads → alle ausführen und weiter.
			for (const tc of toolCalls) {
				if (signal.aborted) return 'aborted';
				const def = TOOL_BY_NAME.get(tc.name);
				const result: ToolResult = def
					? await runReadTool(ctx, tc.name, tc.args)
					: { ok: false, error: `Unbekanntes Tool: ${tc.name}` };
				send({ type: 'tool_result', name: tc.name, ok: result.ok, write: false, label: TOOL_LABELS[tc.name] ?? tc.name });
				appendMessage(session, {
					role: 'tool',
					toolCallId: tc.id,
					name: tc.name,
					content: toolResultText(result)
				});
			}
			continue;
		}

		// Reads vor dem ersten Write ausführen.
		for (let i = 0; i < firstWriteIdx; i += 1) {
			const tc = toolCalls[i];
			if (signal.aborted) return 'aborted';
			const def = TOOL_BY_NAME.get(tc.name);
			const result: ToolResult = def
					? await runReadTool(ctx, tc.name, tc.args)
					: { ok: false, error: `Unbekanntes Tool: ${tc.name}` };
				send({ type: 'tool_result', name: tc.name, ok: result.ok, write: false, label: TOOL_LABELS[tc.name] ?? tc.name });
				appendMessage(session, {
					role: 'tool',
					toolCallId: tc.id,
					name: tc.name,
					content: toolResultText(result)
				});
			}

		// Ab dem ersten Write: Platzhalter anlegen und Pause.
		const approvalId = randomUUID();
		const calls: PendingCall[] = [];
		for (let i = firstWriteIdx; i < toolCalls.length; i += 1) {
			const tc = toolCalls[i];
			appendMessage(session, {
				role: 'tool',
				toolCallId: tc.id,
				name: tc.name,
				content: placeholderContent(approvalId)
			});
			calls.push({
				toolCallId: tc.id,
				name: tc.name,
				args: tc.args,
				messageIndex: session.messages.length - 1,
				isPrimary: i === firstWriteIdx
			});
		}

		const primary = calls[0];
		setPending(session, {
			approvalId,
			toolName: primary.name,
			args: primary.args,
			toolCallId: primary.toolCallId,
			messageIndex: primary.messageIndex,
			calls
		});

		send({
			type: 'approval',
			approvalId,
			tool: primary.name,
			summary: approvalSummary(primary.name, primary.args),
			args: primary.args
		});
		return 'awaiting_approval';
	}

	// Runden-Limit erreicht.
	appendMessage(session, {
		role: 'assistant',
		content: 'Ich bin an der maximalen Schrittzahl angelangt. Bitte formuliere die Anfrage präziser oder teile sie in kleinere Schritte auf.'
	});
	send({ type: 'done' });
	return 'completed';
}

/**
 * Setzt eine gepausete Loop nach einer Bestätigung fort.
 * `note` (optional) wird als Nutzer-Nachricht angehängt (Korrektur).
 */
export async function resume(
	params: LoopParams,
	approvalId: string,
	decision: 'accept' | 'reject',
	note?: string
): Promise<AgentLoopResult> {
	const { session, send } = params;
	const ctx = loadContext(session.userId);
	const pending = session.pending;
	if (!pending || pending.approvalId !== approvalId) {
		send({ type: 'error', error: 'Keine ausstehende Bestätigung gefunden.' });
		return 'completed';
	}

	const calls: PendingCall[] =
		pending.calls.length > 0
			? pending.calls
			: [
					{
						toolCallId: pending.toolCallId,
						name: pending.toolName,
						args: pending.args,
						messageIndex: pending.messageIndex,
						isPrimary: true
					}
				];

	for (const call of calls) {
		const effect = toolEffect(call.name);
		let result: ToolResult;
		if (effect === 'write' && decision === 'reject') {
			result = { ok: false, error: 'Der User hat diese Aktion abgelehnt.' };
		} else if (effect === 'write') {
			result = await runWriteTool(ctx, call.name, call.args);
		} else {
			result = await runReadTool(ctx, call.name, call.args);
		}
		send({
			type: 'tool_result',
			name: call.name,
			ok: result.ok,
			write: effect === 'write',
			label: TOOL_LABELS[call.name] ?? call.name
		});
		// Platzhalter-Message durch das echte Ergebnis ersetzen.
		session.messages[call.messageIndex] = {
			role: 'tool',
			toolCallId: call.toolCallId,
			name: call.name,
			content: toolResultText(result)
		};
	}

	setPending(session, null);

	if (note && note.trim() !== '') {
		appendMessage(session, { role: 'user', content: note.trim() });
	}

	return advance(params);
}

/** Eine neue Nutzer-Nachricht anhängen und die Loop starten. */
export async function startTurn(
	params: LoopParams,
	message: string
): Promise<AgentLoopResult> {
	appendMessage(params.session, { role: 'user', content: message });
	return advance(params);
}

/** Re-Export für die Routen (Kontext-Ladehilfe). */
export { loadContext };
