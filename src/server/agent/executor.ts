// Tool-Ausführung: mappt Agent-Tools auf die bestehenden Server-Funktionen
// (write.ts, workflowStore, CalDAV-Reads). Fehler werden nicht thrown, sondern
// als JSON-Ergebnis zurückgegeben, damit das Modell darauf reagieren kann.

import type {
	CalDavConnection,
	CalDavCalendar,
	EventCreateInput,
	EventUpdateInput,
	TaskCreateInput,
	TaskUpdateInput
} from '$lib/types';
import { dayKey as toDayKey, msFromKey, todayKey, addDaysMs, localInputToMs } from '$lib/dates';
import { listConnections } from '$server/store/connections';
import { fetchCalendarIcs } from '$server/caldav/client';
import { resolveAllCalendars } from '$server/caldav/multi';
import { icalToEventItems } from '$server/caldav/ical';
import { toIcsUtc } from '$lib/dates';
import {
	createEvent,
	mutateEvent,
	removeEvent,
	createTask,
	mutateTask,
	removeTask,
	listAllTasks
} from '$server/lib/write';
import {
	listWorkflows,
	createWorkflow,
	updateWorkflow,
	addStep,
	updateStep,
	resetWorkflow,
	deleteWorkflow
} from '$server/store/store';
import { TOOL_BY_NAME } from './tools';

// ── Ergebnis-Wrapper ──────────────────────────────────────────────────────

export interface ToolResult {
	ok: boolean;
	result?: unknown;
	error?: string;
}

function ok(result: unknown): ToolResult {
	return { ok: true, result };
}

function fail(e: unknown): ToolResult {
	return { ok: false, error: e instanceof Error ? e.message : String(e) };
}

/** Ergebnis als String für die LLM-Tool-Message. */
export function toolResultText(r: ToolResult): string {
	return JSON.stringify(r);
}

// ── Kontext ───────────────────────────────────────────────────────────────

export interface ExecContext {
	userId: string;
	connections: CalDavConnection[];
}

// ── Kalender-Hilfen ───────────────────────────────────────────────────────

function isWorkflowsCalendar(cal: CalDavCalendar): boolean {
	return /\/workflows\/?$/.test(cal.url);
}

function publicCalendars(items: { calendar: CalDavCalendar }[]): CalDavCalendar[] {
	return items.map((i) => i.calendar).filter((c) => !isWorkflowsCalendar(c));
}

function shortCalendar(cal: CalDavCalendar): Record<string, unknown> {
	return {
		id: cal.id,
		name: cal.name,
		color: cal.color,
		connection: cal.connectionName
	};
}

// ── Read-Tools ────────────────────────────────────────────────────────────

