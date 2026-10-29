// Per-User-Webhook-Config (Tägliche-Schul-Tasks-Benachrichtigung):
//   GET  → View (ohne die rohe URL; Token bleibt serverseitig)
//   POST → speichern (leere webhookUrl = gespeicherte beibehalten)

import { json } from '@sveltejs/kit';
import type { RequestHandler } from '@sveltejs/kit';
import { getNotifyView, saveNotify } from '$server/store/notify';
import type { NotifySaveInput } from '$lib/types';

export const GET: RequestHandler = ({ locals }) => {
	if (!locals.user) return json({ error: 'Nicht angemeldet.' }, { status: 401 });
	return json(getNotifyView(locals.user.id));
};

export const POST: RequestHandler = async ({ request, locals }) => {
	if (!locals.user) return json({ error: 'Nicht angemeldet.' }, { status: 401 });

	const body = (await request.json().catch(() => null)) as Partial<NotifySaveInput> | null;
	if (!body || typeof body.enabled !== 'boolean' || typeof body.time !== 'string') {
		return json({ error: 'Ungültige Eingaben.' }, { status: 400 });
	}
	try {
		saveNotify(locals.user.id, {
			enabled: body.enabled,
			time: body.time,
			webhookUrl: typeof body.webhookUrl === 'string' ? body.webhookUrl : undefined
		});
		return json(getNotifyView(locals.user.id));
	} catch (e) {
		return json({ error: e instanceof Error ? e.message : 'Ungültige Eingaben.' }, { status: 400 });
	}
};
