// POST /api/settings/test — eine Verbindung testen (Formularwerte oder gespeicherte id).

import { json } from '@sveltejs/kit';
import { readJsonBody } from '$server/auth/apiHelpers';
import { withUser } from '$server/lib/route';
import { listCalendars, normalizeCalDavUrl, resolveHome } from '$server/caldav/client';
import { listConnections } from '$server/store/connections';
import type { CalDavSettings, TestResult } from '$lib/types';

export const POST = withUser(async ({ request, locals }) => {
	const body = await readJsonBody<{
		id?: string;
		url?: string;
		username?: string;
		password?: string;
	}>(request);

	let settings: CalDavSettings | null = null;

	if (body && typeof body.url === 'string' && body.url.trim()) {
		// Formularwerte testen (unabhängig von gespeicherten Daten).
		const url = normalizeCalDavUrl(body.url).replace(/\/+$/, '');
		const username = typeof body.username === 'string' ? body.username.trim() : '';
		const password = typeof body.password === 'string' ? body.password.trim() : '';
		settings = { url, username, password };
	} else if (body && typeof body.id === 'string' && body.id) {
		// Gespeicherte Verbindung testen.
		const conn = listConnections(locals.user.id).find((c) => c.id === body.id);
		if (conn) settings = { url: conn.url, username: conn.username, password: conn.password };
	}

	if (!settings) {
		return json({ error: 'Keine Verbindung zum Testen angegeben.' }, { status: 400 });
	}

	try {
		const { home } = await resolveHome(settings);
		const calendars = await listCalendars(settings, home);
		const result: TestResult = { ok: true, calendars, eventCount: 0 };
		return json(result);
	} catch (e) {
		// Test-Antwort bleibt unabhängig vom Fehler 200 mit ok:false.
		const result: TestResult = {
			ok: false,
			error: e instanceof Error ? e.message : String(e),
			calendars: [],
			eventCount: 0
		};
		return json(result);
	}
});
