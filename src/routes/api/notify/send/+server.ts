// POST /api/notify/send — manueller Versand („Jetzt senden").
// Sendet JETZT sofort die aktuellen offenen Tasks an die gespeicherte
// Webhook-URL (gleiche Nachrichten-Komposition wie der automatische Job)
// und aktualisiert den Lauf-Status — unabhängig von der frequency-
// Einstellung (also auch, wenn Automatik auf „Nur manuell" steht).

import { json } from '@sveltejs/kit';
import type { RequestHandler } from '@sveltejs/kit';
import { getNotify } from '$server/store/notify';
import { sendMessageForUser } from '$server/jobs/notify';

export const POST: RequestHandler = async ({ locals }) => {
	if (!locals.user) return json({ error: 'Nicht angemeldet.' }, { status: 401 });

	const cfg = getNotify(locals.user.id);
	if (!cfg || !cfg.url || !cfg.token) {
		return json(
			{ ok: false, error: 'Bitte zuerst Webhook-URL und Zugriffsschlüssel speichern.' },
			{ status: 400 }
		);
	}
	const result = await sendMessageForUser(locals.user.id, cfg, new Date());
	return json(result);
};
