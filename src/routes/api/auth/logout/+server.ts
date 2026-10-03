// POST /api/auth/logout

import { json } from '@sveltejs/kit';
import type { RequestHandler } from '@sveltejs/kit';
import { SESSION_COOKIE, destroySession } from '$server/auth/sessionStore';

export const POST: RequestHandler = ({ cookies }) => {
	const token = cookies.get(SESSION_COOKIE);
	if (token) destroySession(token);
	cookies.delete(SESSION_COOKIE, { path: '/' });
	return json({ ok: true });
};
