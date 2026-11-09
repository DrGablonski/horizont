// Multi-Connection-Auflösung: alle CalDAV-Verbindungen eines Users abfragen,
// Kalender aggregieren (mit Verbindungsname) und Kalender über alle
// Verbindungen hinweg finden (für Write-Operationen).

import type { CalDavCalendar, CalDavConnection } from '$lib/types';
import { listCalendars, resolveHome } from '$server/caldav/client';

export interface ResolvedCalendar {
	connection: CalDavConnection;
	calendar: CalDavCalendar; // enthält connectionName
}

export interface ResolvedAll {
	items: ResolvedCalendar[];
	errors: string[];
}

/** Löst eine Verbindung ab und liefert ihre Kalender. */
async function resolveConnectionCalendars(conn: CalDavConnection): Promise<CalDavCalendar[]> {
	const { home } = await resolveHome(conn);
	return listCalendars(conn, home);
}

/**
 * Löst alle Verbindungen des Users ab und liefert alle Kalender.
 * Fehler einzelner Verbindungen werden gesammelt (nicht thrown), damit
 * eine defekte externe Verbindung die anderen nicht blockiert.
 */
export async function resolveAllCalendars(connections: CalDavConnection[]): Promise<ResolvedAll> {
	// Alle Verbindungen parallel auflösen (Roundtrips summieren sich sonst).
	const settled = await Promise.all(
		connections.map(async (conn): Promise<{ conn: CalDavConnection; calendars: CalDavCalendar[]; error?: string }> => {
			try {
				return { conn, calendars: await resolveConnectionCalendars(conn) };
			} catch (e) {
				return { conn, calendars: [], error: `${conn.name}: ${e instanceof Error ? e.message : String(e)}` };
			}
		})
	);

	const items: ResolvedCalendar[] = [];
	const errors: string[] = [];
	for (const { conn, calendars, error } of settled) {
		if (error) errors.push(error);
		for (const cal of calendars) {
			items.push({ connection: conn, calendar: { ...cal, connectionName: conn.name } });
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