export async function runReadTool(ctx: ExecContext, name: string, args: Record<string, unknown>): Promise<ToolResult> {
	switch (name) {
		case 'list_calendars': {
			const conns = ctx.connections;
			if (conns.length === 0) {
				return ok({
					calendars: [],
					note: 'Der User hat keine CalDAV-Verbindung. Events/Tasks können nicht angelegt werden.'
				});
			}
			const { items, errors } = await resolveAllCalendars(conns);
			return ok({
				calendars: publicCalendars(items).map(shortCalendar),
				...(errors.length ? { errors } : {})
			});
		}
		case 'search_events': {
			const conns = ctx.connections;
			if (conns.length === 0) return ok({ events: [], note: 'Keine Kalender verfügbar.' });

			const now = Date.now();
			const todayStart = msFromKey(todayKey());
			const fromMs = typeof args.fromMs === 'number' ? args.fromMs : addDaysMs(todayStart, -30);
			const toMs = typeof args.toMs === 'number' ? args.toMs : addDaysMs(todayStart, 30);
			const query = typeof args.query === 'string' ? args.query.trim().toLowerCase() : '';
			const limit = Math.min(typeof args.limit === 'number' ? args.limit : 30, 100);

			const { items, errors } = await resolveAllCalendars(conns);
			const events: ReturnType<typeof icalToEventItems> = [];
			for (const { connection, calendar } of items) {
				if (isWorkflowsCalendar(calendar)) continue;
				try {
					const icsList = await fetchCalendarIcs(connection, calendar, toIcsUtc(fromMs), toIcsUtc(toMs));
					events.push(...icalToEventItems(icsList, calendar, fromMs, toMs));
				} catch {
					// einzelne Kalender überspringen
				}
			}
			events.sort((a, b) => a.startMs - b.startMs || a.summary.localeCompare(b.summary, 'de'));

			const filtered = query
				? events.filter(
						(e) =>
							e.summary.toLowerCase().includes(query) ||
							(e.location ?? '').toLowerCase().includes(query) ||
							(e.description ?? '').toLowerCase().includes(query)
					)
				: events;

			const out = filtered.slice(0, limit).map((e) => ({
				uid: e.uid,
				calendarId: e.calendarId,
				calendarName: e.calendarName,
				summary: e.summary,
				allDay: e.allDay,
				startMs: e.startMs,
				endMs: e.endMs,
				startLocal: `${toDayKey(e.startMs)}T${fmtTime(e.startMs)}`,
				endLocal: `${toDayKey(e.endMs)}T${fmtTime(e.endMs)}`,
				dayKey: toDayKey(e.startMs),
				...(e.location ? { location: e.location } : {}),
				...(e.description ? { description: e.description } : {})
			}));
			return ok({
				count: out.length,
				total: filtered.length,
				range: { fromMs, toMs },
				events: out,
				...(errors.length ? { errors } : {}),
				...(!query && filtered.length > limit
					? { note: `Nur ${limit} von ${filtered.length} Treffern gezeigt. Präzisiere Suchzeitraum oder Suchtext.` }
					: {})
			});
		}
		case 'list_tasks': {
			const conns = ctx.connections;
			if (conns.length === 0) return ok({ tasks: [], note: 'Keine Kalender verfügbar.' });
			const onlyOpen = args.onlyOpen !== false;
			let tasks = await listAllTasks(conns);
			if (onlyOpen) tasks = tasks.filter((t) => !t.completed);
			const out = tasks.slice(0, 100).map((t) => ({
				uid: t.uid,
				calendarId: t.calendarId,
				calendarName: t.calendarName,
				summary: t.summary,
				completed: t.completed,
				...(t.dueKey ? { dueKey: t.dueKey } : {}),
				...(t.dueMs != null ? { dueMs: t.dueMs, dueLocal: `${toDayKey(t.dueMs)}T${fmtTime(t.dueMs)}` } : {}),
				...(t.priority != null ? { priority: t.priority } : {}),
				...(t.description ? { description: t.description } : {})
			}));
			return ok({ count: out.length, tasks: out });
		}
		case 'list_workflows': {
			const workflows = await listWorkflows(ctx.userId);
			const out = workflows.map((w) => ({
				id: w.id,
				title: w.title,
				notes: w.notes || undefined,
				progress: w.progress,
				completed: w.completedAt != null,
				steps: w.steps.map((s) => ({ id: s.id, title: s.title, done: s.done }))
			}));
			return ok({ count: out.length, workflows: out });
		}
		default:
			return fail(new Error(`Unbekanntes Read-Tool: ${name}`));
	}
}

// ── Write-Tools ───────────────────────────────────────────────────────────

function asString(v: unknown): string | undefined {
	return typeof v === 'string' && v.trim() !== '' ? v.trim() : undefined;
}

function asNumber(v: unknown): number | undefined {
	return typeof v === 'number' && Number.isFinite(v) ? v : undefined;
}

/** „YYYY-MM-DDTHH:MM" (lokal) → epoch ms; toleriert auch epoch-ms-Numbers. Wirft bei ungültigem Format. */
function localToMs(v: unknown): number | undefined {
	if (typeof v === 'number' && Number.isFinite(v)) return v;
	if (typeof v === 'string' && v.trim() !== '') return localInputToMs(v.trim());
	return undefined;
}

function localToMsSafe(v: unknown): number | undefined {
	try {
		return localToMs(v);
	} catch {
		return undefined;
	}
}

