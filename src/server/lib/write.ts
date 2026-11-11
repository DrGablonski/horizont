// Server-seitige CRUD-Operationen für CalDAV-Events und -Tasks.
// Validiert Eingaben, baut/aktualisiert ICS, schreibt über die CalDAV-Client-Funktionen.

import { createHash, randomUUID } from 'node:crypto';
import type {
	CalDavConnection,
	CalDavCalendar,
	CalendarView,
	EventItem,
	EventCreateInput,
	EventUpdateInput,
	TaskItem,
	TaskCreateInput,
	TaskUpdateInput
} from '$lib/types';
import { msFromKey, todayKey } from '$lib/dates';
import { normalizeCategoryName } from '$lib/categories';
import {
	listCalendarObjects,
	findObjectByUid,
	putIcs,
	deleteIcs,
	getObjectIcs
} from '$server/caldav/client';
import {
	findCalendarView,
	resolveCalendarViews,
	resolveWriteTarget
} from '$server/caldav/multi';
import {
	buildEventIcs,
	updateEventIcs,
	buildTaskIcs,
	updateTaskIcs
} from '$server/caldav/icswriter';
import { icalToTaskItems } from '$server/caldav/ical';
import { invalidatePanelCache } from '$server/lib/panelCache';
import type { ResolvedCalendar } from '$server/caldav/multi';

// ── Helfer ────────────────────────────────────────────────────────────────

/** Parallellimitierte Map (CalDAV-Server mögen keine hundert offenen Sockets). */
async function mapLimit<T, R>(items: T[], limit: number, fn: (item: T) => Promise<R>): Promise<R[]> {
	const out: R[] = new Array(items.length);
	let next = 0;
	const workers = Array.from({ length: Math.min(limit, items.length) }, async () => {
		while (next < items.length) {
			const i = next++;
			out[i] = await fn(items[i]);
		}
	});
	await Promise.all(workers);
	return out;
}

// ── Fehler-Typen ──────────────────────────────────────────────────────────

export class NotFoundError extends Error {
	constructor(msg = 'Ressource nicht gefunden') {
		super(msg);
		this.name = 'NotFoundError';
	}
}

export class ValidationError extends Error {
	constructor(msg: string) {
		super(msg);
		this.name = 'ValidationError';
	}
}

/** Zielkalender ist schreibgeschützt (localer Schreibschutz oder fehlende Server-Rechte). */
export class ReadOnlyError extends Error {
	constructor(msg = 'Dieser Kalender ist schreibgeschützt.') {
		super(msg);
		this.name = 'ReadOnlyError';
	}
}

// ── Zielkalender für Schreibzugriffe ──────────────────────────────────────

/** Wirft ReadOnlyError bei lokalem Schreibschutz oder fehlenden Server-Rechten. */
function assertWritable(calendar: CalendarView): void {
	if (calendar.writeDisabled === true || calendar.writable === false) {
		throw new ReadOnlyError(`Kalender „${calendar.name}“ ist schreibgeschützt.`);
	}
}

/**
 * Kalender, in den geschrieben werden darf: bei fehlender/leerer id das
 * erlaubte Standardziel, sonst die explizit genannte Kalender über alle
 * Verbindungen. resolveWriteTarget prüft zwar ebenfalls, wirft dort aber nur
 * einen allgemeinen Fehler — hier zählt der auf 403 mappbare ReadOnlyError.
 */
async function requireWritableCalendar(
	userId: string,
	connections: CalDavConnection[],
	calendarId?: string | null
): Promise<ResolvedCalendar> {
	if (!calendarId) {
		const target = await resolveWriteTarget(userId, connections);
		assertWritable(target.calendar);
		return target;
	}
	const found = await findCalendarView(userId, connections, calendarId);
	if (!found) throw new NotFoundError('Kalender nicht gefunden.');
	assertWritable(found.calendar);
	return found;
}

// ── Validation: Event-Input ───────────────────────────────────────────────

function validateEventInput(input: EventUpdateInput): void {
	if (!input.summary || input.summary.trim().length === 0) {
		throw new ValidationError('Titel darf nicht leer sein.');
	}
	if (input.allDay) {
		if (!input.dayKey || !/^\d{4}-\d{2}-\d{2}$/.test(input.dayKey)) {
			throw new ValidationError('Gültiges Startdatum erforderlich.');
		}
		if (input.endDateKey && !/^\d{4}-\d{2}-\d{2}$/.test(input.endDateKey)) {
			throw new ValidationError('Gültiges Enddatum erforderlich.');
		}
	} else {
		if (input.startMs == null || !Number.isFinite(input.startMs)) {
			throw new ValidationError('Gültige Startzeit erforderlich.');
		}
		if (input.endMs == null || !Number.isFinite(input.endMs) || input.endMs <= input.startMs) {
			throw new ValidationError('Gültige Endzeit erforderlich (muss nach der Startzeit liegen).');
		}
	}
}

