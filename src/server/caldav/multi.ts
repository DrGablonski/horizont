// Multi-Connection-Auflösung: alle CalDAV-Verbindungen eines Users abfragen,
// Kalender aggregieren (mit Verbindungsname) und Kalender über alle
// Verbindungen hinweg finden (für Write-Operationen).

import type { CalDavCalendar, CalDavConnection } from '$lib/types';
import { collectionExists, listCalendars, mkCalendar, resolveHome } from '$server/caldav/client';

export interface ResolvedCalendar {
	connection: CalDavConnection;
	calendar: CalDavCalendar; // enthält connectionName
}

export interface ResolvedAll {
	items: ResolvedCalendar[];
	errors: string[];
}

// Pfad + Name des Standard-Kalenders, den ein frisch angelegter
// System-CALDAV-Account erhält, damit sofort Events angelegt werden können.
const DEFAULT_CAL_SEG = 'main';
const DEFAULT_CAL_NAME = 'Mein Kalender';

/**
 * Löst eine Verbindung ab und liefert ihre Kalender. Für „assigned"-
 * Verbindungen (System-CALDAV) wird ein frischer, leerer Account mit genau
 * einem Standard-Kalender (VEVENT + VTODO) versorgt – CalDAV-Server wie
 * Radicale legen bei der User-Anlage keinen Starter-Kalender an. Externe
 * Verbindungen (vom User selbst hinzugefügt) bleiben unberührt.
 */
async function resolveConnectionCalendars(conn: CalDavConnection): Promise<CalDavCalendar[]> {
	const { home } = await resolveHome(conn);
	let calendars = await listCalendars(conn, home);
	if (conn.kind === 'assigned' && calendars.length === 0) {
		const url = `${home.replace(/\/?$/, '/')}${DEFAULT_CAL_SEG}`;
		if (!(await collectionExists(conn, url))) {
			await mkCalendar(conn, url, DEFAULT_CAL_NAME, ['VEVENT', 'VTODO']);
			calendars = await listCalendars(conn, home);
		}
	}
	return calendars;
}

/**
 * Löst alle Verbindungen des Users ab und liefert alle Kalender.
 * Fehler einzelner Verbindungen werden gesammelt (nicht thrown), damit
 * eine defekte externe Verbindung die anderen nicht blockiert.
 */
export async function resolveAllCalendars(connections: CalDavConnection[]): Promise<ResolvedAll> {
	const items: ResolvedCalendar[] = [];
	const errors: string[] = [];

	for (const conn of connections) {
		try {
			const calendars = await resolveConnectionCalendars(conn);
			for (const cal of calendars) {
				items.push({ connection: conn, calendar: { ...cal, connectionName: conn.name } });
			}
		} catch (e) {
			errors.push(`${conn.name}: ${e instanceof Error ? e.message : String(e)}`);
		}
	}

	return { items, errors };
}

/**
 * Findet einen Kalender (id = Hash seiner URL) über alle Verbindungen des
 * Users. Deterministisch: erste Verbindung mit einem Treffer.
 */
export async function findCalendarAcross(
	connections: CalDavConnection[],
	calendarId: string
): Promise<ResolvedCalendar | null> {
	for (const conn of connections) {
		try {
			const calendars = await resolveConnectionCalendars(conn);
			const cal = calendars.find((c) => c.id === calendarId);
			if (cal) return { connection: conn, calendar: { ...cal, connectionName: conn.name } };
		} catch {
			// Verbindung nicht erreichbar → nächste versuchen
		}
	}
	return null;
}
