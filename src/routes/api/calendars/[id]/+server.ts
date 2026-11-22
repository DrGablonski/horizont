// Einzelner Kalender (id = Hash seiner URL):
//   PATCH  → Anzeigename (PROPPATCH, sonst lokal gemerkt) + lokale Präferenzen
//   DELETE → Collection auf dem CalDAV-Server löschen (Bestätigung = Name)
// Die Zielverbindung wird über alle Verbindungen gesucht; ein optionales
// `connectionId` im Body grenzt die Suche auf diese Verbindung ein.

import { json } from '@sveltejs/kit';
import type { RequestEvent } from './$types';
import type { CalendarPref, CalendarUpdateInput } from '$lib/types';
import { PALETTE, deleteCollection, setCollectionDisplayName } from '$server/caldav/client';
import { findCalendarView, resolveAllCalendars } from '$server/caldav/multi';
import { listConnections } from '$server/store/connections';
import { getDefaultCalendarId, setDefaultCalendar, updateCalendarPref } from '$server/store/calendarPrefs';
import { invalidatePanelCache } from '$server/lib/panelCache';
import { WORKFLOWS_CALENDAR } from '$server/lib/constants';
import { readJsonBody } from '$server/auth/apiHelpers';
import { withUser } from '$server/lib/route';

export const PATCH = withUser<RequestEvent>(async ({ request, params, locals }) => {
	const id = params.id;
	if (!id) return json({ error: 'Kalender-ID fehlt.' }, { status: 400 });

	const body = await readJsonBody<CalendarUpdateInput & { connectionId?: string }>(request);
	if (!body) return json({ error: 'Ungültiger JSON-Body.' }, { status: 400 });

	const name = body.name !== undefined ? (typeof body.name === 'string' ? body.name.trim() : '') : undefined;
	if (body.name !== undefined && !name) return json({ error: 'Kalendername fehlt.' }, { status: 400 });
	if (body.color !== undefined && body.color !== null && (typeof body.color !== 'string' || !/^#[0-9a-fA-F]{6}$/.test(body.color))) {
		return json({ error: 'Farbe muss #rrggbb sein.' }, { status: 400 });
	}
	if (body.order !== undefined && body.order !== null && typeof body.order !== 'number') {
		return json({ error: 'Sortierwert muss eine Zahl sein.' }, { status: 400 });
	}

	const userId = locals.user.id;
	let conns = listConnections(userId);
	if (typeof body.connectionId === 'string' && body.connectionId) {
		conns = conns.filter((c) => c.id === body.connectionId);
	}

	const found = await findCalendarView(userId, conns, id);
	if (!found) return json({ error: 'Kalender nicht gefunden.' }, { status: 404 });
	const view = { ...found.calendar };

	// Name: zuerst auf dem Server setzen; kann er das nicht, lokal merken.
	if (name !== undefined) {
		const ok = await setCollectionDisplayName(found.connection, view.url, name);
		// gelungener PROPPATCH → einen alten lokalen Namen wieder entfernen
		updateCalendarPref(userId, id, ok ? { name: undefined } : { name });
		view.name = name;
	}

	// Lokale Präferenzen (null = Aufhebung → Schlüssel wird entfernt).
	const patch: Partial<CalendarPref> = {};
	if (body.color !== undefined) patch.color = body.color ?? undefined;
	if (body.hidden !== undefined) patch.hidden = body.hidden;
	if (body.writeDisabled !== undefined) patch.writeDisabled = body.writeDisabled;
	if (body.order !== undefined) patch.order = body.order ?? undefined;
	if (Object.keys(patch).length > 0) updateCalendarPref(userId, id, patch);

	// Standardkalender (false entfernt ihn nur, wenn er dies selbst ist).
	if (body.isDefault === true) setDefaultCalendar(userId, id);
	else if (body.isDefault === false && getDefaultCalendarId(userId) === id) setDefaultCalendar(userId, null);

	// Response-View konsistent zu den gespeicherten Präferenzen machen.
	if (body.color !== undefined) {
		view.colorOverride = body.color ?? null;
		view.color = body.color ?? PALETTE[parseInt(view.id, 16) % PALETTE.length];
	}
	if (body.hidden !== undefined) view.hidden = body.hidden;
	if (body.writeDisabled !== undefined) {
		// Server-Rechte aus der View zurückrechnen und Schutz neu anwenden.
		const serverWritable = found.calendar.writable || found.calendar.writeDisabled;
		view.writeDisabled = body.writeDisabled;
		view.writable = serverWritable && !body.writeDisabled;
	}
	if (body.order !== undefined) view.order = body.order ?? null;
	if (body.isDefault !== undefined) view.isDefault = body.isDefault;

	invalidatePanelCache();
	return json(view);
});

export const DELETE = withUser<RequestEvent>(async ({ request, params, locals }) => {
	const id = params.id;
	if (!id) return json({ error: 'Kalender-ID fehlt.' }, { status: 400 });

	const body = await readJsonBody<{ name?: string; connectionId?: string }>(request);
	if (!body || typeof body.name !== 'string') {
		return json({ error: 'Bestätigungsname fehlt.' }, { status: 400 });
	}

	const userId = locals.user.id;
	let conns = listConnections(userId);
	if (typeof body.connectionId === 'string' && body.connectionId) {
		conns = conns.filter((c) => c.id === body.connectionId);
	}

	const found = await findCalendarView(userId, conns, id);
	if (!found) return json({ error: 'Kalender nicht gefunden.' }, { status: 404 });

	// Löschbestätigung: der übermittelte Name muss exakt passen.
	if (body.name !== found.calendar.name) {
		return json({ error: 'Name stimmt nicht mit dem Kalendernamen überein.' }, { status: 403 });
	}
	// Interner Workflow-Speicher ist kein Benutzerkalender.
	if (found.calendar.url.endsWith(`/${WORKFLOWS_CALENDAR}/`)) {
		return json({ error: 'Der interne Kalender kann nicht gelöscht werden.' }, { status: 403 });
	}
	// Der letzte beschreibbare Kalender der Hauptverbindung ist geschützt.
	const serverWritable = found.calendar.writable || found.calendar.writeDisabled;
	if (found.connection.role === 'primary' && serverWritable) {
		const { items } = await resolveAllCalendars(conns);
		const primaryWritable = items.filter(
			(i) => i.connection.role === 'primary' && i.calendar.writable
		);
		if (primaryWritable.length <= 1) {
			return json(
				{ error: 'Der letzte beschreibbare Kalender der Hauptverbindung kann nicht gelöscht werden.' },
				{ status: 403 }
			);
		}
	}

	await deleteCollection(found.connection, found.calendar.url);

	// Lokale Präferenzen des gelöschten Kalenders mit entfernen.
	updateCalendarPref(userId, id, null);
	invalidatePanelCache();
	return json({ ok: true });
});
