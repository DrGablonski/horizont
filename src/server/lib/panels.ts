// Baut aus CalDAV-Events die drei Zeit-Panel (Vergangenheit/Jetzt/Zukunft)
// sowie die archivierten Monatsansichten. Events werden pro Tag per
// Überschneidung gebucketed, damit mehrtägige/laufende Einträge auf jedem
// aktiven Tag erscheinen.

import type {
	ArchiveMonth,
	CalDavConnection,
	CalendarView,
	DayGroup,
	EventItem,
	MainEventsResponse,
	PanelId,
	TimePanel
} from '$lib/types';
import {
	addDaysMs,
	dayKey,
	dayKeysBetween,
	dayLabel,
	isValidMonthKey,
	msFromKey,
	monthGridDays,
	monthKeyFromMs,
	monthStartMs,
	shiftMonthKey,
	startOfDayMs,
	todayKey,
	toIcsUtc
} from '$lib/dates';
import {
	ARCHIVE_GAP_DAYS,
	ARCHIVE_TOTAL_DAYS,
	MAIN_END_DAYS_AHEAD_EXCL,
	MAIN_START_DAYS_BACK,
	FUTURE_DAYS,
	NOW_EXTRA_DAYS,
	PAST_DAYS
} from '$server/lib/constants';
import { fetchCalendarIcs } from '$server/caldav/client';
import { resolveCalendarViews, type ResolvedCalendar } from '$server/caldav/multi';
import { icalToEventItems } from '$server/caldav/ical';
import { listAllTasksForItems } from '$server/lib/write';
import { cached } from '$server/lib/panelCache';
import { getCategories } from '$server/store/categories';
import type { TaskItem } from '$lib/types';

interface Range {
	startMs: number;
	endMs: number; // exklusiv
}

// ── Zeitfenster (relativ zu heute, Mitternacht lokal) ─────────────────────

export function mainRange(todayStart: number): Range {
	return {
		startMs: addDaysMs(todayStart, -MAIN_START_DAYS_BACK),
		endMs: addDaysMs(todayStart, MAIN_END_DAYS_AHEAD_EXCL)
	};
}

export function panelRange(todayStart: number, id: PanelId): Range {
	switch (id) {
		case 'past':
			return { startMs: addDaysMs(todayStart, -PAST_DAYS), endMs: todayStart };
		case 'now':
			return { startMs: todayStart, endMs: addDaysMs(todayStart, NOW_EXTRA_DAYS + 1) };
		case 'future':
			return {
				startMs: addDaysMs(todayStart, NOW_EXTRA_DAYS + 1),
				endMs: addDaysMs(todayStart, NOW_EXTRA_DAYS + 1 + FUTURE_DAYS)
			};
	}
}

function emptyResponse(base: Omit<MainEventsResponse, 'panels'>): MainEventsResponse {
	const panels: TimePanel[] = (['past', 'now', 'future'] as PanelId[]).map((id) => ({
		id,
		title: PANEL_TITLES[id].title,
		subtitle: PANEL_TITLES[id].subtitle,
		days: [],
		eventCount: 0,
		defaultOpen: id === 'now'
	}));
	return { ...base, panels };
}

const PANEL_TITLES: Record<PanelId, { title: string; subtitle: string }> = {
	past: { title: 'Vergangenheit', subtitle: `Die letzten ${PAST_DAYS} Tage` },
	now: { title: 'Jetzt', subtitle: 'Heute und die kommenden Tage' },
	future: { title: 'Zukunft', subtitle: `Die nächsten ${FUTURE_DAYS} Tage` }
};

// ── Bucketing ─────────────────────────────────────────────────────────────

/** Gruppiert Ereignisse + Aufgaben pro Tag (auch Tage nur mit Aufgaben). */
function bucketDaysMerged(
	events: EventItem[],
	tasks: EventItem[],
	keys: string[],
	today: string
): DayGroup[] {
	const groups: DayGroup[] = [];
	for (const k of keys) {
		const dStart = msFromKey(k);
		const dEnd = addDaysMs(dStart, 1);
		const evs = events
			.filter((e) => e.startMs < dEnd && e.endMs > dStart)
			.sort((a, b) => a.startMs - b.startMs || a.summary.localeCompare(b.summary, 'de'));
		const tks = tasksForDay(tasks, dStart, dEnd);
		if (evs.length === 0 && tks.length === 0) continue;
		groups.push({ dayKey: k, label: dayLabel(k), isToday: k === today, events: [...evs, ...tks] });
	}
	return groups;
}

