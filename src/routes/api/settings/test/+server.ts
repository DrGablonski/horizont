import { json } from '@sveltejs/kit';
import { listCalendars, resolveHome } from '$server/caldav/client';
import { getSettings } from '$server/store/store';
import type { CalDavSettings, TestResult } from '$lib/types';

export async function POST({ request }: { request: Request }) {
	const body = (await request.json().catch(() => null)) as Partial<CalDavSettings> | null;
	let settings: CalDavSettings | null;

	// Formularwerte testen, falls eine URL übermittelt wurde; sonst gespeicherte Daten.
	if (body && typeof body.url === 'string' && body.url.trim()) {
		const current = getSettings();
		const url = body.url.trim().replace(/\/+$/, '');
		const username = typeof body.username === 'string' ? body.username.trim() : '';
		const incomingPassword = typeof body.password === 'string' ? body.password.trim() : '';
		const password = incomingPassword !== '' ? incomingPassword : (current?.password ?? '').trim();
		settings = { url, username, password };
	} else {
		settings = getSettings();
	}

	if (!settings) {
		return json({ error: 'Keine Einstellungen gespeichert.' }, { status: 400 });
	}
	try {
		const { home } = await resolveHome(settings);
		const calendars = await listCalendars(settings, home);
		const result: TestResult = { ok: true, calendars, eventCount: 0 };
		return json(result);
	} catch (e) {
		const result: TestResult = {
			ok: false,
			error: e instanceof Error ? e.message : String(e),
			calendars: [],
			eventCount: 0
		};
		return json(result);
	}
}
