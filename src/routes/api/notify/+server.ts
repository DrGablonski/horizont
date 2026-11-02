// Per-User-Webhook-Config (Tägliche-Schul-Tasks-Benachrichtigung):
//   GET  → View (ohne den rohen Token)
//   POST → speichern (leere Felder = gespeicherte Werte beibehalten)

import { json } from '@sveltejs/kit';
import type { RequestHandler } from '@sveltejs/kit';
import { getNotifyView, saveNotify } from '$server/store/notify';
import { normalizeCategoryName } from '$lib/categories';
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
	// categories: Array gültiger Kategoriennamen; fehlend = gespeichert behalten.
	let categories: string[] | undefined;
	if (body.categories !== undefined) {
		if (!Array.isArray(body.categories)) return json({ error: 'Ungültige Kategorien.' }, { status: 400 });
		categories = body.categories.map((c) => normalizeCategoryName(c) ?? '').filter((c) => c !== '');
	}
	try {
		saveNotify(locals.user.id, {
			enabled: body.enabled,
			time: body.time,
			url: typeof body.url === 'string' ? body.url : undefined,
			token: typeof body.token === 'string' ? body.token : undefined,
			prompt: typeof body.prompt === 'string' ? body.prompt : undefined,
			categories
		});
		return json(getNotifyView(locals.user.id));
	} catch (e) {
		return json({ error: e instanceof Error ? e.message : 'Ungültige Eingaben.' }, { status: 400 });
	}
};