function categoryColorMap(userId: string): Map<string, string> {
	return new Map(getCategories(userId).map((c) => [c.name.toLowerCase(), c.color]));
}

/**
 * Ordnet aufgelöste Kalender (ohne ausgeblendete) ihren Verbindungen zu,
 * damit Events/Tasks pro Kalender parallel abgefragt werden können.
 * Kalender ohne zugehörige Verbindung (z. B. gelöst) werden übersprungen.
 */
function toResolvedItems(connections: CalDavConnection[], calendars: CalendarView[]): ResolvedCalendar[] {
	const byId = new Map(connections.map((c) => [c.id, c]));
	return calendars.flatMap((calendar) => {
		const connection = byId.get(calendar.connectionId);
		return connection ? [{ connection, calendar }] : [];
	});
}

// ── Hauptansicht ──────────────────────────────────────────────────────────

/** Events aus bereits aufgelösten Kalendern holen — pro Kalender parallel. */
async function fetchEventsForItems(
	items: ResolvedCalendar[],
	resolveErrors: string[],
	rangeStart: number,
	rangeEnd: number
): Promise<{ events: EventItem[]; errors: string[] }> {
	const errors: string[] = [...resolveErrors];
	const perCalendar = await Promise.all(
		items.map(async ({ connection, calendar }) => {
			try {
				const icsList = await fetchCalendarIcs(
					connection,
					calendar,
					toIcsUtc(rangeStart),
					toIcsUtc(rangeEnd)
				);
				return icalToEventItems(icsList, calendar, rangeStart, rangeEnd);
			} catch (e) {
				errors.push(`${calendar.connectionName}: ${e instanceof Error ? e.message : String(e)}`);
				return [] as EventItem[];
			}
		})
	);
	const events = perCalendar.flat();
	events.sort((a, b) => a.startMs - b.startMs || a.summary.localeCompare(b.summary, 'de'));
	return { events, errors };
}

// ── Tasks in die Timeline einbetten ──────────────────────────────────────

/** Wandelt eine CalDAV-Aufgabe (VTODO) in einen Timeline-Eintrag um. */
function taskToTimelineItem(t: TaskItem, colors: Map<string, string>): EventItem {
	const anchorMs = t.dueMs ?? (t.dueKey ? msFromKey(t.dueKey) : null);
	return {
		id: `task:${t.calendarId}:${t.uid}`,
		uid: t.uid,
		calendarId: t.calendarId,
		calendarName: t.calendarName,
		calendarColor: t.calendarColor,
		summary: t.summary,
		description: t.description,
		startMs: anchorMs ?? 0,
		endMs: (anchorMs ?? 0) + 1,
		allDay: true,
		kind: 'task',
		completed: t.completed,
		completedAt: t.completedAt ?? null,
		category: t.category,
		categoryColor: t.category
			? colors.get(t.category.toLowerCase()) ?? '#64748b'
			: undefined,
		dueKey: t.dueKey,
		dueMs: t.dueMs
	};
}

/** Tasks, die auf diesem Tag fällig sind (Stichtag oder Datum-Fälligkeit). */
function tasksForDay(tasks: EventItem[], dayStart: number, dayEnd: number): EventItem[] {
	return tasks
		.filter((t) => (t.dueMs != null && t.dueMs >= dayStart && t.dueMs < dayEnd) ||
			(t.dueMs == null && t.dueKey != null && msFromKey(t.dueKey) === dayStart))
		.sort(
			(a, b) =>
				(a.completed ? 1 : 0) - (b.completed ? 1 : 0) ||
				(a.dueMs ?? Infinity) - (b.dueMs ?? Infinity) ||
				a.summary.localeCompare(b.summary, 'de')
		);
}

export function buildMainResponse(
	userId: string,
	connections: CalDavConnection[]
): Promise<MainEventsResponse> {
	const today = todayKey();
	// Kurzer TTL + Invalidierung bei jeder Schreiboperation (panelCache).
	return cached(`main:${userId}:${today}`, () => buildMain(userId, connections, today));
}

