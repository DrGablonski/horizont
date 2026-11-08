// GET /api/auth/me — aktueller User (401 via hooks.server, falls keine Session).

import { json } from '@sveltejs/kit';
import type { RequestHandler } from '@sveltejs/kit';

export const GET: RequestHandler = ({ locals }) => {
	if (!locals.user) return json({ error: 'Nicht angemeldet.' }, { status: 401 });
	return json({ user: locals.user });
};