// ── Validation: Task-Input ────────────────────────────────────────────────

function validateTaskCreateInput(input: TaskCreateInput): void {
	if (!input.summary || input.summary.trim().length === 0) {
		throw new ValidationError('Aufgabentitel darf nicht leer sein.');
	}
}

function validateTaskPatch(input: TaskUpdateInput): void {
	// Partial: nur geprüfte Felder
	if (input.due != null) {
		if (input.due.kind === 'date' && !/^\d{4}-\d{2}-\d{2}$/.test(input.due.key)) {
			throw new ValidationError('Ungültiges Datum.');
		}
		if (input.due.kind === 'time' && (!Number.isFinite(input.due.ms) || input.due.ms <= 0)) {
			throw new ValidationError('Ungültige Zeit.');
		}
	}
	if (input.category != null && input.category !== null) {
		if (normalizeCategoryName(input.category) == null) {
			throw new ValidationError('Ungültiger Kategoriename (1–40 Zeichen, ohne Komma/Semikolon).');
		}
	}
}


function buildEventItemFromInput(
	calendar: CalDavCalendar,
	uid: string,
	input: EventUpdateInput
): EventItem {
	let startMs: number;
	let endMs: number;

	if (input.allDay) {
		const dayK = input.dayKey!;
		const endK = input.endDateKey ?? dayK;
		startMs = msFromKey(dayK);
		endMs = msFromKey(endK) + 86400000;
	} else {
		startMs = input.startMs!;
		endMs = input.endMs!;
	}

	const id = `${calendar.id}|${uid}|${startMs}`;

	return {
		id,
		uid,
		calendarId: calendar.id,
		calendarName: calendar.name,
		calendarColor: calendar.color,
		startMs,
		endMs,
		summary: input.summary.trim(),
		location: input.location?.trim() || undefined,
		description: input.description?.trim() || undefined,
		allDay: input.allDay
	};
}

// ── Event: Create ─────────────────────────────────────────────────────────

export async function createEvent(
	userId: string,
	connections: CalDavConnection[],
	input: EventCreateInput
): Promise<EventItem> {
	validateEventInput(input);
	const { connection, calendar } = await requireWritableCalendar(userId, connections, input.calendarId);

	const uid = `horizont-${randomUUID()}`;
	const { ics } = buildEventIcs(uid, input);
	const url = `${calendar.url.replace(/\/?$/, '/')}${uid}.ics`;
	await putIcs(connection, url, ics);
	invalidatePanelCache();

	return buildEventItemFromInput(calendar, uid, input);
}

// ── Event: Mutate ─────────────────────────────────────────────────────────

export async function mutateEvent(
	userId: string,
	connections: CalDavConnection[],
	calendarId: string,
	uid: string,
	input: EventUpdateInput
): Promise<EventItem> {
	validateEventInput(input);
	const { connection, calendar } = await requireWritableCalendar(userId, connections, calendarId);

	const found = await findObjectByUid(connection, calendar, uid);
	if (!found) throw new NotFoundError('Kalendereintrag nicht gefunden.');

	const { ics } = updateEventIcs(found.ics, uid, input);
	await putIcs(connection, found.url, ics, found.etag);
	invalidatePanelCache();

	return buildEventItemFromInput(calendar, uid, input);
}

// ── Event: Delete ─────────────────────────────────────────────────────────

export async function removeEvent(
	userId: string,
	connections: CalDavConnection[],
	calendarId: string,
	uid: string
): Promise<void> {
	const { connection, calendar } = await requireWritableCalendar(userId, connections, calendarId);

	const found = await findObjectByUid(connection, calendar, uid);
	if (!found) throw new NotFoundError('Kalendereintrag nicht gefunden.');

	await deleteIcs(connection, found.url, found.etag);
	invalidatePanelCache();
}

// ── Task: Create ──────────────────────────────────────────────────────────

function buildTaskItemFromInput(
	calendar: CalDavCalendar,
	uid: string,
	input: {
		summary: string;
		description?: string;
		completed?: boolean;
		due?: { kind: 'none' } | { kind: 'date'; key: string } | { kind: 'time'; ms: number };
		category?: string | null;
	}
): TaskItem {
	let dueKey: string | undefined;
	let dueMs: number | undefined;
	if (input.due != null) {
		if (input.due.kind === 'date') dueKey = input.due.key;
		else if (input.due.kind === 'time') dueMs = input.due.ms;
	}

	const id = createHash('sha256')
		.update(`${calendar.id}|${uid}|${input.summary}`)
		.digest('hex')
		.slice(0, 16);

	return {
		id,
		uid,
		calendarId: calendar.id,
		calendarName: calendar.name,
		calendarColor: calendar.color,
		summary: input.summary.trim(),
		description: input.description?.trim() || undefined,
		completed: input.completed ?? false,
		dueKey,
		dueMs,
		category: input.category ?? undefined
	};
}

