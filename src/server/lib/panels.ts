// Baut aus CalDAV-Events die drei Zeit-Panel (Vergangenheit/Jetzt/Zukunft)
// sowie die archivierten Seiten. Events werden pro Tag per Überschneidung
// gebucketed, damit mehrtägige/laufende Einträge auf jedem aktiven Tag
// erscheinen.

import type {
	ArchivePage,
	CalDavConnection,
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
	msFromKey,
	startOfDayMs,
	todayKey,
	toIcsUtc
} from '$lib/dates';
import {
	ARCHIVE_GAP_DAYS,
	ARCHIVE_PAGE_DAYS,
	ARCHIVE_TOTAL_DAYS,
	MAIN_END_DAYS_AHEAD_EXCL,
	MAIN_START_DAYS_BACK,
	FUTURE_DAYS,
	NOW_EXTRA_DAYS,
	PAST_DAYS
} from '$server/lib/constants';
import { fetchCalendarIcs } from '$server/caldav/client';
import { resolveAllCalendars } from '$server/caldav/multi';
import { icalToEventItems } from '$server/caldav/ical';

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

/** Gruppiert Events, die einen der übergebenen Tage (inklusiv) berühren. */
function bucketDays(events: EventItem[], keys: string[], today: string): DayGroup[] {
	const groups: DayGroup[] = [];
	for (const k of keys) {
		const dStart = msFromKey(k);
		const dEnd = addDaysMs(dStart, 1);
		const evs = events
			.filter((e) => e.startMs < dEnd && e.endMs > dStart)
			.sort((a, b) => a.startMs - b.startMs || a.summary.localeCompare(b.summary, 'de'));
		if (evs.length === 0) continue;
		groups.push({ dayKey: k, label: dayLabel(k), isToday: k === today, events: evs });
	}
	return groups;
}

// ── Hauptansicht ──────────────────────────────────────────────────────────

async function fetchEventsInRange(
	connections: CalDavConnection[],
	rangeStart: number,
	rangeEnd: number
): Promise<{ events: EventItem[]; error: string | null; errors: string[] }> {
	try {
		const { items, errors } = await resolveAllCalendars(connections);
		const events: EventItem[] = [];
		for (const { connection, calendar } of items) {
			const icsList = await fetchCalendarIcs(connection, calendar, toIcsUtc(rangeStart), toIcsUtc(rangeEnd));
			events.push(...icalToEventItems(icsList, calendar, rangeStart, rangeEnd));
		}
		events.sort((a, b) => a.startMs - b.startMs || a.summary.localeCompare(b.summary, 'de'));
		return {
			events,
			error: errors.length > 0 ? errors.join(' | ') : null,
			errors
		};
	} catch (e) {
		return { events: [], error: e instanceof Error ? e.message : String(e), errors: [] };
	}
}

export async function buildMainResponse(connections: CalDavConnection[]): Promise<MainEventsResponse> {
	const today = todayKey();
	const todayStart = msFromKey(today);
	const base: Omit<MainEventsResponse, 'panels'> = {
		todayKey: today,
		generatedAt: Date.now(),
		configured: connections.length > 0
	};

	if (connections.length === 0) return emptyResponse(base);

	const { startMs, endMs } = mainRange(todayStart);
	const { events, error } = await fetchEventsInRange(connections, startMs, endMs);

	const panels: TimePanel[] = (['past', 'now', 'future'] as PanelId[]).map((id) => {
		const r = panelRange(todayStart, id);
		const keys = dayKeysBetween(r.startMs, r.endMs);
		const groups = bucketDays(events, keys, today);

		// „Jetzt": heute immer zeigen (auch ohne Einträge → „nichts geplant").
		if (id === 'now' && !groups.some((g) => g.dayKey === today)) {
			const idx = Math.max(0, keys.indexOf(today));
			groups.splice(idx, 0, { dayKey: today, label: dayLabel(today), isToday: true, events: [] });
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

// ── Archiv (paginiert, neueste Seite zuerst) ──────────────────────────────

export interface ArchiveMeta {
	keys: string[]; // alle Archiv-Tage, aufsteigend (ältester → neuester)
	totalDays: number;
}

export function archiveMeta(todayStart: number): ArchiveMeta {
	const oldest = addDaysMs(todayStart, -ARCHIVE_TOTAL_DAYS);
	const newestExcl = addDaysMs(todayStart, -(ARCHIVE_GAP_DAYS - 1)); // Grenze zu „Vergangenheit"
	const keys = dayKeysBetween(oldest, newestExcl);
	return { keys, totalDays: keys.length };
}

export async function buildArchiveResponse(
	connections: CalDavConnection[],
	page: number
): Promise<ArchivePage> {
	const today = todayKey();
	const todayStart = msFromKey(today);
	const meta = archiveMeta(todayStart);
	const pageSafe = Math.max(1, Math.trunc(page) || 1);

	const out: Omit<ArchivePage, 'days' | 'eventCount'> = {
		page: pageSafe,
		hasMore: false,
		configured: connections.length > 0
	};

	if (connections.length === 0 || meta.totalDays === 0) {
		return { ...out, days: [], eventCount: 0 };
	}

	const startIdx = (pageSafe - 1) * ARCHIVE_PAGE_DAYS;
	const pageKeysAsc = meta.keys.slice(startIdx, startIdx + ARCHIVE_PAGE_DAYS);
	if (pageKeysAsc.length === 0) {
		return { ...out, days: [], eventCount: 0 };
	}

	out.hasMore = startIdx + ARCHIVE_PAGE_DAYS < meta.totalDays;

	const pageStart = msFromKey(pageKeysAsc[0]);
	const pageEnd = addDaysMs(msFromKey(pageKeysAsc[pageKeysAsc.length - 1]), 1);
	const { events, error } = await fetchEventsInRange(connections, pageStart, pageEnd);

	const groups = bucketDays(events, pageKeysAsc, today);
	const eventCount = groups.reduce((n, g) => n + g.events.length, 0);
	return { ...out, days: groups, eventCount, error: error ?? undefined };
}
