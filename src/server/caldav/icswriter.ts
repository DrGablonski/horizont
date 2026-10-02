// Baut und aktualisiert ICS-Blöcke (VEVENT / VTODO) über ical.js.
// Alle Zeiten werden als floating local (ohne Z / TZID) geschrieben, da der
// Server dieselbe Zeitzone wie der Benutzer nutzt (Europe/Berlin im Container).

import Ical from 'ical.js';

// ── Fold / Unfold (RFC 5545 §3.1) ─────────────────────────────────────────

/** Faltet umgebruchszeilen zurück zu kompletten Zeilen. */
export function unfold(ics: string): string {
	return ics.replace(/\r\n[ \t]/g, '').replace(/\n[ \t]/g, '');
}

function foldLine(line: string): string {
	const buf = Buffer.from(line, 'utf8');
	if (buf.length <= 75) return line;

	const out: string[] = [];
	let remaining = line;
	let first = true;

	while (remaining.length > 0) {
		const maxBytes = first ? 75 : 74;
		let cut = 0;
		let bytes = 0;
		for (const ch of remaining) {
			const chBytes = Buffer.byteLength(ch, 'utf8');
			if (bytes + chBytes > maxBytes) break;
			bytes += chBytes;
			cut += ch.length;
		}
		if (cut === 0) cut = 1;
		const segment = remaining.slice(0, cut);
		remaining = remaining.slice(cut);
		out.push(first ? segment : ' ' + segment);
		first = false;
	}

	return out.join('\r\n');
}

/** Faltet einen ICS-Text an 75 Oktet (RFC-konform, byte-aware). */
export function foldIcs(raw: string): string {
	return raw
		.split('\r\n')
		.map(foldLine)
		.join('\r\n');
}

/** Serialisiert einen ical.js Component zu RFC-konformem ICS-Text. */
export function serialize(comp: any): string {
	const raw = comp.toString();
	return foldIcs(unfold(raw));
}

// ── Zeit-Helfer ───────────────────────────────────────────────────────────

/** Epoch ms → ical.js floating local Time (keine Z, kein TZID). */
export function timeFromMs(ms: number): any {
	return Ical.Time.fromJSDate(new Date(ms));
}

/** YYYY-MM-DD → ical.js all-day Date (isDate=true, VALUE=DATE). */
export function dateFromKey(key: string): any {
	const [y, m, d] = key.split('-').map(Number);
	return new (Ical.Time as any)({ year: y, month: m, day: d });
}

/** YYYY-MM-DD → nächster Tag (für exclusive DTEND). */
export function addOneDayToKey(key: string): string {
	const [y, m, d] = key.split('-').map(Number);
	const dt = new Date(y, m - 1, d + 1);
	const yy = dt.getFullYear();
	const mm = String(dt.getMonth() + 1).padStart(2, '0');
	const dd = String(dt.getDate()).padStart(2, '0');
	return `${yy}-${mm}-${dd}`;
}

// ── Skeleton-Generatoren ──────────────────────────────────────────────────

function makeVCalendar(): any {
	const j = Ical.parse('BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Horizont//EN\r\nEND:VCALENDAR') as any;
	return new Ical.Component(j);
}

function makeVEVENT(): any {
	const j = Ical.parse('BEGIN:VEVENT\r\nEND:VEVENT') as any;
	return new Ical.Component(j);
}

function makeVTODO(): any {
	const j = Ical.parse('BEGIN:VTODO\r\nEND:VTODO') as any;
	return new Ical.Component(j);
}

// ── Property-Helfer ───────────────────────────────────────────────────────

function setOptionalText(comp: any, name: string, value: string | undefined): void {
	if (value != null && value.trim().length > 0) {
		comp.updatePropertyWithValue(name, value);
	} else if (comp.hasProperty(name)) {
		comp.removeProperty(name);
	}
}

// ── Event-Felder anwenden ─────────────────────────────────────────────────

interface EventFields {
	summary: string;
	location?: string;
	description?: string;
	allDay: boolean;
	dayKey?: string;
	endDateKey?: string;
	startMs?: number;
	endMs?: number;
}

function applyEventFields(comp: any, input: EventFields): void {
	comp.updatePropertyWithValue('summary', input.summary);
	setOptionalText(comp, 'location', input.location);
	setOptionalText(comp, 'description', input.description);

	if (input.allDay) {
		if (input.dayKey) {
			comp.updatePropertyWithValue('dtstart', dateFromKey(input.dayKey));
		}
		const endKey = input.endDateKey || input.dayKey;
		if (endKey) {
			comp.updatePropertyWithValue('dtend', dateFromKey(addOneDayToKey(endKey)));
		}
	} else {
		if (input.startMs != null) {
			comp.updatePropertyWithValue('dtstart', timeFromMs(input.startMs));
		}
		if (input.endMs != null) {
			comp.updatePropertyWithValue('dtend', timeFromMs(input.endMs));
		}
	}
}

// ── Event: neu erstellen ──────────────────────────────────────────────────