async function buildMain(
	userId: string,
	connections: CalDavConnection[],
	today: string
): Promise<MainEventsResponse> {
	const todayStart = msFromKey(today);
	const base: Omit<MainEventsResponse, 'panels'> = {
		todayKey: today,
		generatedAt: Date.now(),
		configured: connections.length > 0
	};

	if (connections.length === 0) return emptyResponse(base);

	const { startMs, endMs } = mainRange(todayStart);
	// Kalender (ausgeblendete ausgeschlossen) nur einmal auflösen, Events und
	// Tasks parallel davon ableiten. Fehler einzelner Verbindungen sammeln.
	const { calendars, errors: resolveErrors } = await resolveCalendarViews(userId, connections, {
		includeHidden: false
	});
	const items = toResolvedItems(connections, calendars);
	const taskErrors: string[] = [];
	const [{ events, errors }, rawTasks] = await Promise.all([
		fetchEventsForItems(items, resolveErrors, startMs, endMs),
		listAllTasksForItems(items).catch((e) => {
			taskErrors.push(`Aufgaben: ${e instanceof Error ? e.message : String(e)}`);
			return [] as TaskItem[];
		})
	]);
	const error = errors.length + taskErrors.length > 0 ? [...errors, ...taskErrors].join(' | ') : null;

	// Aufgaben mitten unter die Kalender-Ereignisse mischen.
	// Erledigte (abgehakte) Tasks bleiben auf der Startseite ausgespart –
	// sie landen im Archiv (dort am Tag des Abhakens).
	const colors = categoryColorMap(userId);
	const tasks = rawTasks
		.map((t) => taskToTimelineItem(t, colors))
		.filter((t) => !t.completed);
	const unscheduled = tasks.filter((t) => t.dueKey == null && t.dueMs == null);

	// Überfällige, offene Aufgaben „wandern": sie bleiben nicht am alten
	// Fälligkeitstag stehen, sondern erscheinen ab sofort jeden Tag bei
	// „Heute" — dort mit rotem Minus als überfällig markiert.
	const overdue = tasks
		.filter(
			(t) =>
				!t.completed &&
				((t.dueKey != null && t.dueKey < today) || (t.dueMs != null && t.dueMs < todayStart))
		)
		.sort(
			(a, b) =>
				(a.dueMs ?? msFromKey(a.dueKey ?? today)) - (b.dueMs ?? msFromKey(b.dueKey ?? today))
		);
	const overdueIds = new Set(overdue.map((t) => t.id));
	const dayTasks = tasks.filter((t) => !overdueIds.has(t.id));

	const panels: TimePanel[] = (['past', 'now', 'future'] as PanelId[]).map((id) => {
		const r = panelRange(todayStart, id);
		const keys = dayKeysBetween(r.startMs, r.endMs);
		const groups = bucketDaysMerged(events, dayTasks, keys, today);

		// „Jetzt": heute immer zeigen (auch ohne Einträge → „nichts geplant").
		if (id === 'now' && !groups.some((g) => g.dayKey === today)) {
			const idx = Math.max(0, keys.indexOf(today));
			groups.splice(idx, 0, { dayKey: today, label: dayLabel(today), isToday: true, events: [] });
		}
		// Überfällige + Aufgaben ohne Fälligkeitsdatum gehören in den heutigen Tag.
		if (id === 'now') {
			const todayGroup = groups.find((g) => g.dayKey === today);
			if (todayGroup)
				todayGroup.events = [
					...todayGroup.events,
					...overdue.map((t) => ({ ...t, overdue: true })),
					...unscheduled.sort((a, b) => (a.completed ? 1 : 0) - (b.completed ? 1 : 0))
				];
		}

		const eventCount = groups.reduce((n, g) => n + g.events.length, 0);
		return {
			id,
			title: PANEL_TITLES[id].title,
			subtitle: PANEL_TITLES[id].subtitle,
			days: groups,
			eventCount,
			defaultOpen: id === 'now'
		};
	});

	return { ...base, panels, error: error ?? undefined };
}

// ── Archiv (Monatsansicht) ────────────────────────────────────────────────

export interface ArchiveWindow {
	oldest: string; // ältester Archiv-Tag (YYYY-MM-DD)
	newest: string; // neuester Archiv-Tag (YYYY-MM-DD, inklusiv)
}

export function archiveWindow(todayStart: number): ArchiveWindow {
	const oldest = dayKey(addDaysMs(todayStart, -ARCHIVE_TOTAL_DAYS));
	const newest = dayKey(addDaysMs(todayStart, -(ARCHIVE_GAP_DAYS - 1))); // Grenze zu „Vergangenheit"
	return { oldest, newest };
}

