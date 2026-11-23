// Tests für die ICS-Erzeugung/-Aktualisierung (icswriter.ts). Alle Assertions
// orientieren sich am realen Verhalten (floating local ohne Z, kein SEQUENCE-
// Bump, PRIORITY nur als Lösch-Fallback bei Kategorie-Änderung).
import { describe, expect, it } from 'bun:test';
import {
	addOneDayToKey,
	buildEventIcs,
	buildTaskIcs,
	foldIcs,
	timeFromMs,
	unfold,
	updateEventIcs,
	updateTaskIcs
} from '$server/caldav/icswriter';

/** Zeitzone-unabhängige floating-Lokal-Komponenten aus lokaler Zeitangabe. */
function localMs(y: number, mo: number, d: number, h: number, mi: number): number {
	return new Date(y, mo - 1, d, h, mi, 0).getTime();
}

/** Aufspalten in Zeilen (nach Unfold), damit Assertions gegen Einzelzeilen laufen. */
function lines(ics: string): string[] {
	return unfold(ics).split('\r\n');
}

describe('buildEventIcs – mit Zeiten (floating local)', () => {
	const ms = localMs(2025, 3, 1, 10, 0);
	const built = buildEventIcs('uid-1@test', {
		summary: 'Test & Termin',
		description: 'Ein Text',
		allDay: false,
		startMs: ms,
		endMs: ms + 3600_000
	});

	it('erhält UID, SUMMARY, DTSTART/DTEND im Roundtrip', () => {
		const l = lines(built.ics);
		expect(built.uid).toBe('uid-1@test');
		expect(l).toContain('UID:uid-1@test');
		expect(l).toContain('SUMMARY:Test & Termin');
		expect(l).toContain('DTSTART:20250301T100000');
		expect(l).toContain('DTEND:20250301T110000');
		expect(l).toContain('DESCRIPTION:Ein Text');
		expect(l[0]).toBe('BEGIN:VCALENDAR');
		expect(l[l.length - 1]).toBe('END:VCALENDAR');
		expect(l).toContain('VERSION:2.0');
	});

	it('schreibt Zeiten ohne Z und ohne TZID (floating)', () => {
		expect(built.ics).not.toMatch(/DT(START|END)[^;]*Z/);
		expect(built.ics).not.toContain('TZID');
	});

	it('verwirft leere/Whitespace-Optionalfelder', () => {
		const b = buildEventIcs('u2', {
			summary: 'S',
			location: '   ',
			description: '',
			allDay: false,
			startMs: ms,
			endMs: ms + 60_000
		});
		const l = lines(b.ics);
		expect(l.some(l => l.startsWith('LOCATION'))).toBe(false);
		expect(l.some(l => l.startsWith('DESCRIPTION'))).toBe(false);
	});
});

describe('buildEventIcs – ganztägig', () => {
	it('nutzt VALUE=DATE und exklusives DTEND = Folgetag', () => {
		const b = buildEventIcs('uid-ad', {
			summary: 'Ganztag',
			allDay: true,
			dayKey: '2025-03-01',
			endDateKey: '2025-03-02'
		});
		const l = lines(b.ics);
		expect(l).toContain('DTSTART;VALUE=DATE:20250301');
		expect(l).toContain('DTEND;VALUE=DATE:20250303');
	});

	it('nutzt ohne endDateKey denselben Tag (DTEND = Tag + 1)', () => {
		const b = buildEventIcs('uid-ad2', { summary: 'Eintägig', allDay: true, dayKey: '2025-03-01' });
		expect(lines(b.ics)).toContain('DTEND;VALUE=DATE:20250302');
	});
});

