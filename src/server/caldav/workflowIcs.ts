// Baut und parst die ICS-Objekte für die Workflow-Persistenz.
//
// Ein Workflow wird als VTODO in einem internen "workflows"-Kalender gespeichert:
//   - UID      = Workflow-Id (gleichzeitig Dateiname → direkter GET, keine Suche)
//   - SUMMARY  = Titel (menschlich lesbar in Standard-CalDAV-Clients)
//   - X-HORIZONT = base64(JSON.stringify(workflow))
//
// Der komplette Workflow-Zustand liegt base64-codiert, weil der Radicale/vobject-
// Serialisierer Werte nicht registrierter X-Eigenschaften beim ersten Komma
// abschneidet. Das Base64-Alphabet (A–Z a–z 0–9 + / =) enthält keine Kommata,
// Semikola, Backslashes oder Zeilenumbrüche – der Wert übersteht Folden/Unfolden
// und die Server-Serialisierung exakt (per Round-Trip-Test verifiziert).

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

/** Workflow → RFC-5545-konformer ICS-Text (VCALENDAR mit einem VTODO). */
export function buildWorkflowIcs(wf: Workflow): string {
	const vcal = new Ical.Component(
		Ical.parse('BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Horizont//EN\r\nEND:VCALENDAR') as any
	);
	const vtodo = new Ical.Component(Ical.parse('BEGIN:VTODO\r\nEND:VTODO') as any);
	vtodo.updatePropertyWithValue('uid', wf.id);
	vtodo.updatePropertyWithValue('summary', wf.title);
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
