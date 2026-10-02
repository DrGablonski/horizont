// CalDAV-basierte Persistenz für Workflows.
//
// Jeder Workflow = ein VTODO-Objekt in einem internen "workflows"-Kalender.
// Dateiname == Workflow-Id ({id}.ics), daher ist jeder Zugriff ein direkter GET
// ohne UID-Suche. Der vollständige Zustand liegt als X-HORIZONT (base64-JSON)
// innerhalb des Objekts; siehe caldav/workflowIcs.ts für die Codierung.
//
// Diese Module ist rein: es erhält die CalDAV-Settings als Parameter und hat
// keine Abhängigkeit von store.ts (verhindert Zirkelimporte). store.ts löst
// die Settings auf und delegiert hierher.

import { randomUUID } from 'node:crypto';
import type {
	CalDavSettings,
	UpdateStepInput,
	UpdateWorkflowInput,
	Workflow,
	WorkflowStep
} from '$lib/types';
import { WORKFLOWS_CALENDAR } from '$server/lib/constants';
import {
	collectionExists,
	deleteIcs,
	getObjectIcs,
	listCalendarObjects,
	mkCalendar,
	putIcs,
	resolveHome
} from '$server/caldav/client';
import { buildWorkflowIcs, parseWorkflowIcs } from '$server/caldav/workflowIcs';

// ── Ableitung der Kalender-URL ────────────────────────────────────────────

/** URL des internen Workflow-Kalenders (ohne Existenzprüfung). */
async function workflowsBase(settings: CalDavSettings): Promise<string> {
	const { home } = await resolveHome(settings);
	return new URL(`${WORKFLOWS_CALENDAR}/`, home).toString();
}

/**
 * Stellt sicher, dass der interne Kalender existiert (legt ihn sonst per
 * MKCALENDAR an) und liefert seine Basis-URL. Nur im Schreibpfad aufrufen.
 */
async function ensureWorkflowsCalendar(settings: CalDavSettings): Promise<string> {
	const base = await workflowsBase(settings);
	if (!(await collectionExists(settings, base))) {
		await mkCalendar(settings, base, 'Workflows (intern)');
	}
	return base;
}

// ── Abgeleitete Felder (progress, aktiver Schritt, Abschluss) ─────────────

/** Berechnet progress/activeStepId/completedAt/updatedAt und mutiert das Objekt. */
function recompute(wf: Workflow): Workflow {
	const now = Date.now();
	let active: WorkflowStep | null = null;
	for (const s of wf.steps) {
		if (!s.done) {
			active = s;
			break;
		}
	}
	const total = wf.steps.length;
	const done = wf.steps.filter((s) => s.done).length;
	const allDone = total > 0 && done === total;

	wf.activeStepId = active ? active.id : null;
	wf.progress = total === 0 ? 0 : done / total;
	wf.completedAt = allDone ? (wf.completedAt ?? now) : null;
	wf.updatedAt = now;
	return wf;
}

// ── Lese-/Schreibpfade ────────────────────────────────────────────────────

/** Liest einen Workflow aus CalDAV (null, wenn nicht vorhanden/ungültig). */
async function readWorkflow(settings: CalDavSettings, id: string): Promise<Workflow | null> {
	const base = await workflowsBase(settings);
	const ics = await getObjectIcs(settings, `${base}${id}.ics`);
	if (ics == null) return null;
	const wf = parseWorkflowIcs(ics);
	if (wf == null) return null;
	return recompute(wf);
}

/** Schreibt einen Workflow zurück nach CalDAV (recomputet vorher). */
async function persist(settings: CalDavSettings, wf: Workflow): Promise<void> {
	recompute(wf);
	const base = await ensureWorkflowsCalendar(settings);
	const ics = buildWorkflowIcs(wf);
	await putIcs(settings, `${base}${wf.id}.ics`, ics);
}

// ── Öffentliche API (signiert wie der frühere Datei-Store, nun async) ─────

