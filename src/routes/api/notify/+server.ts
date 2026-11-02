// Per-User-Webhook-Config (Tägliche-Schul-Tasks-Benachrichtigung):
//   GET  → View (ohne den rohen Token)
//   POST → speichern (leere Felder = gespeicherte Werte beibehalten)

import { json } from '@sveltejs/kit';
import type { RequestHandler } from '@sveltejs/kit';
import { getNotifyView, saveNotify } from '$server/store/notify';
import { PRIORITY_BUCKETS, type PriorityBucket } from '$lib/priorities';
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
	// priorities: Array mit nur gültigen Buckets (1/5/9); fehlend = gespeichert behalten.
	let priorities: PriorityBucket[] | undefined;
	if (body.priorities !== undefined) {
		if (!Array.isArray(body.priorities)) return json({ error: 'Ungültige Prioritäten.' }, { status: 400 });
		priorities = body.priorities.filter((p): p is PriorityBucket =>
			(PRIORITY_BUCKETS as readonly unknown[]).includes(p)
		);
	}
	try {
		saveNotify(locals.user.id, {
			enabled: body.enabled,
			time: body.time,
			url: typeof body.url === 'string' ? body.url : undefined,
			token: typeof body.token === 'string' ? body.token : undefined,
			prompt: typeof body.prompt === 'string' ? body.prompt : undefined,
			priorities
		});
		return json(getNotifyView(locals.user.id));
	} catch (e) {
		return json({ error: e instanceof Error ? e.message : 'Ungültige Eingaben.' }, { status: 400 });
	}
};
