// POST /api/auth/logout

import { json } from '@sveltejs/kit';
import type { RequestHandler } from '@sveltejs/kit';
import { SESSION_COOKIE, destroySession } from '$server/auth/sessionStore';
import { sessionCookieOptions } from '$server/auth/apiHelpers';

export const POST: RequestHandler = ({ request, cookies }) => {
	const token = cookies.get(SESSION_COOKIE);
	if (token) destroySession(token);
	cookies.delete(SESSION_COOKIE, sessionCookieOptions(request));
	return json({ ok: true });
};
