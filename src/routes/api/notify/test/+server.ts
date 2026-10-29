// POST /api/notify/test — Webhook testen (Formularwert oder gespeicherte URL).
// Sendet eine Beispiel-Nachricht; T3 Code antwortet mit 202 und
// dem Header x-t3-hook-outcome (z. B. „accepted").

import { json } from '@sveltejs/kit';
import type { RequestHandler } from '@sveltejs/kit';
import { getNotify } from '$server/store/notify';
import { dateKey, formatNotifyMessage, postNotify } from '$server/jobs/notify';
import type { TaskItem } from '$lib/types';

export const POST: RequestHandler = async ({ request, locals }) => {
	if (!locals.user) return json({ error: 'Nicht angemeldet.' }, { status: 401 });

	const body = (await request.json().catch(() => null)) as { webhookUrl?: string } | null;
	const saved = getNotify(locals.user.id)?.webhookUrl ?? '';
	const url =
		typeof body?.webhookUrl === 'string' && body.webhookUrl.trim() !== ''
			? body.webhookUrl.trim()
			: saved;
	if (!url) {
		return json({ ok: false, error: 'Keine Webhook-URL angegeben.' }, { status: 400 });
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
	const text = formatNotifyMessage([sample], now);

	try {
		const res = await postNotify(url, text, dateKey(now));
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