export async function listWorkflows(settings: CalDavSettings): Promise<Workflow[]> {
	const base = await workflowsBase(settings);
	if (!(await collectionExists(settings, base))) return [];

	const objects = await listCalendarObjects(settings, base);
	const results = await Promise.all(
		objects.map(async (o) => {
			const ics = await getObjectIcs(settings, o.url);
			if (ics == null) return null;
			const wf = parseWorkflowIcs(ics);
			if (wf == null) return null;
			return recompute(wf);
		})
	);

	return results
		.filter((w): w is Workflow => w != null)
		.sort((a, b) => b.updatedAt - a.updatedAt);
}

export async function getWorkflow(settings: CalDavSettings, id: string): Promise<Workflow | null> {
	return readWorkflow(settings, id);
}

export async function createWorkflow(
	settings: CalDavSettings,
	input: { title: string; steps: string[] }
): Promise<Workflow> {
	const now = Date.now();
	const title = (input.title ?? '').trim() || 'Neuer Workflow';
	const steps: WorkflowStep[] = (input.steps ?? [])
		.map((s) => (s ?? '').trim())
		.filter((s) => s.length > 0)
		.map((s) => ({ id: randomUUID(), title: s, done: false, completedAt: null }));

	const wf: Workflow = {
		id: randomUUID(),
		title,
		notes: '',
		createdAt: now,
		updatedAt: now,
		completedAt: null,
		activeStepId: null,
		steps,
		progress: 0
	};
	await persist(settings, wf);
	return wf;
}

export async function updateWorkflow(
	settings: CalDavSettings,
	id: string,
	patch: UpdateWorkflowInput
): Promise<Workflow | null> {
	const wf = await readWorkflow(settings, id);
	if (wf == null) return null;
	if (typeof patch.title === 'string' && patch.title.trim()) wf.title = patch.title.trim();
	if (typeof patch.notes === 'string') wf.notes = patch.notes;
	await persist(settings, wf);
	return wf;
}

export async function deleteWorkflow(settings: CalDavSettings, id: string): Promise<boolean> {
	const wf = await readWorkflow(settings, id);
	if (wf == null) return false;
	const base = await ensureWorkflowsCalendar(settings);
	await deleteIcs(settings, `${base}${id}.ics`);
	return true;
}

export async function addStep(settings: CalDavSettings, id: string, title: string): Promise<Workflow | null> {
	const wf = await readWorkflow(settings, id);
	if (wf == null) return null;
	const t = (title ?? '').trim();
	if (t) wf.steps.push({ id: randomUUID(), title: t, done: false, completedAt: null });
	await persist(settings, wf);
	return wf;
}

export async function updateStep(
	settings: CalDavSettings,
	id: string,
	stepId: string,
	patch: UpdateStepInput
): Promise<Workflow | null> {
	const wf = await readWorkflow(settings, id);
	if (wf == null) return null;
	const step = wf.steps.find((s) => s.id === stepId);
	if (step) {
		if (typeof patch.title === 'string' && patch.title.trim()) step.title = patch.title.trim();
		if (typeof patch.done === 'boolean') {
			step.done = patch.done;
			step.completedAt = patch.done ? Date.now() : null;
		}
	}
	await persist(settings, wf);
	return wf;
}

export async function deleteStep(
	settings: CalDavSettings,
	id: string,
	stepId: string
): Promise<Workflow | null> {
	const wf = await readWorkflow(settings, id);
	if (wf == null) return null;
	wf.steps = wf.steps.filter((s) => s.id !== stepId);
	await persist(settings, wf);
	return wf;
}

export async function resetWorkflow(settings: CalDavSettings, id: string): Promise<Workflow | null> {
	const wf = await readWorkflow(settings, id);
	if (wf == null) return null;
	for (const s of wf.steps) {
		s.done = false;
		s.completedAt = null;
	}
	wf.completedAt = null;
	await persist(settings, wf);
	return wf;
}
