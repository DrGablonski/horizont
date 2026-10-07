// KI-Agent: Status + Chat (SSE).
//
//   GET  → Status (steht eine Agent-Config bereit?) – Layout mountet das Widget danach.
//   POST → Chat-Nachricht; antwortet mit einem SSE-Stream:
//          delta / tool_result / approval / done / error.
//          Endet der Stream bei 'approval', wartet die Loop auf
//          POST /api/agent/approve (selbe sessionKey + approvalId).

import { json } from '@sveltejs/kit';
import type { RequestHandler } from '@sveltejs/kit';
import { resolveAgent } from '$server/agent/configStore';
import { createSession, setSystemPrompt } from '$server/agent/sessions';
import { buildSystemPrompt } from '$server/agent/prompt';
import { startTurn, resume } from '$server/agent/loop';
import { sseResponse } from '$server/agent/sse';
import { agentRateLimited } from '$server/agent/ratelimit';
import { clientIp } from '$server/auth/apiHelpers';

export const GET: RequestHandler = ({ locals }) => {
	const user = locals.user;
	if (!user) return json({ error: 'Nicht angemeldet.' }, { status: 401 });
	const resolved = resolveAgent(user.id);
	if (!resolved) {
		return json({ available: false, source: null, provider: null, model: null, baseUrl: null });
	}
	return json({
		available: true,
		source: resolved.source,
		provider: resolved.config.provider,
		model: resolved.config.model,
		baseUrl: resolved.config.baseUrl
	});
};

export const POST: RequestHandler = async ({ request, locals }) => {
	const user = locals.user;
	if (!user) return json({ error: 'Nicht angemeldet.' }, { status: 401 });

	const resolved = resolveAgent(user.id);
	if (!resolved) {
		return json({ error: 'KI-Agent ist nicht konfiguriert.' }, { status: 404 });
	}
	if (agentRateLimited(clientIp(request))) {
		return json({ error: 'Zu viele Anfragen – bitte kurz warten.' }, { status: 429 });
	}

	const body = (await request.json().catch(() => null)) as {
		message?: string;
		sessionKey?: string;
	} | null;
	const message = typeof body?.message === 'string' ? body.message.trim() : '';
	if (message.length === 0) return json({ error: 'Nachricht fehlt.' }, { status: 400 });
	if (message.length > 2000) {
		return json({ error: 'Nachricht ist zu lang (max. 2000 Zeichen).' }, { status: 400 });
	}

	const sessionKey = typeof body?.sessionKey === 'string' ? body.sessionKey : undefined;
	const session = createSession(user.id, sessionKey, buildSystemPrompt());
	setSystemPrompt(session, buildSystemPrompt());
	const config = resolved.config;
	const signal = request.signal;

	return sseResponse(async (send) => {
		if (session.pending) {
			// Statt auf der Karte zu antworten hat der User getippt →
			// als Ablehnung mit Korrektur interpretieren.
			await resume(
				{ session, config, signal, send },
				session.pending.approvalId,
				'reject',
				message
			);
		} else {
			await startTurn({ session, config, signal, send }, message);
		}
	});
};
