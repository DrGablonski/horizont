// In-Memory-Session-Store.
//
// Bewusst ohne Persistenz: nach einem Neustart des Containers sind alle
// Sessions ungültig (alle User müssen sich neu anmelden). Das ist die
// vom Admin gewünschte Semantik und eliminiert ein Session-Datenleck.

import { randomBytes } from 'node:crypto';
import { getUserById } from '$server/auth/userStore';
import type { AppUser } from '$lib/types';

const SESSION_TTL_MS = 12 * 60 * 60 * 1000; // 12 h

export const SESSION_COOKIE = 'horizont_session';

interface SessionRecord {
	userId: string;
	expiresAt: number;
}

const sessions = new Map<string, SessionRecord>();

function prune(now: number): void {
	for (const [token, rec] of sessions) {
		if (rec.expiresAt <= now) sessions.delete(token);
	}
}

export function createSession(userId: string): string {
	prune(Date.now());
	const token = randomBytes(32).toString('hex');
	sessions.set(token, { userId, expiresAt: Date.now() + SESSION_TTL_MS });
	return token;
}

export function destroySession(token: string): void {
	sessions.delete(token);
}

/** Liefert den (öffentlichen) User der Session oder null. */
export function getSessionUser(token: string | undefined | null): AppUser | null {
	if (!token) return null;
	const now = Date.now();
	const rec = sessions.get(token);
	if (!rec) return null;
	if (rec.expiresAt <= now) {
		sessions.delete(token);
		return null;
	}
	const stored = getUserById(rec.userId);
	if (!stored || stored.disabled) return null;
	return {
		id: stored.id,
		username: stored.username,
		role: stored.role,
		createdAt: stored.createdAt,
		lastLoginAt: stored.lastLoginAt
	};
}

export const SESSION_MAX_AGE_S = Math.floor(SESSION_TTL_MS / 1000);