export function buildEventIcs(uid: string, input: EventFields): { uid: string; ics: string } {
	const vcal = makeVCalendar();
	const vevent = makeVEVENT();
	vevent.updatePropertyWithValue('uid', uid);
	applyEventFields(vevent, input);
	vcal.addSubcomponent(vevent);
	return { uid, ics: serialize(vcal) };
}

// ── Event: bestehendes aktualisieren ──────────────────────────────────────

export function updateEventIcs(existingIcs: string, uid: string, input: EventFields): { uid: string; ics: string } {
	const j = Ical.parse(unfold(existingIcs)) as any;
	const vcal = new Ical.Component(j);

	const vevents: any[] = vcal.getAllSubcomponents('vevent') ?? [];
	let vevent: any = null;
	for (const v of vevents) {
		if (v.getFirstPropertyValue?.('uid') === uid) {
			vevent = v;
			break;
		}
	}

	if (!vevent) {
		vevent = makeVEVENT();
		vevent.updatePropertyWithValue('uid', uid);
		vcal.addSubcomponent(vevent);
	}

	applyEventFields(vevent, input);
	return { uid, ics: serialize(vcal) };
}

// ── Task-Felder anwenden (voll, für Create) ──────────────────────────────

interface TaskFields {
	summary: string;
	description?: string;
	completed?: boolean;
	due?: { kind: 'none' } | { kind: 'date'; key: string } | { kind: 'time'; ms: number };
	priority?: number | null;
}

function applyTaskFields(comp: any, input: TaskFields): void {
	comp.updatePropertyWithValue('summary', input.summary);
	setOptionalText(comp, 'description', input.description);

	if (input.completed) {
		comp.updatePropertyWithValue('completed', Ical.Time.now());
	} else if (comp.hasProperty('completed')) {
		comp.removeProperty('completed');
	}

	if (input.due != null) {
		if (input.due.kind === 'none') {
			if (comp.hasProperty('due')) comp.removeProperty('due');
		} else if (input.due.kind === 'date') {
			comp.updatePropertyWithValue('due', dateFromKey(input.due.key));
		} else if (input.due.kind === 'time') {
			comp.updatePropertyWithValue('due', timeFromMs(input.due.ms));
		}
	}

	if (input.priority != null && input.priority !== null && input.priority !== undefined) {
		comp.updatePropertyWithValue('priority', input.priority);
	} else if (comp.hasProperty('priority')) {
		comp.removeProperty('priority');
	}
}

// ── Task: neu erstellen ───────────────────────────────────────────────────

export function buildTaskIcs(uid: string, input: TaskFields): { uid: string; ics: string } {
	const vcal = makeVCalendar();
	const vtodo = makeVTODO();
	vtodo.updatePropertyWithValue('uid', uid);
	applyTaskFields(vtodo, input);
	vcal.addSubcomponent(vtodo);
	return { uid, ics: serialize(vcal) };
}

// ── Task: bestehendes aktualisieren (partial) ─────────────────────────────

interface TaskPatch {
	summary?: string;
	description?: string;
	completed?: boolean;
	due?: { kind: 'none' } | { kind: 'date'; key: string } | { kind: 'time'; ms: number };
	priority?: number | null;
}

export function updateTaskIcs(existingIcs: string, uid: string, patch: TaskPatch): { uid: string; ics: string } {
	const j = Ical.parse(unfold(existingIcs)) as any;
	const vcal = new Ical.Component(j);

	const vtodos: any[] = vcal.getAllSubcomponents('vtodo') ?? [];
	let vtodo: any = null;
	for (const v of vtodos) {
		if (v.getFirstPropertyValue?.('uid') === uid) {
			vtodo = v;
			break;
		}
	}

	if (!vtodo) {
		vtodo = makeVTODO();
		vtodo.updatePropertyWithValue('uid', uid);
		vcal.addSubcomponent(vtodo);
	}

	if (patch.summary != null) vtodo.updatePropertyWithValue('summary', patch.summary);
	if (patch.description !== undefined) setOptionalText(vtodo, 'description', patch.description);

	if (patch.completed != null) {
		if (patch.completed) {
			vtodo.updatePropertyWithValue('completed', Ical.Time.now());
		} else if (vtodo.hasProperty('completed')) {
			vtodo.removeProperty('completed');
		}
	}

	if (patch.due != null) {
		if (patch.due.kind === 'none') {
			if (vtodo.hasProperty('due')) vtodo.removeProperty('due');
		} else if (patch.due.kind === 'date') {
			vtodo.updatePropertyWithValue('due', dateFromKey(patch.due.key));
		} else if (patch.due.kind === 'time') {
			vtodo.updatePropertyWithValue('due', timeFromMs(patch.due.ms));
		}
	}

	if (patch.priority !== undefined) {
		if (patch.priority === null) {
			if (vtodo.hasProperty('priority')) vtodo.removeProperty('priority');
		} else {
			vtodo.updatePropertyWithValue('priority', patch.priority);
		}
	}

	return { uid, ics: serialize(vcal) };
}
