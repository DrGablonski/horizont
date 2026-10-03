// Gemeinsame Helfer für die Auth-API (Rate-Limit, Cookie-Optionen, Errors).

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

export function sessionCookieOptions() {
	return {
		path: '/',
		httpOnly: true,
		sameSite: 'lax' as const,
		maxAge: SESSION_MAX_AGE_S
	};
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
