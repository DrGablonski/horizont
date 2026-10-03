// POST /api/auth/setup — einmalige Erstellung des ersten Admins.
// Öffentlicher Endpunkt nur, solange noch kein User existiert (hooks.server).
//
// Optional: System-CalDAV-Konfiguration (Basis-URL + Admin-API-URL) — wird dann
// hinterlegt und dem Admin direkt ein CalDAV-Account angelegt. Scheitert die
// CalDAV-Anlage, bleibt das Setup trotzdem erfolgreich (caldavError wird
// gemeldet; nachgeholt werden kann das unter /admin).

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
import { saveSystemCaldav } from '$server/store/system';
import { ensureCaldavForUser } from '$server/admin/provision';
import type { SetupResult } from '$lib/types';

export const POST: RequestHandler = async (event) => {
	const { request, cookies } = event;
	if (hasUsers()) {
		return json({ error: 'Setup ist bereits abgeschlossen.' }, { status: 403 });
	}
	if (rateLimited(clientIp(request))) {
		return json({ error: 'Zu viele Versuche. Bitte in einer Minute erneut versuchen.' }, { status: 429 });
	}

	const body = await readJsonBody<{
		username?: string;
		password?: string;
		caldav?: { baseUrl?: string; adminApiUrl?: string; adminToken?: string };
	}>(request);
	if (!body) return json({ error: 'Ungültiger JSON-Body.' }, { status: 400 });

	const username = typeof body.username === 'string' ? body.username.trim() : '';
	const password = typeof body.password === 'string' ? body.password : '';

	// Optionale System-CalDAV-Konfiguration (nur wirksam, wenn beide URLs
	// angegeben sind).
	const cBaseUrl =
		typeof body.caldav?.baseUrl === 'string' ? body.caldav.baseUrl.trim().replace(/\/+$/, '') : '';
	const cAdminApiUrl =
		typeof body.caldav?.adminApiUrl === 'string' ? body.caldav.adminApiUrl.trim().replace(/\/+$/, '') : '';
	const cToken = typeof body.caldav?.adminToken === 'string' ? body.caldav.adminToken.trim() : '';
	const hasCaldav = Boolean(cBaseUrl || cAdminApiUrl);
	if (hasCaldav && (!cBaseUrl || !cAdminApiUrl)) {
		return json(
			{ error: 'System-CalDAV: Basis-URL und Admin-API-URL werden zusammen benötigt.' },
			{ status: 400 }
		);
	}

	try {
		const user = createUser({ username, password, role: 'admin' });
		// Vorhandene Einzel-User-Konfiguration (data/settings.json) dem Admin
		// als zugewiesene Verbindung zuordnen und die Datei archivieren.
		migrateLegacySettings(user.id);

		// Optional: System-CalDAV hinterlegen + Admin-CalDAV-Account anlegen.
		// Fehler sind nicht fatal — das Setup gilt trotzdem als abgeschlossen.
		let caldav: SetupResult['caldav'] = null;
		let caldavError: string | null = null;
		if (hasCaldav) {
			try {
				saveSystemCaldav({
					baseUrl: cBaseUrl,
					adminApiUrl: cAdminApiUrl,
					adminToken: cToken || undefined
				});
				caldav = await ensureCaldavForUser(user.id, username);
			} catch (e) {
				caldavError = e instanceof Error ? e.message : String(e);
			}
		}

		const token = createSession(user.id);
		cookies.set(SESSION_COOKIE, token, sessionCookieOptions(event));
		return json({ ok: true, user: publicUser(user), caldav, caldavError } satisfies SetupResult);
	} catch (e) {
		return json(jsonErr(e), { status: 400 });
	}
};
