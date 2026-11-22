// GET /api/auth/me — aktueller User (401 via hooks.server, falls keine Session).

import { json } from '@sveltejs/kit';
import { withUser } from '$server/lib/route';

export const GET = withUser(({ locals }) => json({ user: locals.user }));
