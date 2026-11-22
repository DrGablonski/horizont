// Kalender-Verwaltung:
//   GET  → alle Kalender inkl. lokaler Präferenzen (?sichtbar=1 nur sichtbare)
//   POST → neuen Kalender per MKCALENDAR auf einer Verbindung anlegen
// Fehler antworten immer als { error: string }.

import { json } from '@sveltejs/kit';
import { createHash, randomBytes } from 'node:crypto';
import type { CalendarCreateInput, CalendarView } from '$lib/types';
import { PALETTE, collectionExists, mkCalendar, resolveHome } from '$server/caldav/client';
import { resolveCalendarViews } from '$server/caldav/multi';
import { getConnectionById, listConnections } from '$server/store/connections';
import { updateCalendarPref } from '$server/store/calendarPrefs';
import { invalidatePanelCache } from '$server/lib/panelCache';
import { readJsonBody } from '$server/auth/apiHelpers';
import { withUser } from '$server/lib/route';

/** ASCII-Slug aus dem Kalendernamen (Umlaute aufgelöst, nicht [a-z0-9] → '-'). */
function slugify(name: string): string {
	const s = name
		.normalize('NFD')
		.replace(/[\u0300-\u036f]/g, '')
		.toLowerCase()
		.replace(/[^a-z0-9]+/g, '-')
		.replace(/^-+|-+$/g, '');
	return s || 'kalender';
}

export const GET = withUser(async ({ url, locals }) => {
	const conns = listConnections(locals.user.id);
	if (conns.length === 0) {
		return json({ configured: false, calendars: [], errors: [], primaryId: null });
	}

	// Standard: alle Kalender (auch ausgeblendete, sonst sieht die Verwaltung
	// sie nicht); ?sichtbar=1 liefert nur die in den Ansichten sichtbaren.
	const includeHidden = url.searchParams.get('sichtbar') !== '1';
	const { calendars, errors, primaryId } = await resolveCalendarViews(locals.user.id, conns, {
		includeHidden
	});
	return json({ configured: true, calendars, errors, primaryId });
});

export const POST = withUser(async ({ request, locals }) => {
	const body = await readJsonBody<CalendarCreateInput>(request);
	if (!body || typeof body.connectionId !== 'string' || !body.connectionId) {
		return json({ error: 'Verbindungs-ID fehlt.' }, { status: 400 });
	}
	const name = typeof body.name === 'string' ? body.name.trim() : '';
	if (!name) return json({ error: 'Kalendername fehlt.' }, { status: 400 });
	const color = body.color;
	if (color !== undefined && (typeof color !== 'string' || !/^#[0-9a-fA-F]{6}$/.test(color))) {
		return json({ error: 'Farbe muss #rrggbb sein.' }, { status: 400 });
	}

	const userId = locals.user.id;
	const conn = getConnectionById(userId, body.connectionId);
	if (!conn) return json({ error: 'Verbindung nicht gefunden.' }, { status: 400 });

	// Nur saubere Komponennamen ins MKCALENDAR-XML (Default: VEVENT + VTODO).
	const comps = Array.isArray(body.components)
		? body.components.filter((c) => typeof c === 'string' && /^[A-Z][A-Z0-9]{1,9}$/.test(c))
		: [];
	const components = comps.length > 0 ? comps : ['VEVENT', 'VTODO'];

	const { home } = await resolveHome(conn);
	const target = `${home.replace(/\/?$/, '/')}${slugify(name)}-${randomBytes(3).toString('hex')}.ics`;
	if (await collectionExists(conn, target)) {
		return json({ error: 'Ein Kalender mit diesem Namen existiert bereits.' }, { status: 409 });
	}
	await mkCalendar(conn, target, name, components);

	// Frische View aufbauen — id und Palette-Farbe wie in der Kalender-Liste.
	const hash = createHash('sha256').update(target).digest('hex').slice(0, 12);
	if (color) updateCalendarPref(userId, hash, { color });
	invalidatePanelCache();

	const view: CalendarView = {
		id: hash,
		name,
		color: color ?? PALETTE[parseInt(hash, 16) % PALETTE.length],
		url: target,
		connectionName: conn.name,
		connectionId: conn.id,
		role: conn.role,
		writable: true,
		writeDisabled: false,
		hidden: false,
		isDefault: false,
		order: null,
		colorOverride: color ?? null,
		supportedComponents: components
	};
	return json(view, { status: 201 });
});
