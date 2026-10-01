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
