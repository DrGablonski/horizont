// Per-User API-Token (Maschinen-Auth für /api/*, z. B. für T3 Code):
//   GET    → Status (vorhanden? erstellt? zuletzt genutzt?)
//   POST   → neuen Token erzeugen (ersetzt vorhandenen) — Klartext nur einmal
//   DELETE → Token ablehnen

import { json } from '@sveltejs/kit';
import type { RequestHandler } from '@sveltejs/kit';
import { generateApiToken, getApiTokenView, revokeApiToken } from '$server/auth/apiToken';
import type { ApiTokenGenerated } from '$lib/types';

export const GET: RequestHandler = ({ locals }) => {
	if (!locals.user) return json({ error: 'Nicht angemeldet.' }, { status: 401 });
	return json(getApiTokenView(locals.user.id));
};

export const POST: RequestHandler = ({ locals }) => {
	if (!locals.user) return json({ error: 'Nicht angemeldet.' }, { status: 401 });
	const res: ApiTokenGenerated = generateApiToken(locals.user.id);
	return json(res, { status: 201 });
};

export const DELETE: RequestHandler = ({ locals }) => {
	if (!locals.user) return json({ error: 'Nicht angemeldet.' }, { status: 401 });
	revokeApiToken(locals.user.id);
	return json({ ok: true });
};
