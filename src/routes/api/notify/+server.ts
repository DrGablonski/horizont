// Per-User-Webhook-Config (Tasks-Benachrichtigung per Webhook):
//   GET  → View (ohne den rohen Token)
//   POST → speichern (leere Felder = gespeicherte Werte beibehalten)

import { json } from '@sveltejs/kit';
import type { RequestHandler } from '@sveltejs/kit';
import { getNotifyView, saveNotify } from '$server/store/notify';
import { normalizeCategoryName } from '$lib/categories';
import type { NotifyFrequency, NotifySaveInput } from '$lib/types';

const FREQUENCIES: NotifyFrequency[] = ['manual', 'daily', 'weekly', 'interval'];

export const GET: RequestHandler = ({ locals }) => {
	if (!locals.user) return json({ error: 'Nicht angemeldet.' }, { status: 401 });
	return json(getNotifyView(locals.user.id));
};

export const POST: RequestHandler = async ({ request, locals }) => {
	if (!locals.user) return json({ error: 'Nicht angemeldet.' }, { status: 401 });

	const body = (await request.json().catch(() => null)) as Partial<NotifySaveInput> | null;
	if (!body || typeof body.time !== 'string') {
		return json({ error: 'Ungültige Eingaben.' }, { status: 400 });
	}
	// frequency: direkt oder (alt) als enabled-Boolean übermittelt.
	let frequency: NotifyFrequency | undefined;
	if (typeof body.frequency === 'string' && FREQUENCIES.includes(body.frequency)) {
		frequency = body.frequency;
	} else if (typeof (body as { enabled?: unknown }).enabled === 'boolean') {
		frequency = (body as { enabled: boolean }).enabled ? 'daily' : 'manual';
	}
	if (!frequency) return json({ error: 'Ungültige Eingaben.' }, { status: 400 });
	// categories: Array gültiger Kategoriennamen; fehlend = gespeichert behalten.
	let categories: string[] | undefined;
	if (body.categories !== undefined) {
		if (!Array.isArray(body.categories)) return json({ error: 'Ungültige Kategorien.' }, { status: 400 });
		categories = body.categories.map((c) => normalizeCategoryName(c) ?? '').filter((c) => c !== '');
	}
	try {
		saveNotify(locals.user.id, {
			frequency,
			time: body.time,
			weekday: typeof body.weekday === 'number' ? body.weekday : undefined,
			intervalHours: typeof body.intervalHours === 'number' ? body.intervalHours : undefined,
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
