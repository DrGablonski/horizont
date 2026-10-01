// Persistenz für Workflows und CalDAV-Einstellungen.
// JSON-Dateien im Datenverzeichnis, atomares Schreiben (tmp + rename).

import { mkdirSync, readFileSync, writeFileSync, renameSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { randomUUID } from 'node:crypto';
import { DATA_DIR } from '$server/lib/constants';
import type {
	CalDavSettings,
	CalDavSettingsView,
	UpdateStepInput,
	UpdateWorkflowInput,
	Workflow,
	WorkflowStep
} from '$lib/types';

const WORKFLOWS_FILE = 'workflows.json';
const SETTINGS_FILE = 'settings.json';

function dataPath(file: string): string {
	mkdirSync(DATA_DIR, { recursive: true });
	return join(DATA_DIR, file);
}

function readJson<T>(file: string, fallback: T): T {
	const p = dataPath(file);
	if (!existsSync(p)) return fallback;
	try {
		return JSON.parse(readFileSync(p, 'utf8')) as T;
	} catch {
		return fallback;
	}
}

function writeJsonAtomic(file: string, data: unknown): void {
	const p = dataPath(file);
	const tmp = `${p}.tmp`;
	writeFileSync(tmp, JSON.stringify(data, null, 2), 'utf8');
	renameSync(tmp, p);
}

// ── Workflows ─────────────────────────────────────────────────────────────

interface WorkflowStore {
	workflows: Workflow[];
}

function load(): WorkflowStore {
	return readJson<WorkflowStore>(WORKFLOWS_FILE, { workflows: [] });
}

function save(store: WorkflowStore): void {
	writeJsonAtomic(WORKFLOWS_FILE, store);
}

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

function find(store: WorkflowStore, id: string): Workflow | undefined {
	return store.workflows.find((w) => w.id === id);
}

export function listWorkflows(): Workflow[] {
	const store = load();
	return [...store.workflows]
		.map((w) => recompute({ ...w, steps: w.steps.map((s) => ({ ...s })) }))
		.sort((a, b) => b.updatedAt - a.updatedAt);
}

export function getWorkflow(id: string): Workflow | null {
	const store = load();
	const wf = find(store, id);
	return wf ? recompute(JSON.parse(JSON.stringify(wf))) : null;
}

export function createWorkflow(input: { title: string; steps: string[] }): Workflow {
	const store = load();
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
	recompute(wf);
	store.workflows.push(wf);
	save(store);
	return wf;
}

export function updateWorkflow(id: string, patch: UpdateWorkflowInput): Workflow | null {
	const store = load();
	const wf = find(store, id);
	if (!wf) return null;
	if (typeof patch.title === 'string' && patch.title.trim()) wf.title = patch.title.trim();
	if (typeof patch.notes === 'string') wf.notes = patch.notes;
	recompute(wf);
	save(store);
	return wf;
}

export function deleteWorkflow(id: string): boolean {
	const store = load();
	const idx = store.workflows.findIndex((w) => w.id === id);
	if (idx === -1) return false;
	store.workflows.splice(idx, 1);
	save(store);
	return true;
}

export function addStep(id: string, title: string): Workflow | null {
	const store = load();
	const wf = find(store, id);
	if (!wf) return null;
	const t = (title ?? '').trim();
	if (!t) return wf;
	wf.steps.push({ id: randomUUID(), title: t, done: false, completedAt: null });
	recompute(wf);
	save(store);
	return wf;
}

export function updateStep(id: string, stepId: string, patch: UpdateStepInput): Workflow | null {
	const store = load();
	const wf = find(store, id);
	if (!wf) return null;
	const step = wf.steps.find((s) => s.id === stepId);
	if (!step) return wf;
	if (typeof patch.title === 'string' && patch.title.trim()) step.title = patch.title.trim();
	if (typeof patch.done === 'boolean') {
		step.done = patch.done;
		step.completedAt = patch.done ? Date.now() : null;
	}
	recompute(wf);
	save(store);
	return wf;
}

export function deleteStep(id: string, stepId: string): Workflow | null {
	const store = load();
	const wf = find(store, id);
	if (!wf) return null;
	wf.steps = wf.steps.filter((s) => s.id !== stepId);
	recompute(wf);
	save(store);
	return wf;
}

export function resetWorkflow(id: string): Workflow | null {
	const store = load();
	const wf = find(store, id);
	if (!wf) return null;
	for (const s of wf.steps) {
		s.done = false;
		s.completedAt = null;
	}
	wf.completedAt = null;
	recompute(wf);
	save(store);
	return wf;
}

// ── Einstellungen ─────────────────────────────────────────────────────────

export function getSettings(): CalDavSettings | null {
	const s = readJson<CalDavSettings | null>(SETTINGS_FILE, null);
	if (!s || !s.url) return null;
	return s;
}

export function saveSettings(s: CalDavSettings): void {
	writeJsonAtomic(SETTINGS_FILE, s);
}

export function getSettingsView(): CalDavSettingsView {
	const s = getSettings();
	if (!s) {
		return { configured: false, url: '', username: '', hasPassword: false };
	}
	return {
		configured: true,
		url: s.url,
		username: s.username.trim(),
		hasPassword: Boolean(s.password)
	};
}
