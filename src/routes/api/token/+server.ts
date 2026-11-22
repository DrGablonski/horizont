// Per-User API-Token (Maschinen-Auth für /api/*, z. B. für externe Tools/MCP):
//   GET    → Status (vorhanden? erstellt? zuletzt genutzt?)
//   POST   → neuen Token erzeugen (ersetzt vorhandenen) — Klartext nur einmal
//   DELETE → Token ablehnen

import { json } from '@sveltejs/kit';
import { withUser } from '$server/lib/route';
import { generateApiToken, getApiTokenView, revokeApiToken } from '$server/auth/apiToken';
import type { ApiTokenGenerated } from '$lib/types';

export const GET = withUser(({ locals }) => json(getApiTokenView(locals.user.id)));

export const POST = withUser(({ locals }) => {
	const res: ApiTokenGenerated = generateApiToken(locals.user.id);
	return json(res, { status: 201 });
});

export const DELETE = withUser(({ locals }) => {
	revokeApiToken(locals.user.id);
	return json({ ok: true });
});
