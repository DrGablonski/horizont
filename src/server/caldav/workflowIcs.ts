// Baut und parst die ICS-Objekte für die Workflow-Persistenz.
//
// Ein Workflow wird als VTODO in einem internen "workflows"-Kalender gespeichert.
// Das Objekt ist ein RFC-5545-konformes, in Standard-CalDAV-Clients (z. B.
// Thunderbird/Lightning) sauber lesbares Task-Objekt:
//
//   - UID             = Workflow-Id (gleichzeitig Dateiname → direkter GET, keine Suche)
//   - DTSTAMP        = Erstellungszeitpunkt (RFC 5545 §3.6.2: REQUIRED)
//   - LAST-MODIFIED  = letzte Änderung
//   - SUMMARY        = "Workflow: <Titel>" (menschlich lesbar, erkennbar als Workflow)
//   - STATUS         = NEEDS-ACTION / IN-PROCESS / COMPLETED (RFC 5545 §3.3.5)
//   - PERCENT-COMPLETE = Fortschritt 0–100
//   - COMPLETED      = Abschlusszeitpunkt (nur wenn alle Schritte erledigt)
//   - CATEGORIES     = "HORIZONT" (Filter/Markierung in Clients)
//   - DESCRIPTION    = menschenlesbare Schritteliste + Notizen (escaping übernimmt ical.js)
//   - X-HORIZONT     = base64(JSON.stringify(workflow)) – die Maschinendaten (Single Source of Truth)
//
// Der komplette Workflow-Zustand liegt base64-codiert, weil der Radicale/vobject-
// Serialisierer Werte nicht registrierter X-Eigenschaften beim ersten Komma
// abschneidet. Das Base64-Alphabet (A–Z a–z 0–9 + / =) enthält keine Kommata,
// Semikola, Backslashes oder Zeilenumbrüche – der Wert übersteht Folden/Unfolden
// und die Server-Serialisierung exakt (per Round-Trip-Test verifiziert).
//
// DTSTAMP und LAST-MODIFIED sind aus createdAt/updatedAt abgeleitet (nicht
// "now"), damit ein und derselbe Workflow-Zustand immer byte-identisches ICS
// erzeugt – unnötige Server-Last und fluktuierende ETags entfallen.

import Ical from 'ical.js';
import { serialize, unfold } from '$server/caldav/icswriter';
import type { Workflow, WorkflowStep } from '$lib/types';

const X_PROP = 'x-horizont';

// ── Codierung / Dekodierung des Payloads ──────────────────────────────────

/** Workflow → base64(JSON). */
export function encodeWorkflow(wf: Workflow): string {
	return Buffer.from(JSON.stringify(wf), 'utf8').toString('base64');
}

/** base64(JSON) → validiertes Workflow-Objekt (oder null). */
export function decodeWorkflow(b64: string): Workflow | null {
	let json: string;
	try {
		json = Buffer.from(b64, 'base64').toString('utf8');
	} catch {
		return null;
	}
	let obj: unknown;
	try {
		obj = JSON.parse(json);
	} catch {
		return null;
	}
	return validateWorkflow(obj);
}

/** Definiert die Pflichtfelder und normalisiert optionale Felder. */
function validateWorkflow(obj: unknown): Workflow | null {
	if (typeof obj !== 'object' || obj === null) return null;
	const o = obj as Record<string, any>;
	if (typeof o.id !== 'string' || o.id.length === 0) return null;
	if (typeof o.title !== 'string') return null;
	if (!Array.isArray(o.steps)) return null;

	const steps: WorkflowStep[] = [];
	for (const raw of o.steps) {
		if (typeof raw !== 'object' || raw === null) return null;
		const s = raw as Record<string, any>;
		if (typeof s.id !== 'string' || typeof s.title !== 'string') return null;
		steps.push({
			id: s.id,
			title: s.title,
			done: Boolean(s.done),
			completedAt: typeof s.completedAt === 'number' ? s.completedAt : null
		});
	}

	return {
		id: o.id,
		title: o.title,
		notes: typeof o.notes === 'string' ? o.notes : '',
		createdAt: typeof o.createdAt === 'number' ? o.createdAt : 0,
		updatedAt: typeof o.updatedAt === 'number' ? o.updatedAt : 0,
		completedAt: typeof o.completedAt === 'number' ? o.completedAt : null,
		activeStepId: typeof o.activeStepId === 'string' ? o.activeStepId : null,
		steps,
		progress: typeof o.progress === 'number' ? o.progress : 0
	};
}