function buildEventInput(args: Record<string, unknown>): EventUpdateInput {
	const allDay = args.allDay === true;
	return {
		summary: asString(args.summary) ?? '',
		location: asString(args.location),
		description: asString(args.description),
		allDay,
		dayKey: asString(args.dayKey),
		endDateKey: asString(args.endDateKey),
		startMs: localToMs(args.startLocal),
		endMs: localToMs(args.endLocal)
	};
}

function buildTaskDue(args: Record<string, unknown>): TaskUpdateInput['due'] | undefined {
	const due = args.due;
	if (due == null || typeof due !== 'object') return undefined;
	const d = due as Record<string, unknown>;
	if (d.kind === 'none') return { kind: 'none' };
	if (d.kind === 'date') {
		const key = asString(d.key);
		if (!key) throw new Error('due.key fehlt bei kind="date".');
		return { kind: 'date', key };
	}
	if (d.kind === 'time') {
		const ms = localToMs(d.local ?? d.ms);
		if (ms == null) throw new Error('due.local fehlt bei kind="time" (Format "YYYY-MM-DDTHH:MM").');
		return { kind: 'time', ms };
	}
	throw new Error('due.kind muss "none", "date" oder "time" sein.');
}

export async function runWriteTool(
	ctx: ExecContext,
	name: string,
	args: Record<string, unknown>
): Promise<ToolResult> {
	try {
		switch (name) {
			case 'create_event': {
				const calendarId = asString(args.calendarId);
				if (!calendarId) throw new Error('calendarId fehlt.');
				const input: EventCreateInput = { ...buildEventInput(args), calendarId };
				const ev = await createEvent(ctx.connections, input);
				return ok({
					created: true,
					uid: ev.uid,
					summary: ev.summary,
					calendarName: ev.calendarName,
					...(ev.allDay ? { dayKey: toDayKey(ev.startMs) } : { startMs: ev.startMs, endMs: ev.endMs })
				});
			}
			case 'update_event': {
				const calendarId = asString(args.calendarId);
				const uid = asString(args.uid);
				if (!calendarId || !uid) throw new Error('calendarId und uid erforderlich.');
				const ev = await mutateEvent(ctx.connections, calendarId, uid, buildEventInput(args));
				return ok({
					updated: true,
					uid: ev.uid,
					summary: ev.summary,
					...(ev.allDay ? { dayKey: toDayKey(ev.startMs) } : { startMs: ev.startMs, endMs: ev.endMs })
				});
			}
			case 'delete_event': {
				const calendarId = asString(args.calendarId);
				const uid = asString(args.uid);
				if (!calendarId || !uid) throw new Error('calendarId und uid erforderlich.');
				await removeEvent(ctx.connections, calendarId, uid);
				return ok({ deleted: true, uid });
			}
			case 'create_task': {
				const conns = ctx.connections;
				if (conns.length === 0) throw new Error('Keine CalDAV-Verbindung vorhanden.');
				let calendarId = asString(args.calendarId);
				if (!calendarId) {
					const { items } = await resolveAllCalendars(conns);
					const first = publicCalendars(items)[0];
					if (!first) throw new Error('Kein Kalender gefunden.');
					calendarId = first.id;
				}
				const input: TaskCreateInput = {
					summary: asString(args.summary) ?? '',
					calendarId
				};
				const description = asString(args.description);
				if (description) input.description = description;
				if (args.completed === true) input.completed = true;
				const due = buildTaskDue(args);
				if (due) input.due = due;
				const priority = asNumber(args.priority);
				if (priority != null) input.priority = priority;
				const task = await createTask(conns, input);
				return ok({
					created: true,
					uid: task.uid,
					summary: task.summary,
					calendarName: task.calendarName,
					...(task.dueKey ? { dueKey: task.dueKey } : {}),
					...(task.dueMs != null ? { dueMs: task.dueMs } : {})
				});
			}
			case 'update_task': {
				const calendarId = asString(args.calendarId);
				const uid = asString(args.uid);
				if (!calendarId || !uid) throw new Error('calendarId und uid erforderlich.');
				const input: TaskUpdateInput = {};
				const summary = asString(args.summary);
				if (summary) input.summary = summary;
				const description = asString(args.description);
				if (description) input.description = description;
				if (args.completed === true || args.completed === false) input.completed = args.completed;
				const due = buildTaskDue(args);
				if (due) input.due = due;
				const priority = asNumber(args.priority);
				if (priority != null) input.priority = priority;
				const task = await mutateTask(ctx.connections, calendarId, uid, input);
				return ok({
					updated: true,
					uid: task.uid,
					summary: task.summary,
					completed: task.completed,
					...(task.dueKey ? { dueKey: task.dueKey } : {}),
					...(task.dueMs != null ? { dueMs: task.dueMs } : {})
				});
			}
			case 'delete_task': {
				const calendarId = asString(args.calendarId);
				const uid = asString(args.uid);
				if (!calendarId || !uid) throw new Error('calendarId und uid erforderlich.');
				await removeTask(ctx.connections, calendarId, uid);
				return ok({ deleted: true, uid });
			}
			case 'create_workflow': {
				const title = asString(args.title);
				if (!title) throw new Error('title fehlt.');
				const steps = Array.isArray(args.steps) ? (args.steps as unknown[]).filter((s): s is string => typeof s === 'string' && s.trim() !== '') : [];
				if (steps.length === 0) throw new Error('Mindestens ein Schritt erforderlich.');
				const w = await createWorkflow(ctx.userId, { title, steps: steps.map((s) => s.trim()) });
				return ok({ created: true, id: w.id, title: w.title, steps: w.steps.length });
			}
			case 'update_workflow': {
				const id = asString(args.id);
				if (!id) throw new Error('id fehlt.');
				const patch: { title?: string; notes?: string } = {};
				const title = asString(args.title);
				if (title) patch.title = title;
				const notes = asString(args.notes);
				if (notes !== undefined) patch.notes = notes;
				const w = await updateWorkflow(ctx.userId, id, patch);
				if (!w) throw new Error('Workflow nicht gefunden.');
				return ok({ updated: true, id: w.id, title: w.title });
			}
			case 'add_workflow_step': {
				const id = asString(args.id);
				const title = asString(args.title);
				if (!id || !title) throw new Error('id und title erforderlich.');
				const w = await addStep(ctx.userId, id, title);
				if (!w) throw new Error('Workflow nicht gefunden.');
				return ok({ added: true, workflowId: w.id, stepCount: w.steps.length, title: w.title });
			}
			case 'set_workflow_step': {
				const id = asString(args.id);
				const stepId = asString(args.stepId);
				const done = args.done === true;
				if (!id || !stepId) throw new Error('id und stepId erforderlich.');
				const w = await updateStep(ctx.userId, id, stepId, { done });
				if (!w) throw new Error('Workflow oder Schritt nicht gefunden.');
				return ok({
					set: true,
					workflowId: w.id,
					stepId,
					done,
					progress: w.progress,
					completed: w.completedAt != null
				});
			}
			case 'delete_workflow': {
				const id = asString(args.id);
				if (!id) throw new Error('id fehlt.');
				const deleted = await deleteWorkflow(ctx.userId, id);
				if (!deleted) throw new Error('Workflow nicht gefunden.');
				return ok({ deleted: true, id });
			}
			case 'reset_workflow': {
				const id = asString(args.id);
				if (!id) throw new Error('id fehlt.');
				const w = await resetWorkflow(ctx.userId, id);
				if (!w) throw new Error('Workflow nicht gefunden.');
				return ok({ reset: true, id: w.id, title: w.title, progress: w.progress });
			}
			default:
				return fail(new Error(`Unbekanntes Write-Tool: ${name}`));
		}
	} catch (e) {
		return fail(e);
	}
}

