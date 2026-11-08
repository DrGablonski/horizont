// Wandelt rohe ics-Blöcke in EventItem-Listen um. Wiederholungen werden per
// ical.js-RekurExpansion expandiert (echte DTSTART ⇒ korrekte UNTIL/COUNT-
// Semantik), auf den Zielzeitraum gefiltert und nach Beginn sortiert.
//
// ical.js-Objekte werden intern bewusst mit `any` gehandhabt, da die
// generierten Typen an mehreren Stellen unvollständig sind; die öffentlichen
// Signaturen bleiben strikt.

import Ical from 'ical.js';
import type { CalDavCalendar, EventItem } from '$lib/types';
import { MAX_OCCURRENCES } from '$server/lib/constants';

const DAY_MS = 86_400_000;

// Strukturelles Minimum eines ical.js Time-Objekts.
interface IcalTimeLike {
	isDate: boolean;
	year: number;
	month: number; // 1–12
	day: number;
	toJSDate(): Date;
}

/**
 * ical.js Time → epoch ms. Für reine Datumswerte (isDate, all-day) wird
 * bewusst lokal aus den Datumsfeldern gebildet (Zeitzone-unabhängig korrekt);
 * für Datumszeiten liefert toJSDate() die korrekte absolute Zeit.
 */
function toMs(t: IcalTimeLike): number {
	if (t.isDate) {
		return new Date(t.year, t.month - 1, t.day).getTime();
	}
	return t.toJSDate().getTime();
}

function str(v: unknown): string | undefined {
	if (v == null) return undefined;
	const s = String(v).trim();
	return s.length ? s : undefined;
}

export function icalToEventItems(
	icsList: string[],
	calendar: CalDavCalendar,
	rangeStart: number,
	rangeEnd: number
): EventItem[] {
	const items: EventItem[] = [];

	for (const ics of icsList) {
		let comp: any;
		try {
			comp = new Ical.Component(Ical.parse(ics) as any);
		} catch {
			continue;
		}

		const vevents: any[] = comp.getAllSubcomponents('vevent') ?? [];

		for (const v of vevents) {
			let ev: any;
			try {
				ev = new Ical.Event(v);
			} catch {
				continue;
			}

			const summary = str(ev.component?.getFirstPropertyValue?.('summary')) ?? '(Kein Titel)';
			const location = str(ev.component?.getFirstPropertyValue?.('location'));
			const description = str(ev.component?.getFirstPropertyValue?.('description'));
			const uid = str(ev.component?.getFirstPropertyValue?.('uid')) ?? 'n/a';
			const allDay = Boolean(ev.startDate?.isDate);

			const pushOccurrence = (start: IcalTimeLike) => {
				let startMs: number;
				let endMs: number;
				try {
					const d: any = ev.getOccurrenceDetails(start);
					startMs = toMs(d.startDate as IcalTimeLike);
					endMs = toMs(d.endDate as IcalTimeLike);
				} catch {
					startMs = toMs(start);
					endMs = startMs + (allDay ? DAY_MS : 3_600_000);
				}
				// Keine Überschneidung mit dem Zielzeitraum → verwerfen.
				if (endMs <= rangeStart || startMs >= rangeEnd) return;

				items.push({
					id: `${calendar.id}|${uid}|${startMs}`,
					uid,
					calendarId: calendar.id,
					calendarName: calendar.name,
					calendarColor: calendar.color,
					summary,
					location,
					description,
					startMs,
					endMs,
					allDay
				});
			};

			const dtstart = ev.startDate as IcalTimeLike | undefined;
			if (!dtstart) continue;

			if (!ev.isRecurring()) {
				pushOccurrence(dtstart);
			} else {
				const exp: any = ev.iterator(); // echte DTSTART → korrekte Wiederholungs-Semantik
				let count = 0;
				let t: IcalTimeLike | undefined = exp.next() as IcalTimeLike | undefined;
				while (t && count < MAX_OCCURRENCES) {
					const tMs = toMs(t);
					if (tMs > rangeEnd) break; // chronologisch sortiert ⇒ darüber endet die Schleife
					pushOccurrence(t);
					count++;
					t = exp.next() as IcalTimeLike | undefined;
				}
			}
		}
	}

	items.sort((a, b) => a.startMs - b.startMs || a.summary.localeCompare(b.summary, 'de'));
	return items;
}

// ── Tasks (VTODO) ─────────────────────────────────────────────────────────

import type { TaskItem } from '$lib/types';

export function icalToTaskItems(ics: string, calendar: CalDavCalendar): TaskItem[] {
	const out: TaskItem[] = [];

	let comp: any;
	try {
		comp = new Ical.Component(Ical.parse(ics) as any);
	} catch {
		return out;
	}

	const vtodos: any[] = comp.getAllSubcomponents('vtodo') ?? [];

	for (const v of vtodos) {
		const uid = str(v.getFirstPropertyValue?.('uid')) ?? 'n/a';
		const summary = str(v.getFirstPropertyValue?.('summary')) ?? '(Kein Titel)';
		const description = str(v.getFirstPropertyValue?.('description'));

		const completed = v.hasProperty?.('completed') ?? false;

		// COMPLETED-Datum (Tag des Abhakens) lesen – erledigte Tasks landen
		// im Archiv an diesem Tag. ical.js v2 hat kein Component.getProperty;
		// getFirstPropertyValue liefert das Time-Objekt direkt.
		let completedAt: number | null = null;
		try {
			const dt = v.getFirstPropertyValue?.('completed') as IcalTimeLike | null | undefined;
			if (dt && typeof dt.toJSDate === 'function') completedAt = toMs(dt);
		} catch {
			/* ignore */
		}

		let dueKey: string | undefined;
		let dueMs: number | undefined;

		const dueVal = v.getFirstPropertyValue?.('due') as IcalTimeLike | null | undefined;
		if (dueVal && typeof dueVal.toJSDate === 'function') {
			if (dueVal.isDate) {
				const p = (n: number) => String(n).padStart(2, '0');
				dueKey = `${dueVal.year}-${p(dueVal.month)}-${p(dueVal.day)}`;
			} else {
				dueMs = toMs(dueVal);
			}
		}

		let category: string | undefined;
		const catVal = v.getFirstPropertyValue?.('categories');
		const catList = Array.isArray(catVal) ? catVal : [catVal];
		for (const c of catList) {
			const s = str(c);
			if (s) {
				category = s;
				break; // ein Task → eine Kategorie (erste gewinnt)
			}
		}

		let priority: number | undefined;
		const priVal = v.getFirstPropertyValue?.('priority');
		if (priVal != null) {
			const n = Number(priVal);
			if (Number.isInteger(n) && n >= 1 && n <= 9) priority = n;
		}

		out.push({
			id: `${calendar.id}|${uid}`,
			uid,
			calendarId: calendar.id,
			calendarName: calendar.name,
			calendarColor: calendar.color,
			summary,
			description,
			completed,
			completedAt,
			dueKey,
			dueMs,
			category,
			priority
		});
	}

	return out;
}
