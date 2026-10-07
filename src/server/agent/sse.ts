// SSE-Stream-Wrapper für die Agent-Endpunkte.
// Events werden als `data: <json>\n\n` geschrieben; `work(send)` erzeugt den
// Stream-Inhalt (Agent-Loop), der Stream schließt sich danach automatisch.

import type { AgentEvent } from './types';

export const SSE_HEADERS: Record<string, string> = {
	'content-type': 'text/event-stream; charset=utf-8',
	'cache-control': 'no-cache, no-transform',
	connection: 'keep-alive',
	'x-accel-buffering': 'no'
};

/** Liefert `false`, wenn der Client schon weg ist (Stream geschlossen). */
export type SseSend = (ev: AgentEvent) => boolean;

export function sseResponse(work: (send: SseSend) => Promise<void>): Response {
	const encoder = new TextEncoder();
	let closed = false;
	const stream = new ReadableStream<Uint8Array>({
		async start(ctrl) {
			const send: SseSend = (ev) => {
				if (closed) return false;
				try {
					ctrl.enqueue(encoder.encode(`data: ${JSON.stringify(ev)}\n\n`));
					return true;
				} catch {
					closed = true;
					return false;
				}
			};
			try {
				await work(send);
			} catch (e) {
				if (!closed) {
					try {
						send({
							type: 'error',
							error: e instanceof Error ? e.message : 'Unbekannter Fehler'
						});
					} catch {
						closed = true;
					}
				}
			} finally {
				closed = true;
				try {
					ctrl.close();
				} catch {
					// bereits geschlossen
				}
			}
		}
	});
	return new Response(stream, { headers: SSE_HEADERS });
}
