import { json } from '@sveltejs/kit';
import { getSettings, getSettingsView, saveSettings } from '$server/store/store';
import type { CalDavSettings } from '$lib/types';

export function GET() {
	return json(getSettingsView());
}

export async function POST({ request }: { request: Request }) {
	const body = (await request.json().catch(() => null)) as Partial<CalDavSettings> | null;
	if (!body || typeof body.url !== 'string' || !body.url.trim()) {
		return json({ error: 'CalDAV-URL fehlt.' }, { status: 400 });
	}
	const url = body.url.trim().replace(/\/+$/, '');
	const username = typeof body.username === 'string' ? body.username.trim() : '';
	const incomingPassword = typeof body.password === 'string' ? body.password.trim() : '';
	// Leeres Passwort = „beibehalten", wenn bereits eines hinterlegt ist.
	const current = getSettings();
	const password = incomingPassword !== '' ? incomingPassword : (current?.password ?? '').trim();
	saveSettings({ url, username, password });
	return json(getSettingsView());
}
