// POST /api/notify/test — Webhook testen.
// Sendet eine Beispiel-Nachricht; manche Empfänger antworten mit 202 und
// einem Ergebnis-Header x-t3-hook-outcome (z. B. „accepted").
// Die Formularwerte (url/token/prompt) werden getestet; leere Werte
// fallen auf die gespeicherte Config zurück.

import { json } from '@sveltejs/kit';
import { readJsonBody } from '$server/auth/apiHelpers';
import { withUser } from '$server/lib/route';
import { DEFAULT_NOTIFY_PROMPT, getNotify, webhookUrlOf } from '$server/store/notify';
import { composeMessage, dateKey, postNotify } from '$server/jobs/notify';
import type { TaskItem } from '$lib/types';

export const POST = withUser(async ({ request, locals }) => {
	const body = await readJsonBody<{ url?: string; token?: string; prompt?: string }>(request);

	const saved = getNotify(locals.user.id);
	const url =
		typeof body?.url === 'string' && body.url.trim() !== '' ? body.url.trim() : saved?.url ?? '';
	const token =
		typeof body?.token === 'string' && body.token.trim() !== ''
			? body.token.trim()
			: saved?.token ?? '';
	const prompt =
		typeof body?.prompt === 'string' && body.prompt.trim() !== ''
			? body.prompt
			: saved?.prompt || DEFAULT_NOTIFY_PROMPT;

	if (!url || !token) {
		return json({ ok: false, error: 'Bitte Webhook-URL und Token angeben.' }, { status: 400 });
	}

	const now = new Date();
	const sample: TaskItem = {
		id: 'notify-test',
		uid: 'notify-test',
		calendarId: 'test',
		calendarName: 'Test',
		calendarColor: '#000000',
		summary: 'Testnachricht von Horizont (Einstellungen → Benachrichtigung (Webhook))',
		completed: false
	};
	const text = composeMessage(prompt, [sample], now);

	try {
		const res = await postNotify(webhookUrlOf({ url, token }), text, dateKey(now));
		const outcome = res.headers.get('x-t3-hook-outcome') ?? undefined;
		if (res.ok) {
			return json({ ok: true, status: res.status, outcome });
		}
		return json({ ok: false, status: res.status, outcome, error: `Webhook hat ${res.status} geantwortet` });
	} catch (e) {
		const msg = e instanceof Error ? e.message : String(e);
		return json({ ok: false, error: msg });
	}
});
