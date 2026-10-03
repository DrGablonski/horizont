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
	if (fwd) return fwd.split(',')[0].trim();
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
	const fwd = (event.request.headers.get('x-forwarded-proto') ?? '')
		.split(',')[0]
		.trim()
		.toLowerCase();
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

export async function readJsonBody<T>(request: Request): Promise<T | null> {
	try {
		return (await request.json()) as T;
	} catch {
		return null;
	}
}