// ── Approval-Überschriften (für die Bestätigungs-Karte) ───────────────────

function fmtTime(ms: number): string {
	const d = new Date(ms);
	return d.toLocaleTimeString('de-DE', { hour: '2-digit', minute: '2-digit' });
}

function fmtDay(keyOrMs: string | number, key: boolean = true): string {
	if (typeof keyOrMs === 'string') {
		const [y, m, day] = keyOrMs.split('-');
		return `${day}.${m}.${y}`;
	}
	const d = new Date(keyOrMs);
	return d.toLocaleDateString('de-DE', { day: '2-digit', month: '2-digit', year: 'numeric' });
}

function dueText(args: Record<string, unknown>): string {
	const due = args.due;
	if (due == null || typeof due !== 'object') return '';
	const d = due as Record<string, unknown>;
	if (d.kind === 'none') return 'Fällig: keine';
	if (d.kind === 'date' && typeof d.key === 'string') return `Fällig: ${fmtDay(d.key)}`;
	if (d.kind === 'time') {
		const ms = localToMsSafe(d.local ?? d.ms);
		if (ms != null) return `Fällig: ${fmtDay(ms, false)} ${fmtTime(ms)}`;
	}
	return '';
}

/** Menschlesbare Kurzbeschreibung für die Approval-Karte. */
export function approvalSummary(name: string, args: Record<string, unknown>): string {
	const g = (k: string): string | undefined => asString(args[k]);
	switch (name) {
		case 'create_event':
		case 'update_event': {
			const summary = g('summary') ?? '';
			if (args.allDay === true) {
				const from = g('dayKey');
				const to = g('endDateKey');
				const when = from
					? to && to !== from
						? `${fmtDay(from)}–${fmtDay(to)}`
						: fmtDay(from)
					: '';
				return `${name === 'create_event' ? 'Termin anlegen' : 'Termin ändern'}: „${summary}"${when ? ' · ' + when : ''}`;
			}
			const startMs = localToMsSafe(args.startLocal);
			const endMs = localToMsSafe(args.endLocal);
			const when = startMs != null ? `${fmtDay(startMs, false)} ${fmtTime(startMs)}${endMs != null ? '–' + fmtTime(endMs) : ''}` : '';
			return `${name === 'create_event' ? 'Termin anlegen' : 'Termin ändern'}: „${summary}"${when ? ' · ' + when : ''}`;
		}
		case 'delete_event':
			return 'Termin löschen';
		case 'create_task': {
			const summary = g('summary') ?? '';
			const due = dueText(args);
			return `Aufgabe anlegen: „${summary}"${due ? ' · ' + due : ''}`;
		}
		case 'update_task': {
			const summary = g('summary');
			const due = dueText(args);
			const parts: string[] = [];
			if (args.completed === true) parts.push('als erledigt markieren');
			if (summary) parts.push(`Titel → „${summary}"`);
			if (due) parts.push(due);
			return `Aufgabe ändern${parts.length ? ': ' + parts.join(', ') : ''}`;
		}
		case 'delete_task':
			return 'Aufgabe löschen';
		case 'create_workflow': {
			const title = g('title') ?? '';
			const steps = Array.isArray(args.steps) ? args.steps.length : 0;
			return `Workflow anlegen: „${title}" (${steps} Schritte)`;
		}
		case 'update_workflow': {
			const title = g('title');
			return title ? `Workflow-Titel ändern: „${title}"` : 'Workflow ändern';
		}
		case 'add_workflow_step':
			return `Schritt hinzufügen: „${g('title') ?? ''}"`;
		case 'set_workflow_step':
			return args.done === true ? 'Schritt als erledigt markieren' : 'Schritt wieder öffnen';
		case 'delete_workflow':
			return 'Workflow löschen';
		case 'reset_workflow':
			return 'Workflow zurücksetzen (alle Schritte offen)';
		default:
			return name;
	}
}

/** Verbindungen nachladen (falls noch nicht geladen). */
export function loadContext(userId: string): ExecContext {
	return { userId, connections: listConnections(userId) };
}

/** Effekt eines Tools ermitteln (für Loop-Steuerung). */
export function toolEffect(name: string): 'read' | 'write' | null {
	return TOOL_BY_NAME.get(name)?.effect ?? null;
}
