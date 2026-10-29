// POST /api/notify/test — Webhook testen.
// Sendet eine Beispiel-Nachricht; T3 Code antwortet mit 202 und
// dem Header x-t3-hook-outcome (z. B. „accepted").
// Die Formularwerte (url/token/prompt) werden getestet; leere Werte
// fallen auf die gespeicherte Config zurück.

import { json } from '@sveltejs/kit';
import type { RequestHandler } from '@sveltejs/kit';
import { DEFAULT_NOTIFY_PROMPT, getNotify, webhookUrlOf } from '$server/store/notify';
import { composeMessage, dateKey, postNotify } from '$server/jobs/notify';
import type { TaskItem } from '$lib/types';

export const POST: RequestHandler = async ({ request, locals }) => {
	if (!locals.user) return json({ error: 'Nicht angemeldet.' }, { status: 401 });

	const body = (await request.json().catch(() => null)) as {
		url?: string;
		token?: string;
		prompt?: string;
	} | null;

	const saved = getNotify(locals.user.id);
	let url =
		typeof body?.url === 'string' && body.url.trim() !== '' ? body.url.trim() : saved?.url ?? '';
	let token =
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
		summary: 'Testnachricht von Horizont (Einstellungen → Benachrichtigung)',
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
};
