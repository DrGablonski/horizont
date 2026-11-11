// Multi-Connection-Auflösung: alle CalDAV-Verbindungen eines Users abfragen,
// Kalender aggregieren (mit Verbindungsname) und Kalender über alle
// Verbindungen hinweg finden (für Write-Operationen). Die View-Funktionen
// verschmelzen den CalDAV-Rohzustand mit den lokalen Kalender-Präferenzen.

import type { CalendarPref, CalendarView, CalDavCalendar, CalDavConnection } from '$lib/types';
import { listCalendars, resolveHome } from '$server/caldav/client';
import { getCalendarPrefs, getDefaultCalendarId } from '$server/store/calendarPrefs';
import { getPrimaryConnection } from '$server/store/connections';

export interface ResolvedCalendar {
	connection: CalDavConnection;
	calendar: CalendarView; // enthält connectionName + Prefs
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

/** Rohzustand eines Kalenders als View: connectionId/role gesetzt, Prefs neutral. */
function toRawView(calendar: CalDavCalendar, connection: CalDavConnection): CalendarView {
	return {
		...calendar,
		connectionName: connection.name,
		connectionId: connection.id,
		role: connection.role,
		writable: calendar.writable ?? true,
		writeDisabled: false,
		hidden: false,
		isDefault: false,
		order: null,
		colorOverride: null,
		supportedComponents: calendar.supportedComponents ?? []
	};
}

/** Wendet lokale Präferenzen auf eine Roh-View an (Sichtbarkeit, Farbe, Schutz). */
function applyPrefs(view: CalendarView, pref: CalendarPref | undefined): CalendarView {
	if (!pref) return view;
	const writeDisabled = pref.writeDisabled === true;
	return {
		...view,
		hidden: pref.hidden === true,
		writeDisabled,
		isDefault: pref.isDefault === true,
		order: pref.order ?? null,
		colorOverride: pref.color ?? null,
		color: pref.color ?? view.color,
		// Lokal gemerkter Name gewinnt (Server konnte displayname nicht setzen).
		name: pref.name ?? view.name,
		writable: view.writable && !writeDisabled
	};
}

/** Reihenfolge: order aufsteigend (null zuletzt), danach Name. */
function compareViews(a: CalendarView, b: CalendarView): number {
	if (a.order !== b.order) {
		if (a.order === null) return 1;
		if (b.order === null) return -1;
		return a.order - b.order;
	}
	return a.name.localeCompare(b.name);
}

/**
 * Löst alle Verbindungen des Users ab und liefert alle Kalender im
 * Rohzustand (connectionId/role gesetzt, ohne Prefs). Fehler einzelner
 * Verbindungen werden gesammelt (nicht thrown), damit eine defekte externe
 * Verbindung die anderen nicht blockiert.
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
			items.push({ connection: conn, calendar: toRawView(cal, conn) });
		}
	}

	return { items, errors };
}

/** Alle Kalender der Verbindungen, aber schon mit angewendeten lokalen Prefs. */
async function resolveResolvedCalendars(userId: string, connections: CalDavConnection[]): Promise<ResolvedAll> {
	const { items, errors } = await resolveAllCalendars(connections);
	const prefs = getCalendarPrefs(userId);
	return {
		items: items.map((item) => ({
			connection: item.connection,
			calendar: applyPrefs(item.calendar, prefs[item.calendar.id])
		})),
		errors
	};
}

/**
 * CalDAV + lokale Prefs verschmelzen. Sortierung: order aufsteigend
 * (null zuletzt), dann Name. Ausgeblendete Kalender fallen standardmäßig
 * heraus; `writableOnly` filtert zusätzlich nach Beschreibbarkeit.
 */
export async function resolveCalendarViews(
	userId: string,
	conns: CalDavConnection[],
	opts?: { includeHidden?: boolean; writableOnly?: boolean }
): Promise<{ calendars: CalendarView[]; errors: string[]; primaryId: string | null }> {
	const { items, errors } = await resolveResolvedCalendars(userId, conns);
	let calendars = items.map((item) => item.calendar);
	if (!opts?.includeHidden) calendars = calendars.filter((c) => !c.hidden);
	if (opts?.writableOnly) calendars = calendars.filter((c) => c.writable);
	calendars.sort(compareViews);
	const primary = getPrimaryConnection(userId);
	return { calendars, errors, primaryId: primary?.id ?? null };
}

/**
 * Findet einen Kalender (id = Hash seiner URL) über alle Verbindungen und
 * wendet die Präferenzen an — auch bei ausgeblendeten Kalendern, damit
 * Detail- und Schreibpfade funktionieren. Deterministisch: erster Treffer.
 */
export async function findCalendarView(
	userId: string,
	conns: CalDavConnection[],
	calendarId: string
): Promise<ResolvedCalendar | null> {
	const { items } = await resolveResolvedCalendars(userId, conns);
	return items.find((item) => item.calendar.id === calendarId) ?? null;
}

/**
 * Zulässiges Ziel für neue Einträge: explizit genannte ID (sonst Fehler),
 * sonst Standardkalender, sonst erster beschreibbarer Kalender der
 * primary-Verbindung, sonst letzter Ausweg: ein beliebiger beschreibbarer
 * Kalender. Sekundäre Verbindungen sind als Ziel erlaubt, solange der
 * Kalender nicht lokal writeDisabled ist.
 */
export async function resolveWriteTarget(
	userId: string,
	conns: CalDavConnection[],
	calendarId?: string | null
): Promise<ResolvedCalendar> {
	if (calendarId) {
		const found = await findCalendarView(userId, conns, calendarId);
		if (!found) throw new Error('Kalender nicht gefunden.');
		if (found.calendar.writeDisabled || !found.calendar.writable) {
			throw new Error(`Kalender ${found.calendar.name} ist schreibgeschützt.`);
		}
		return found;
	}

	// Sichtbare, beschreibbare Kalender in Anzeigereihenfolge.
	const { items } = await resolveResolvedCalendars(userId, conns);
	const writable = items
		.filter((item) => !item.calendar.hidden && item.calendar.writable)
		.sort((a, b) => compareViews(a.calendar, b.calendar));
	if (writable.length === 0) throw new Error('Kein beschreibbarer Kalender gefunden.');

	const defaultId = getDefaultCalendarId(userId);
	if (defaultId) {
		const def = writable.find((item) => item.calendar.id === defaultId);
		if (def) return def;
	}

	const primary = getPrimaryConnection(userId);
	if (primary) {
		const fromPrimary = writable.find((item) => item.calendar.connectionId === primary.id);
		if (fromPrimary) return fromPrimary;
	}
	return writable[0];
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
			if (cal) return { connection: conn, calendar: toRawView(cal, conn) };
		} catch {
			// Verbindung nicht erreichbar → nächste versuchen
		}
	}
	return null;
}
