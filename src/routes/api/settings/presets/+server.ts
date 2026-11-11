// Anbieter-Vorlagen für das Verbindungsformular (statisch, ohne Secrets).
// Liegt hinter der allgemeinen /api/-Auth der Hooks — das Formular lebt in den
// angemeldeten Einstellungen, eine öffentliche Ausnahme braucht es nicht.
// Inhalte laut Design-Kontrakt „Mehrkalender & fremde CalDAV-Server“, Abschnitt 4.

import { json } from '@sveltejs/kit';
import type { RequestHandler } from '@sveltejs/kit';
import type { ProviderPreset } from '$lib/types';

// Google unterstützt kein CalDAV mit Passwort (nur OAuth2) → leere URL + Hinweis.
const PRESETS: ProviderPreset[] = [
	{
		id: 'icloud',
		label: 'iCloud',
		url: 'https://caldav.icloud.com',
		usernameLabel: 'Apple-ID',
		hint: 'Apple-ID und app-spezifisches Passwort (appleid.apple.com) verwenden; Kalender-Anlage ist bei Apple oft untersagt (403).',
		supportsCalendarCreation: false
	},
	{
		id: 'google',
		label: 'Google Calendar',
		url: '',
		usernameLabel: 'Benutzername',
		hint: 'Google Calendar spricht kein CalDAV mit Passwort (nur OAuth2) — bitte einen CalDAV-tauglichen Anbieter verbinden',
		supportsCalendarCreation: false
	},
	{
		id: 'fastmail',
		label: 'Fastmail',
		url: 'https://caldav.fastmail.com/dav/',
		usernameLabel: 'E-Mail-Adresse',
		hint: 'App-Passwort (nicht das reguläre Passwort) verwenden.',
		supportsCalendarCreation: true
	},
	{
		id: 'nextcloud',
		label: 'Nextcloud',
		url: 'https://<host>/remote.php/dav/',
		usernameLabel: 'Benutzername',
		hint: 'Benutzername und (App-)Passwort des eigenen Servers.',
		supportsCalendarCreation: true
	},
	{
		id: 'radicale',
		label: 'Radicale',
		url: 'https://<host>:5232/',
		usernameLabel: 'Benutzername',
		hint: 'Eigener Radicale-Server.',
		supportsCalendarCreation: true
	},
	{
		id: 'bailkal',
		label: 'Baïkal',
		url: 'https://<host>/dav.php',
		usernameLabel: 'Benutzername',
		hint: 'Eigener Baïkal-Server.',
		supportsCalendarCreation: true
	},
	{
		id: 'generic',
		label: 'Eigener Server',
		url: '',
		usernameLabel: 'Benutzername',
		hint: 'Eigene CalDAV-URL.',
		supportsCalendarCreation: true
	}
];

// Reine Lesehilfe fürs Formular — keine Session erforderlich, keine Secrets enthalten.
export const GET: RequestHandler = () => {
	return json({ presets: PRESETS });
};
