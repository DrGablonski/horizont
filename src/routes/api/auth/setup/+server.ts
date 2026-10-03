// POST /api/auth/setup — einmalige Erstellung des ersten Admins.
// Öffentlicher Endpunkt nur, solange noch kein User existiert (hooks.server).

import { json } from '@sveltejs/kit';
import type { RequestHandler } from '@sveltejs/kit';
import { SESSION_COOKIE, createSession } from '$server/auth/sessionStore';
import {
	jsonErr,
	rateLimited,
	clientIp,
	readJsonBody,
	sessionCookieOptions
} from '$server/auth/apiHelpers';
import { createUser, hasUsers, publicUser } from '$server/auth/userStore';
import { migrateLegacySettings } from '$server/store/connections';

export const POST: RequestHandler = async ({ request, cookies }) => {
	if (hasUsers()) {
		return json({ error: 'Setup ist bereits abgeschlossen.' }, { status: 403 });
	}
	if (rateLimited(clientIp(request))) {
		return json({ error: 'Zu viele Versuche. Bitte in einer Minute erneut versuchen.' }, { status: 429 });
	}

	const body = await readJsonBody<{ username?: string; password?: string }>(request);
	if (!body) return json({ error: 'Ungültiger JSON-Body.' }, { status: 400 });

	const username = typeof body.username === 'string' ? body.username.trim() : '';
	const password = typeof body.password === 'string' ? body.password : '';

	try {
		const user = createUser({ username, password, role: 'admin' });
		// Vorhandene Einzel-User-Konfiguration (data/settings.json) dem Admin
		// als zugewiesene Verbindung zuordnen und die Datei archivieren.
		migrateLegacySettings(user.id);
		const token = createSession(user.id);
		cookies.set(SESSION_COOKIE, token, sessionCookieOptions(request));
		return json({ ok: true, user: publicUser(user) });
	} catch (e) {
		return json(jsonErr(e), { status: 400 });
	}
};
