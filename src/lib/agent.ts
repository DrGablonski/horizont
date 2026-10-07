// Client-seitiger Zugriff auf den KI-Agent (SSE-Streams).
//
// Der Chat ist zweiphasig: POST /api/agent liefert einen Event-Stream, der
// mit 'done' (fertig) oder 'approval' (Pause, Bestätigung erforderlich)
// endet. Bei 'approval' folgt POST /api/agent/approve mit selbem sessionKey.

import type { AgentStatus } from './types';

export interface AgentApproval {
	approvalId: string;
	tool: string;
	summary: string;
	args: Record<string, unknown>;
}

export interface AgentChatHandlers {
	onDelta?: (text: string) => void;
	/** `write` = es wurde (möglicherweise) Daten verändert. */
	onToolResult?: (name: string, ok: boolean, write: boolean, label: string) => void;
	onApproval?: (a: AgentApproval) => void;
	onDone?: () => void;
	onError?: (error: string) => void;
}

async function readSse(body: ReadableStream<Uint8Array>, handlers: AgentChatHandlers): Promise<void> {
	const reader = body.getReader();
	const decoder = new TextDecoder();
	let buf = '';
	for (;;) {
		const { done, value } = await reader.read();
		if (done) break;
		buf += decoder.decode(value, { stream: true });
		let idx: number;
		while ((idx = buf.indexOf('\n\n')) !== -1) {
			const frame = buf.slice(0, idx);
			buf = buf.slice(idx + 2);
			for (const line of frame.split('\n')) {
				if (!line.startsWith('data:')) continue;
				const payload = line.slice(5).trim();
				if (payload === '') continue;
				let ev: {
					type: string;
					text?: string;
					name?: string;
					ok?: boolean;
					write?: boolean;
					label?: string;
					error?: string;
					approvalId?: string;
					tool?: string;
					summary?: string;
					args?: Record<string, unknown>;
				};
				try {
					ev = JSON.parse(payload);
				} catch {
					continue;
				}
				switch (ev.type) {
					case 'delta':
						handlers.onDelta?.(ev.text ?? '');
						break;
					case 'tool_result':
						handlers.onToolResult?.(ev.name ?? '', ev.ok === true, ev.write === true, ev.label ?? ev.name ?? '');
						break;
					case 'approval':
						handlers.onApproval?.({
							approvalId: ev.approvalId ?? '',
							tool: ev.tool ?? '',
							summary: ev.summary ?? '',
							args: ev.args ?? {}
						});
						break;
					case 'error':
						handlers.onError?.(ev.error ?? 'Unbekannter Fehler.');
						break;
					case 'done':
						handlers.onDone?.();
						break;
				}
			}
		}
	}
}

async function streamPost(
	url: string,
	body: unknown,
	handlers: AgentChatHandlers,
	signal?: AbortSignal
): Promise<void> {
	let res: Response;
	try {
		res = await fetch(url, {
			method: 'POST',
			headers: { 'Content-Type': 'application/json' },
			body: JSON.stringify(body),
			signal
		});
	} catch (e) {
		if ((e as Error).name === 'AbortError') return;
		handlers.onError?.('Verbindung zum Server fehlgeschlagen.');
		return;
	}
	if (!res.ok || !res.body) {
		let msg = `HTTP ${res.status}`;
		try {
			const b = (await res.json()) as { error?: string };
			if (b?.error) msg = b.error;
		} catch {
			/* kein JSON-Body */
		}
		handlers.onError?.(msg);
		return;
	}
	try {
		await readSse(res.body, handlers);
	} catch (e) {
		if ((e as Error).name === 'AbortError') return;
		handlers.onError?.('Verbindung unterbrochen.');
	}
}

export const agent = {
	/** Steht eine Agent-Config bereit? (legt fest, ob das Widget sichtbar ist) */
	status: async (): Promise<AgentStatus> => {
		const res = await fetch('/api/agent');
		if (!res.ok) throw new Error(`HTTP ${res.status}`);
		return (await res.json()) as AgentStatus;
	},

	/** Neue Chat-Nachricht (oder Text-Antwort auf ausstehende Bestätigung). */
	chat: (sessionKey: string | null, message: string, handlers: AgentChatHandlers, signal?: AbortSignal) =>
		streamPost(
			'/api/agent',
			{ message, sessionKey: sessionKey ?? undefined },
			handlers,
			signal
		),

	/** Ausstehende Bestätigung entscheiden. */
	approve: (
		sessionKey: string,
		approvalId: string,
		decision: 'accept' | 'reject',
		note: string | undefined,
		handlers: AgentChatHandlers,
		signal?: AbortSignal
	) =>
		streamPost(
			'/api/agent/approve',
			{ sessionKey, approvalId, decision, note },
			handlers,
			signal
		)
};