export async function createTask(
	userId: string,
	connections: CalDavConnection[],
	input: TaskCreateInput
): Promise<TaskItem> {
	validateTaskCreateInput(input);
	// Ohne ausdrücklich gewähltes Fälligkeitsdatum: automatisch den
	// Erstellungstag eintragen — die Aufgabe taucht so sofort bei „Heute"
	// auf und wird ab dem nächsten Tag als überfällig markiert.
	if (input.due == null || input.due.kind === 'none') {
		input = { ...input, due: { kind: 'date', key: todayKey() } };
	}
	const { connection, calendar } = await requireWritableCalendar(userId, connections, input.calendarId);

	const uid = `horizont-${randomUUID()}`;
	const { ics } = buildTaskIcs(uid, input);
	const url = `${calendar.url.replace(/\/?$/, '/')}${uid}.ics`;
	await putIcs(connection, url, ics);
	invalidatePanelCache();

	return buildTaskItemFromInput(calendar, uid, input);
}

// ── Task: Mutate (partial) ────────────────────────────────────────────────

export async function mutateTask(
	userId: string,
	connections: CalDavConnection[],
	calendarId: string,
	uid: string,
	input: TaskUpdateInput
): Promise<TaskItem> {
	validateTaskPatch(input);
	const { connection, calendar } = await requireWritableCalendar(userId, connections, calendarId);

	const found = await findObjectByUid(connection, calendar, uid);
	if (!found) throw new NotFoundError('Aufgabe nicht gefunden.');

	const { ics } = updateTaskIcs(found.ics, uid, input);
	await putIcs(connection, found.url, ics, found.etag);
	invalidatePanelCache();

	const items = icalToTaskItems(ics, calendar);
	const item = items.find((t) => t.uid === uid);
	if (!item) throw new NotFoundError('Aufgabe nach Update nicht gefunden.');
	return item;
}

// ── Task: Delete ──────────────────────────────────────────────────────────

export async function removeTask(
	userId: string,
	connections: CalDavConnection[],
	calendarId: string,
	uid: string
): Promise<void> {
	const { connection, calendar } = await requireWritableCalendar(userId, connections, calendarId);

	const found = await findObjectByUid(connection, calendar, uid);
	if (!found) throw new NotFoundError('Aufgabe nicht gefunden.');

	await deleteIcs(connection, found.url, found.etag);
	invalidatePanelCache();
}

// ── Tasks: Read (für API GET) ─────────────────────────────────────────────

/**
 * Tasks aus bereits aufgelösten Kalendern lesen (Roundtrips der
 * Kalenderauflösung werden nicht doppelt bezahlt). Objekt-GETs laufen
 * parallellimitiert — die serielle Kette war der Hauptkostentreiber.
 */
export async function listAllTasksForItems(items: ResolvedCalendar[]): Promise<TaskItem[]> {
	const perCalendar = await mapLimit(items, 6, async ({ connection, calendar }) => {
		const local: TaskItem[] = [];
		try {
			const objects = await listCalendarObjects(connection, calendar.url);
			const chunks = await mapLimit(objects, 8, async (obj) => {
				const ics = await getObjectIcs(connection, obj.url);
				return ics ? icalToTaskItems(ics, calendar) : ([] as TaskItem[]);
			});
			for (const chunk of chunks) local.push(...chunk);
		} catch {
			// skip failed calendar
		}
		return local;
	});

	const tasks = perCalendar.flat();
	return tasks.sort((a, b) => {
		if (a.completed !== b.completed) return a.completed ? 1 : -1;
		const aDue = a.dueMs ?? (a.dueKey ? msFromKey(a.dueKey) : Infinity);
		const bDue = b.dueMs ?? (b.dueKey ? msFromKey(b.dueKey) : Infinity);
		return aDue - bDue;
	});
}

/** Tasks aus allen sichtbaren Kalendern des Users (Panel-Sicht). */
export async function listAllTasks(userId: string, connections: CalDavConnection[]): Promise<TaskItem[]> {
	const { calendars } = await resolveCalendarViews(userId, connections, { includeHidden: false });
	const items: ResolvedCalendar[] = [];
	for (const calendar of calendars) {
		const connection = connections.find((c) => c.id === calendar.connectionId);
		if (connection) items.push({ connection, calendar });
	}
	return listAllTasksForItems(items);
}