describe('updateEventIcs', () => {
	const ms = localMs(2025, 3, 1, 10, 0);
	const base = buildEventIcs('uid-1@test', {
		summary: 'Alt',
		description: 'Text',
		allDay: false,
		startMs: ms,
		endMs: ms + 3600_000
	}).ics;

	it('hält die UID und aktualisiert Felder', () => {
		const up = updateEventIcs(base, 'uid-1@test', {
			summary: 'Neu',
			description: 'Text',
			allDay: false,
			startMs: ms,
			endMs: ms + 7200_000
		});
		const l = lines(up.ics);
		expect(up.uid).toBe('uid-1@test');
		expect(l).toContain('UID:uid-1@test');
		expect(l).toContain('SUMMARY:Neu');
		expect(l).toContain('DTEND:20250301T120000');
	});

	it('setzt KEIN SEQUENCE (Aktualisierungen laufen über If-Match/ETag)', () => {
		const up = updateEventIcs(base, 'uid-1@test', {
			summary: 'Neu',
			allDay: false,
			startMs: ms,
			endMs: ms + 3600_000
		});
		expect(unfold(up.ics)).not.toContain('SEQUENCE');
	});

	it('entfernt optionale Felder, die bei Updates nicht mitgegeben werden', () => {
		// Kurioses, aber bewusstes Verhalten: description fehlt in den Update-Feldern
		// → setOptionalText entfernt die bestehende DESCRIPTION.
		const up = updateEventIcs(base, 'uid-1@test', {
			summary: 'Neu',
			allDay: false,
			startMs: ms,
			endMs: ms + 3600_000
		});
		expect(lines(up.ics).some(l => l.startsWith('DESCRIPTION'))).toBe(false);
	});

	it('ergänzt ein neues VEVENT, wenn die UID nicht gefunden wird', () => {
		const up = updateEventIcs(base, 'anderer-uid', {
			summary: 'Zusatz',
			allDay: false,
			startMs: ms,
			endMs: ms + 3600_000
		});
		const text = unfold(up.ics);
		expect(text).toContain('UID:uid-1@test');
		expect(text).toContain('UID:anderer-uid');
		expect(text.match(/BEGIN:VEVENT/g)).toHaveLength(2);
	});
});

describe('buildTaskIcs', () => {
	it('setzt UID, SUMMARY, DUE als Datum und CATEGORIES', () => {
		const b = buildTaskIcs('t-1', {
			summary: 'Einkauf',
			due: { kind: 'date', key: '2025-04-02' },
			category: 'Arbeit'
		});
		const l = lines(b.ics);
		expect(l).toContain('BEGIN:VTODO');
		expect(l).toContain('UID:t-1');
		expect(l).toContain('SUMMARY:Einkauf');
		expect(l).toContain('DUE;VALUE=DATE:20250402');
		expect(l).toContain('CATEGORIES:Arbeit');
		// Der Builder selbst setzt keine PRIORITY.
		expect(l.some(l => l.startsWith('PRIORITY'))).toBe(false);
	});

	it('schreibt COMPLETED nur bei completed=true', () => {
		const offen = buildTaskIcs('t-2', { summary: 'Offen', completed: false });
		expect(lines(offen.ics).some(l => l.startsWith('COMPLETED'))).toBe(false);
		const fertig = buildTaskIcs('t-3', { summary: 'Fertig', completed: true });
		expect(lines(fertig.ics).some(l => l.startsWith('COMPLETED'))).toBe(true);
	});

	it('setzt DUE als floating-Zeitpunkt bzw. entfernt kind „none" DUE', () => {
		const zeit = buildTaskIcs('t-4', { summary: 'S', due: { kind: 'time', ms: localMs(2025, 5, 1, 18, 30) } });
		expect(lines(zeit.ics)).toContain('DUE:20250501T183000');
		const ohne = buildTaskIcs('t-5', { summary: 'S', due: { kind: 'none' } });
		expect(lines(ohne.ics).some(l => l.startsWith('DUE'))).toBe(false);
	});
});

