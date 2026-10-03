// POST /api/auth/login

import { json } from '@sveltejs/kit';
import type { RequestHandler } from '@sveltejs/kit';
import { SESSION_COOKIE, createSession } from '$server/auth/sessionStore';
import {
	clientIp,
	jsonErr,
	rateLimited,
	readJsonBody,
	sessionCookieOptions
} from '$server/auth/apiHelpers';
import {
	getUserByUsername,
	publicUser,
	touchLastLogin,
	verifyPassword
} from '$server/auth/userStore';

export const POST: RequestHandler = async (event) => {
	const { request, cookies } = event;
	const body = await readJsonBody<{ username?: string; password?: string }>(request);
	if (!body) return json({ error: 'Ungültiger JSON-Body.' }, { status: 400 });

	if (rateLimited(clientIp(request))) {
		return json(
			{ error: 'Zu viele Login-Versuche. Bitte in einer Minute erneut versuchen.' },
			{ status: 429 }
		);
	}

	const username = typeof body.username === 'string' ? body.username.trim() : '';
	const password = typeof body.password === 'string' ? body.password : '';
	const user = username ? getUserByUsername(username) : null;

	// Gleiches Fehlerbild bei unbekanntem User wie bei falschem Passwort.
	const valid = user != null && !user.disabled && verifyPassword(user, password);
	if (!valid) {
		return json({ error: 'Benutzername oder Passwort ist falsch.' }, { status: 401 });
	}

	touchLastLogin(user.id);
	const token = createSession(user.id);
	cookies.set(SESSION_COOKIE, token, sessionCookieOptions(event));
	return json({ ok: true, user: publicUser(user) });
};