export function buildArchiveMonthResponse(
	userId: string,
	connections: CalDavConnection[],
	requestedMonthKey: string | null
): Promise<ArchiveMonth> {
	const today = todayKey();
	const todayStart = msFromKey(today);
	const win = archiveWindow(todayStart);
	const latestMonth = monthKeyFromMs(msFromKey(win.newest));

	// Angefragten Monat (falls gültig) in den Archivbereich klemmen,
	// andernfalls den neuesten Archiv-Monat zeigen.
	let monthKey: string;
	if (isValidMonthKey(requestedMonthKey)) {
		monthKey = requestedMonthKey;
		if (monthKey + '-01' > win.newest) monthKey = latestMonth;
		else if (shiftMonthKey(monthKey, 1) + '-01' <= win.oldest)
			monthKey = monthKeyFromMs(msFromKey(win.oldest));
	} else {
		monthKey = latestMonth;
	}

	const out: Omit<ArchiveMonth, 'days' | 'eventCount'> = {
		monthKey,
		rangeStart: win.oldest,
		rangeEnd: win.newest,
		canPrev: monthKey + '-01' > win.oldest, // Tag vor Monatsbeginn liegt noch im Archiv
		canNext: shiftMonthKey(monthKey, 1) + '-01' <= win.newest,
		configured: connections.length > 0
	};

	// Gleicher Mechanismus wie die Hauptansicht (TTL + Invalidierung).
	return cached(`archive:${userId}:${monthKey}:${today}`, () =>
		buildArchive(userId, connections, out, today)
	);
}

async function buildArchive(
	userId: string,
	connections: CalDavConnection[],
	out: Omit<ArchiveMonth, 'days' | 'eventCount'>,
	today: string
): Promise<ArchiveMonth> {
	if (connections.length === 0) {
		return { ...out, days: [], eventCount: 0 };
	}

	const todayStart = msFromKey(today);
	const win = archiveWindow(todayStart);

	// Events für das ganze Monatsraster holen, aber nur innerhalb des
	// Archivbereichs (außerhalb liegen Tage der Hauptansicht).
	// Dazu die Aufgaben (VTODOs): sie erscheinen im Archiv an ihrem
	// Fälligkeitstag — erledigte mit Haken/Durchstrich.
	const monthKey = out.monthKey;
	const grid = monthGridDays(monthKey);
	const gridStart = msFromKey(grid[0]);
	const gridEnd = addDaysMs(msFromKey(grid[grid.length - 1]), 1);
	const startMs = Math.max(gridStart, msFromKey(win.oldest));
	const endMs = Math.min(gridEnd, addDaysMs(msFromKey(win.newest), 1));
	let events: EventItem[] = [];
	let error: string | null = null;
	// Kalender (ausgeblendete ausgeschlossen) nur einmal auflösen, Events +
	// Tasks parallel ableiten. Fehler einzelner Verbindungen sammeln.
	const { calendars, errors: resolveErrors } = await resolveCalendarViews(userId, connections, {
		includeHidden: false
	});
	const items = toResolvedItems(connections, calendars);
	const taskErrors: string[] = [];
	const [fetched, rawTasks] = await Promise.all([
		startMs < endMs
			? fetchEventsForItems(items, resolveErrors, startMs, endMs)
			: Promise.resolve({ events: [] as EventItem[], errors: [] as string[] }),
		listAllTasksForItems(items).catch((e) => {
			taskErrors.push(`Aufgaben: ${e instanceof Error ? e.message : String(e)}`);
			return [] as TaskItem[];
		})
	]);
	events = fetched.events;
	error =
		fetched.errors.length + taskErrors.length > 0
			? [...fetched.errors, ...taskErrors].join(' | ')
			: null;

	const colors = categoryColorMap(userId);
	const tasks = rawTasks.map((t) => {
		const item = taskToTimelineItem(t, colors);
		// Erledigte Tasks landen im Archiv am Tag des Abhakens (COMPLETED);
		// ohne Erledigungs-Datum bleibt der alte Fälligkeitstag als Anker.
		if (item.completed && item.completedAt != null) {
			item.dueKey = dayKey(item.completedAt);
			item.dueMs = undefined;
		}
		return item;
	});

	const groups = bucketDaysMerged(events, tasks, grid, today);
	const eventCount = groups
		.filter((g) => g.dayKey.startsWith(monthKey))
		.reduce((n, g) => n + g.events.length, 0);
	return { ...out, days: groups, eventCount, error: error ?? undefined };
}