describe('updateTaskIcs', () => {
	function seed(): string {
		const ics = buildTaskIcs('t-10', {
			summary: 'Alt',
			description: 'Notiz',
			completed: true,
			due: { kind: 'date', key: '2025-04-02' },
			category: 'Arbeit'
		}).ics;
		// PRIORITY manuell einschleusen (Kategorie-Fallback aus Altbestand)
		return ics.replace('END:VTODO', 'PRIORITY:3\r\nEND:VTODO');
	}

	it('ändert nur angegebene Felder (patch.summary allein)', () => {
		const up = updateTaskIcs(seed(), 't-10', { summary: 'Neu' });
		const l = lines(up.ics);
		expect(l).toContain('UID:t-10');
		expect(l).toContain('SUMMARY:Neu');
		expect(l).toContain('DESCRIPTION:Notiz');
		expect(l).toContain('CATEGORIES:Arbeit');
		expect(l).toContain('PRIORITY:3'); // categories nicht angefasst → PRIORITY bleibt
	});

	it('ersetzt die Kategorie und entfernt dabei PRIORITY', () => {
		const up = updateTaskIcs(seed(), 't-10', { category: 'Privat' });
		const l = lines(up.ics);
		expect(l).toContain('CATEGORIES:Privat');
		expect(l.some(l => l.startsWith('PRIORITY'))).toBe(false);
	});

	it('entfernt Kategorie und PRIORITY bei category=null', () => {
		const up = updateTaskIcs(seed(), 't-10', { category: null });
		const l = lines(up.ics);
		expect(l.some(l => l.startsWith('CATEGORIES'))).toBe(false);
		expect(l.some(l => l.startsWith('PRIORITY'))).toBe(false);
	});

	it('entfernt COMPLETED bei completed=false und DUE bei due.kind=none', () => {
		const up = updateTaskIcs(seed(), 't-10', { completed: false, due: { kind: 'none' } });
		const l = lines(up.ics);
		expect(l.some(l => l.startsWith('COMPLETED'))).toBe(false);
		expect(l.some(l => l.startsWith('DUE'))).toBe(false);
	});

	it('ergänzt ein neues VTODO bei unbekannter UID', () => {
		const up = updateTaskIcs(seed(), 'neu-uid', { summary: 'Neues Task' });
		const text = unfold(up.ics);
		expect(text).toContain('UID:t-10');
		expect(text).toContain('UID:neu-uid');
		expect(text.match(/BEGIN:VTODO/g)).toHaveLength(2);
	});
});

describe('foldIcs/unfold (RFC 5545 §3.1)', () => {
	it('faltet Zeilen über 75 Oktett und entblättert sauber', () => {
		const lang = 'SUMMARY:' + 'x'.repeat(200);
		const gefaltet = foldIcs(lang);
		expect(gefaltet).toContain('\r\n ');
		for (const zeile of gefaltet.split('\r\n')) {
			expect(Buffer.byteLength(zeile, 'utf8')).toBeLessThanOrEqual(75);
		}
		expect(unfold(gefaltet)).toBe(lang);
	});

	it('faltet byte-bewusst bei Mehrbyte-Zeichen', () => {
		const lang = 'SUMMARY:' + 'ä'.repeat(80); // 8 + 160 Bytes, aber 88 Code Units
		const gefaltet = foldIcs(lang);
		expect(gefaltet).not.toContain('\ufffd'); // kein abgeschnittenes Teilzeichen
		for (const zeile of gefaltet.split('\r\n')) {
			expect(Buffer.byteLength(zeile, 'utf8')).toBeLessThanOrEqual(75);
		}
		expect(unfold(gefaltet)).toBe(lang);
	});

	it('lässt kurze Zeilen unverändert', () => {
		expect(foldIcs('SUMMARY:Kurz')).toBe('SUMMARY:Kurz');
		expect(foldIcs('SUMMARY:' + 'x'.repeat(67))).toBe('SUMMARY:' + 'x'.repeat(67)); // exakt 75
	});

	it('entfaltet LF-basierte CRLF-Faltungen (Toleranz gegenüber Servern)', () => {
		expect(unfold('SUMMARY:Ab\r\n cd')).toBe('SUMMARY:Abcd');
		expect(unfold('SUMMARY:Ab\n cd')).toBe('SUMMARY:Abcd');
	});
});

describe('Zeit-Helfer', () => {
	it('addOneDayToKey über Monats- und Jahresgrenzen inkl. Schaltjahr', () => {
		expect(addOneDayToKey('2025-01-31')).toBe('2025-02-01');
		expect(addOneDayToKey('2025-12-31')).toBe('2026-01-01');
		expect(addOneDayToKey('2024-02-28')).toBe('2024-02-29');
	});

	it('timeFromMs liefert floating Lokalzeit ohne UTC-Flag', () => {
		const t = timeFromMs(localMs(2025, 6, 15, 8, 45));
		// ical.js markiert floating Zeiten über die Zone „floating".
		expect(t.zone?.tzid).toBe('floating');
		expect(t.year).toBe(2025);
		expect(t.month).toBe(6);
		expect(t.day).toBe(15);
		expect(t.hour).toBe(8);
		expect(t.minute).toBe(45);
	});
});