// ── ICS bauen / parsen ────────────────────────────────────────────────────

/** RFC-5545-Zeitstempel (UTC) aus einer Unix-Millisekunden-Marke. */
function utcTime(ms: number): Ical.Time {
	return Ical.Time.fromJSDate(new Date(ms), true);
}

/** STATUS gemäß RFC 5545 §3.3.5 aus dem Workflow-Zustand abgeleitet. */
function workflowStatus(wf: Workflow): string {
	if (wf.completedAt != null || wf.progress >= 1) return 'COMPLETED';
	if (wf.progress > 0) return 'IN-PROCESS';
	return 'NEEDS-ACTION';
}

/** "01.10. 14:32" – deterministisch, ohne Locale-Abhängigkeit. */
function fmtClock(ms: number): string {
	const d = new Date(ms);
	const p = (n: number) => String(n).padStart(2, '0');
	return `${p(d.getDate())}.${p(d.getMonth() + 1)} ${p(d.getHours())}:${p(d.getMinutes())}`;
}

/**
 * Menschenlesbare Schritt-Übersicht für die DESCRIPTION (raw text mit echten
 * Zeilenumbrüchen – das RFC-5545-Escaping von \, ; \ und Newlines übernimmt
 * ical.js beim Serialisieren).
 */
function buildHumanDescription(wf: Workflow): string {
	const lines: string[] = [`Workflow: ${wf.title}`];
	const total = wf.steps.length;
	const done = wf.steps.filter((s) => s.done).length;
	lines.push(total === 0 ? 'Keine Schritte.' : `${done}/${total} Schritte erledigt`);
	if (total > 0) {
		lines.push('');
		for (const s of wf.steps) {
			let line = `[${s.done ? 'x' : ' '}] ${s.title}`;
			if (s.done && s.completedAt != null) line += ` (${fmtClock(s.completedAt)})`;
			if (!s.done && s.id === wf.activeStepId) line += '  <== aktuell';
			lines.push(line);
		}
	}
	if (wf.notes.trim()) {
		lines.push('', 'Notizen:', wf.notes.trim());
	}
	return lines.join('\n');
}

/** Workflow → RFC-5545-konformer ICS-Text (VCALENDAR mit einem VTODO). */
export function buildWorkflowIcs(wf: Workflow): string {
	const vcal = new Ical.Component(
		Ical.parse('BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Horizont//EN\r\nEND:VCALENDAR') as any
	);
	const vtodo = new Ical.Component(Ical.parse('BEGIN:VTODO\r\nEND:VTODO') as any);
	vtodo.updatePropertyWithValue('uid', wf.id);
	vtodo.updatePropertyWithValue('dtstamp', utcTime(wf.createdAt));
	vtodo.updatePropertyWithValue('last-modified', utcTime(wf.updatedAt));
	vtodo.updatePropertyWithValue('summary', `Workflow: ${wf.title}`);
	vtodo.updatePropertyWithValue('status', workflowStatus(wf));
	vtodo.updatePropertyWithValue('percent-complete', Math.round(wf.progress * 100));
	vtodo.updatePropertyWithValue('categories', 'HORIZONT');
	if (wf.completedAt != null) vtodo.updatePropertyWithValue('completed', utcTime(wf.completedAt));
	vtodo.updatePropertyWithValue('description', buildHumanDescription(wf));
	vtodo.updatePropertyWithValue(X_PROP, encodeWorkflow(wf));
	vcal.addSubcomponent(vtodo);
	return serialize(vcal);
}

/** ICS-Text → Workflow (oder null, wenn kein gültiges Workflow-Objekt enthalten). */
export function parseWorkflowIcs(ics: string): Workflow | null {
	let comp: any;
	try {
		comp = new Ical.Component(Ical.parse(unfold(ics)) as any);
	} catch {
		return null;
	}
	const vtodos: any[] = comp.getAllSubcomponents('vtodo') ?? [];
	for (const v of vtodos) {
		const b64 = v.getFirstPropertyValue?.(X_PROP);
		if (typeof b64 !== 'string' || b64.length === 0) continue;
		const wf = decodeWorkflow(b64);
		if (wf) return wf;
	}
	return null;
}
