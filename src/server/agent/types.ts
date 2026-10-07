// Interne Typen für den KI-Agent (Messages, Tools, SSE-Events, Sessions).

import type { AgentConfig } from '$lib/types';

// ── LLM-Messages (normalisiert, provider-unabhängig) ─────────────────────

export interface ToolCall {
	id: string;
	name: string;
	args: Record<string, unknown>;
}

export type AgentMsg =
	| { role: 'system'; content: string }
	| { role: 'user'; content: string }
	| { role: 'assistant'; content: string; toolCalls?: ToolCall[] }
	| { role: 'tool'; toolCallId: string; name: string; content: string };

// ── Tool-Definitionen ─────────────────────────────────────────────────────

export interface ToolDef {
	name: string;
	description: string;
	parameters: Record<string, unknown>;
	/** 'read' = direkt ausgeführt, 'write' = erfordert User-Bestätigung. */
	effect: 'read' | 'write';
}

// ── SSE-Events (Client-protokoll) ─────────────────────────────────────────

export type AgentEvent =
	| { type: 'delta'; text: string }
	| {
			type: 'tool_result';
			name: string;
			ok: boolean;
			/** true, wenn es sich um eine (erfolgreiche) Datenänderung handelt. */
			write: boolean;
			/** Anzeigename (deutsch) für das UI. */
			label: string;
	  }
	| { type: 'approval'; approvalId: string; tool: string; summary: string; args: Record<string, unknown> }
	| { type: 'done' }
	| { type: 'error'; error: string };

// ── Ausstehende Bestätigung (zweiphasig) ─────────────────────────────────

/** Ein Schreib-Tool-Call mit seiner Platzhalter-Message. */
export interface PendingCall {
	toolCallId: string;
	name: string;
	args: Record<string, unknown>;
	/** Index der Platzhalter-Tool-Message in session.messages. */
	messageIndex: number;
	/** Erster (Haupt-)Write des Batches – Basis für die Approval-Karte. */
	isPrimary: boolean;
}

export interface PendingApproval {
	approvalId: string;
	/** Haupt-Tool der Bestätigungs-Karte (erster Write des Batches). */
	toolName: string;
	args: Record<string, unknown>;
	toolCallId: string;
	messageIndex: number;
	/** Alle ab dem ersten Write ausstehenden Calls des Batches. */
	calls: PendingCall[];
}

// ── Session (in-memory, pro Chat-Verlauf) ─────────────────────────────────

export interface AgentSession {
	key: string;
	userId: string;
	createdAt: number;
	updatedAt: number;
	/** [0] ist immer die System-Message. */
	messages: AgentMsg[];
	pending: PendingApproval | null;
}

export type AgentLoopResult = 'completed' | 'awaiting_approval' | 'aborted';

export interface AgentContext {
	config: AgentConfig;
}
