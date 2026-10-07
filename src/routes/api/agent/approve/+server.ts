// KI-Agent: Bestätigung/Verwerfung einer Write-Aktion (SSE-Stream für den Fortschritt).
//
//   POST { sessionKey, approvalId, decision: 'accept' | 'reject', note? }
//
// Der Stream liefert dieselben Events wie /api/agent/chat und endet mit
// 'done' oder einem neuen 'approval' (weitere ausstehende Writes).

import { json } from '@sveltejs/kit';
import type { RequestHandler } from '@sveltejs/kit';
import { resolveAgent } from '$server/agent/configStore';
import { getSession } from '$server/agent/sessions';
import { resume } from '$server/agent/loop';
import { sseResponse } from '$server/agent/sse';
import { agentRateLimited } from '$server/agent/ratelimit';
import { clientIp } from '$server/auth/apiHelpers';

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
		sessionKey?: string;
		approvalId?: string;
		decision?: string;
		note?: string;
	} | null;
	const sessionKey = typeof body?.sessionKey === 'string' ? body.sessionKey : '';
	const approvalId = typeof body?.approvalId === 'string' ? body.approvalId : '';
	const decision =
		body?.decision === 'accept' || body?.decision === 'reject' ? body.decision : null;
	const note = typeof body?.note === 'string' ? body.note.trim() : '';

	if (!sessionKey || !approvalId || !decision) {
		return json({ error: 'Unvollständige Anfrage.' }, { status: 400 });
	}

	const session = getSession(sessionKey, user.id);
	if (!session || !session.pending || session.pending.approvalId !== approvalId) {
		return json({ error: 'Bestätigung ist nicht mehr gültig.' }, { status: 410 });
	}

	const config = resolved.config;
	const signal = request.signal;

	return sseResponse(async (send) => {
		await resume({ session, config, signal, send }, approvalId, decision, note || undefined);
	});
};
