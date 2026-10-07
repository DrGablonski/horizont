// In-memory-Chat-Sessions für den KI-Agent (verschwindet bei Neustart).
// Pro User maximal 5 aktive Chats, Session-TTL 30 Minuten Inaktivität.

import { randomUUID } from 'node:crypto';
import type { AgentMsg, AgentSession, PendingApproval } from './types';

const SESSION_TTL_MS = 30 * 60 * 1000;
const MAX_SESSIONS_PER_USER = 5;
const MAX_MESSAGES = 60; // System-Prompt bleibt bei [0] erhalten
const SESSION_KEY_RE = /^[A-Za-z0-9_-]{8,64}$/;

const sessions = new Map<string, AgentSession>();

function touch(s: AgentSession): void {
	s.updatedAt = Date.now();
}

function evict(s: AgentSession): void {
	sessions.delete(s.key);
	s.pending = null;
}

export function createSession(userId: string, key: string | undefined, systemPrompt: string): AgentSession {
	if (key && SESSION_KEY_RE.test(key)) {
		const existing = sessions.get(key);
		if (existing && existing.userId === userId && Date.now() - existing.updatedAt < SESSION_TTL_MS) {
			touch(existing);
			return existing;
		}
		if (existing) evict(existing);
	}

	// Alte Sessions des Users raus, damit die Map nicht wächst.
	for (const s of sessions.values()) {
		if (s.userId !== userId) continue;
		if (Date.now() - s.updatedAt >= SESSION_TTL_MS) {
			evict(s);
			continue;
		}
		const userSessions = [...sessions.values()].filter((x) => x.userId === userId);
		if (userSessions.length >= MAX_SESSIONS_PER_USER) {
			const oldest = userSessions.reduce((a, b) => (a.updatedAt < b.updatedAt ? a : b));
			if (oldest.updatedAt < Date.now() - SESSION_TTL_MS * 0.5) evict(oldest);
		}
	}

	const keyFinal = key && SESSION_KEY_RE.test(key) ? key : randomUUID();
	const now = Date.now();
	const session: AgentSession = {
		key: keyFinal,
		userId,
		createdAt: now,
		updatedAt: now,
		messages: [{ role: 'system', content: systemPrompt }],
		pending: null
	};
	sessions.set(keyFinal, session);
	return session;
}

export function getSession(key: string, userId: string): AgentSession | null {
	const s = sessions.get(key);
	if (!s || s.userId !== userId) return null;
	if (Date.now() - s.updatedAt >= SESSION_TTL_MS) {
		evict(s);
		return null;
	}
	return s;
}

/** System-Prompt aktualisieren (Config kann sich geändert haben). */
export function setSystemPrompt(s: AgentSession, systemPrompt: string): void {
	s.messages[0] = { role: 'system', content: systemPrompt };
	touch(s);
}

/** Nutzer-Message anhängen (mit Beschränkung der Historie). */
export function appendMessage(s: AgentSession, msg: AgentMsg): void {
	s.messages.push(msg);
	while (s.messages.length > MAX_MESSAGES) s.messages.splice(1, 1);
	touch(s);
}

export function setPending(s: AgentSession, pending: PendingApproval | null): void {
	s.pending = pending;
	touch(s);
}

export function allSessionKeys(): string[] {
	return [...sessions.keys()];
}
