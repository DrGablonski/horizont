// Server-seitige CRUD-Operationen für CalDAV-Events und -Tasks.
// Validiert Eingaben, baut/aktualisiert ICS, schreibt über die CalDAV-Client-Funktionen.

import { createHash, randomUUID } from 'node:crypto';
import type {
	CalDavSettings,
	CalDavCalendar,
	EventItem,
	EventCreateInput,
	EventUpdateInput,
	TaskItem,
	TaskCreateInput,
	TaskUpdateInput
} from '$lib/types';
import { msFromKey } from '$lib/dates';
import {
	listCalendarObjects,
	findObjectByUid,
	putIcs,
	deleteIcs,
	getObjectIcs
} from '$server/caldav/client';
import { findCalendar, resolveCalendars } from '$server/lib/caldav';
import {
	buildEventIcs,
	updateEventIcs,
	buildTaskIcs,
	updateTaskIcs
} from '$server/caldav/icswriter';
import { icalToTaskItems } from '$server/caldav/ical';

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
	if (input.priority != null && input.priority !== null) {
		if (!Number.isInteger(input.priority) || input.priority < 1 || input.priority > 9) {
			throw new ValidationError('Priorität muss eine ganze Zahl zwischen 1 und 9 sein.');
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
	settings: CalDavSettings,
	input: EventCreateInput
): Promise<EventItem> {
	validateEventInput(input);
	const calendar = await findCalendar(settings, input.calendarId);
	if (!calendar) throw new NotFoundError('Kalender nicht gefunden.');

	const uid = `horizont-${randomUUID()}`;
	const { ics } = buildEventIcs(uid, input);
	const url = `${calendar.url.replace(/\/?$/, '/')}${uid}.ics`;
	await putIcs(settings, url, ics);

	return buildEventItemFromInput(calendar, uid, input);
}

// ── Event: Mutate ─────────────────────────────────────────────────────────

export async function mutateEvent(
	settings: CalDavSettings,
	calendarId: string,
	uid: string,
	input: EventUpdateInput
): Promise<EventItem> {
	validateEventInput(input);
	const calendar = await findCalendar(settings, calendarId);
	if (!calendar) throw new NotFoundError('Kalender nicht gefunden.');

	const found = await findObjectByUid(settings, calendar, uid);
	if (!found) throw new NotFoundError('Kalendereintrag nicht gefunden.');

	const { ics } = updateEventIcs(found.ics, uid, input);
	await putIcs(settings, found.url, ics, found.etag);

	return buildEventItemFromInput(calendar, uid, input);
}

// ── Event: Delete ─────────────────────────────────────────────────────────

export async function removeEvent(
	settings: CalDavSettings,
	calendarId: string,
	uid: string
): Promise<void> {
	const calendar = await findCalendar(settings, calendarId);
	if (!calendar) throw new NotFoundError('Kalender nicht gefunden.');

	const found = await findObjectByUid(settings, calendar, uid);
	if (!found) throw new NotFoundError('Kalendereintrag nicht gefunden.');

	await deleteIcs(settings, found.url, found.etag);
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
		priority?: number | null;
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
		priority: input.priority ?? undefined
	};
}

export async function createTask(
	settings: CalDavSettings,
	input: TaskCreateInput
): Promise<TaskItem> {
	validateTaskCreateInput(input);
	const calendar = await findCalendar(settings, input.calendarId);
	if (!calendar) throw new NotFoundError('Kalender nicht gefunden.');

	const uid = `horizont-${randomUUID()}`;
	const { ics } = buildTaskIcs(uid, input);
	const url = `${calendar.url.replace(/\/?$/, '/')}${uid}.ics`;
	await putIcs(settings, url, ics);

	return buildTaskItemFromInput(calendar, uid, input);
}

// ── Task: Mutate (partial) ────────────────────────────────────────────────

export async function mutateTask(
	settings: CalDavSettings,
	calendarId: string,
	uid: string,
	input: TaskUpdateInput
): Promise<TaskItem> {
	validateTaskPatch(input);
	const calendar = await findCalendar(settings, calendarId);
	if (!calendar) throw new NotFoundError('Kalender nicht gefunden.');

	const found = await findObjectByUid(settings, calendar, uid);
	if (!found) throw new NotFoundError('Aufgabe nicht gefunden.');

	const { ics } = updateTaskIcs(found.ics, uid, input);
	await putIcs(settings, found.url, ics, found.etag);

	const items = icalToTaskItems(ics, calendar);
	const item = items.find((t) => t.uid === uid);
	if (!item) throw new NotFoundError('Aufgabe nach Update nicht gefunden.');
	return item;
}

// ── Task: Delete ──────────────────────────────────────────────────────────

export async function removeTask(
	settings: CalDavSettings,
	calendarId: string,
	uid: string
): Promise<void> {
	const calendar = await findCalendar(settings, calendarId);
	if (!calendar) throw new NotFoundError('Kalender nicht gefunden.');

	const found = await findObjectByUid(settings, calendar, uid);
	if (!found) throw new NotFoundError('Aufgabe nicht gefunden.');

	await deleteIcs(settings, found.url, found.etag);
}

// ── Tasks: Read (für API GET) ─────────────────────────────────────────────

export async function listAllTasks(settings: CalDavSettings): Promise<TaskItem[]> {
	const calendars = await resolveCalendars(settings);
	const tasks: TaskItem[] = [];

	for (const cal of calendars) {
		try {
			const objects = await listCalendarObjects(settings, cal.url);
			for (const obj of objects) {
				const ics = await getObjectIcs(settings, obj.url);
				if (!ics) continue;
				const items = icalToTaskItems(ics, cal);
				tasks.push(...items);
			}
		} catch {
			// skip failed calendar
		}
	}

	return tasks.sort((a, b) => {
		if (a.completed !== b.completed) return a.completed ? 1 : -1;
		const aDue = a.dueMs ?? (a.dueKey ? msFromKey(a.dueKey) : Infinity);
		const bDue = b.dueMs ?? (b.dueKey ? msFromKey(b.dueKey) : Infinity);
		return aDue - bDue;
	});
}
