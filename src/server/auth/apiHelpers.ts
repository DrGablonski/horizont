// Gemeinsame Helfer für die Auth-API (Rate-Limit, Cookie-Optionen, Errors).

import type { RequestEvent } from '@sveltejs/kit';
import { SESSION_MAX_AGE_S } from '$server/auth/sessionStore';

// ── Rate-Limiting (in-memory, pro IP) ─────────────────────────────────────

const RATE_WINDOW_MS = 60_000;
const RATE_MAX = 5;
const attempts = new Map<string, { count: number; resetAt: number }>();

export function rateLimited(ip: string): boolean {
	const now = Date.now();
	const rec = attempts.get(ip);
	if (!rec || rec.resetAt <= now) {
		attempts.set(ip, { count: 1, resetAt: now + RATE_WINDOW_MS });
		return false;
	}
	rec.count += 1;
	return rec.count > RATE_MAX;
}

export function clientIp(request: Request): string {
	const fwd = request.headers.get('x-forwarded-for');
	if (fwd) {
		// Letzter Eintrag: vom (letzten) Reverse-Proxy selbst hinzugefügt und
		// damit nicht vom Client fälschbar. Der erste Eintrag wäre Client-
		// gesteuert und würde das Rate-Limit per Header-Rotation umgehen.
		const parts = fwd
			.split(',')
			.map((p) => p.trim())
			.filter(Boolean);
		if (parts.length > 0) return parts[parts.length - 1];
	}
	return 'local';
}

/**
 * Cookie-Optionen für die Session. `secure` wird explizit ermittelt:
 * SvelteKits Default ('auto') behandelt jeden Nicht-localhost-Origin als
 * HTTPS, und der Node-Adapter (adapter-node) baut die `Request`-URL immer
 * mit `https://` (siehe `get_origin`, das auf 'https' defaultet) — die
 * URL-Scheme ist daher kein verlässliches TLS-Signal.
 *
 * Verlässliche Signale:
 *  - `x-forwarded-proto` hinter einem TLS-terminierenden Reverse-Proxy,
 *  - der echte Socket-Zustand der Verbindung (`event.platform.req` ist
 *    die rohe Node-Request, die der Adapter weiterreicht).
 */
export function sessionCookieOptions(event: RequestEvent) {
	return {
		path: '/',
		httpOnly: true,
		sameSite: 'lax' as const,
		maxAge: SESSION_MAX_AGE_S,
		secure: requestIsSecure(event)
	};
}

function requestIsSecure(event: RequestEvent): boolean {
	// Hinter einem TLS-terminierenden Proxy ist der Header maßgeblich.
	// Letzter Eintrag: vom Proxy gesetzt, nicht Client-fälschbar.
	const parts = (event.request.headers.get('x-forwarded-proto') ?? '')
		.split(',')
		.map((p) => p.trim().toLowerCase())
		.filter(Boolean);
	const fwd = parts.length > 0 ? parts[parts.length - 1] : '';
	if (fwd === 'https') return true;
	if (fwd === 'http') return false;

	// Direkte Verbindung: `socket.encrypted` ist das echte Signal.
	// `event.platform` ist ein Adapter-Konzept (leeres `App.Platform`),
	// daher gezielter Cast auf die vom Node-Adapter übergebene Form.
	const platform = event.platform as unknown as
		| { req?: { socket?: { encrypted?: boolean } } }
		| undefined;
	return platform?.req?.socket?.encrypted === true;
}

export function jsonErr(e: unknown): { error: string } {
	return { error: e instanceof Error ? e.message : 'Unbekannter Fehler' };
}

// Alle JSON-Payloads in der App sind klein; alles darüber ist unnötig und
// schützt sonst vor Memory-Attacken über überdimensionierte Bodies
// (relevant v. a. für die öffentlichen Endpunkte /api/auth/login + /setup).
const MAX_BODY_BYTES = 64 * 1024;
// Überdimensionierte Bodies werden nicht gespeichert, sondern bis zu dieser
// Grenze einfach verworfen (Drain), damit die 400-Antwort noch ankommt.
// Darüber wird die Verbindung abgebrochen (nur noch Pathologisches).
const DRAIN_CAP_BYTES = 8 * 1024 * 1024;

export async function readJsonBody<T>(request: Request): Promise<T | null> {
	try {
		const text = await readBodyLimited(request, MAX_BODY_BYTES);
		return JSON.parse(text) as T;
	} catch {
		return null;
	}
}

/**
 * Liest den Request-Body streamend. Payloads über `limit` werden verworfen
 * (Drain bis `DRAIN_CAP_BYTES`), damit die Fehlerantwort sauber ankommt
 * statt eines Connection-Resets; erst jenseits des Cap wird abgebrochen.
 */
async function readBodyLimited(request: Request, limit: number): Promise<string> {
	const len = Number(request.headers.get('content-length') ?? '');
	if (Number.isFinite(len) && len > DRAIN_CAP_BYTES) throw new Error('Body zu groß');
	if (!request.body) return '';
	const reader = request.body.getReader();
	const chunks: Uint8Array[] = [];
	let size = 0;
	let keeping = true;
	try {
		for (;;) {
			const { done, value } = await reader.read();
			if (done) break;
			if (value && value.byteLength > 0) {
				size += value.byteLength;
				if (keeping) {
					if (size > limit) {
						keeping = false; // Payload zu groß: Rest nur noch drainen
					} else {
						chunks.push(value);
					}
				}
				if (size > DRAIN_CAP_BYTES) {
					await reader.cancel();
					throw new Error('Body zu groß');
				}
			}
		}
	} finally {
		reader.releaseLock();
	}
	if (!keeping) throw new Error('Body zu groß');
	const out = new Uint8Array(size);
	let off = 0;
	for (const c of chunks) {
		out.set(c, off);
		off += c.byteLength;
	}
	return new TextDecoder().decode(out);
}
