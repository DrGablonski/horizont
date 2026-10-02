// Gemeinsame CalDAV-Server-Helfer: Kalender auflösen, finden, Fehler weiterleiten.

import type { CalDavCalendar, CalDavSettings } from '$lib/types';
import { listCalendars, resolveHome } from '$server/caldav/client';
import { CalDavError } from '$server/caldav/client';

export { CalDavError };

/** Ermittelt Home + alle Kalender für die gespeicherten Settings. */
export async function resolveCalendars(settings: CalDavSettings): Promise<CalDavCalendar[]> {
	const { home } = await resolveHome(settings);
	return listCalendars(settings, home);
}

/** Findet einen Kalender anhand seiner id (hash aus URL). */
export async function findCalendar(settings: CalDavSettings, calendarId: string): Promise<CalDavCalendar | null> {
	const calendars = await resolveCalendars(settings);
	return calendars.find((c) => c.id === calendarId) ?? null;
}
