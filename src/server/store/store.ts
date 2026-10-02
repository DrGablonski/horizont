// Persistenz für Workflows und CalDAV-Einstellungen.
//
// Einstellungen: JSON-Datei im Datenverzeichnis (atomares Schreiben: tmp + rename).
// Workflows: CalDAV (Radicale) – VTODO-Objekte in einem internen Kalender.
// Die eigentliche CalDAV-Logik liegt in store/workflowStore.ts; hier werden die
// Settings aufgelöst und die (nun asynchronen) Funktionen delegiert.

import { mkdirSync, readFileSync, writeFileSync, renameSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { DATA_DIR } from '$server/lib/constants';
import * as wstore from '$server/store/workflowStore';
import type {
	CalDavSettings,
	CalDavSettingsView,
	UpdateStepInput,
	UpdateWorkflowInput,
	Workflow
} from '$lib/types';

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

// ── Einstellungen (dateibasiert) ──────────────────────────────────────────

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

/** Liefert die gespeicherten Settings oder wirft (→ 503 in den Routen). */
function requireSettings(): CalDavSettings {
	const s = getSettings();
	if (!s) {
		throw new Error(
			'CalDAV ist nicht konfiguriert. Bitte zuerst in den Einstellungen eine Verknüpfung hinterlegen.'
		);
	}
	return s;
}

// ── Workflows (delegiert an CalDAV; nun asynchron) ───────────────────────

export async function listWorkflows(): Promise<Workflow[]> {
	return wstore.listWorkflows(requireSettings());
}

export async function getWorkflow(id: string): Promise<Workflow | null> {
	return wstore.getWorkflow(requireSettings(), id);
}

export async function createWorkflow(input: { title: string; steps: string[] }): Promise<Workflow> {
	return wstore.createWorkflow(requireSettings(), input);
}

export async function updateWorkflow(id: string, patch: UpdateWorkflowInput): Promise<Workflow | null> {
	return wstore.updateWorkflow(requireSettings(), id, patch);
}

export async function deleteWorkflow(id: string): Promise<boolean> {
	return wstore.deleteWorkflow(requireSettings(), id);
}

export async function addStep(id: string, title: string): Promise<Workflow | null> {
	return wstore.addStep(requireSettings(), id, title);
}

export async function updateStep(
	id: string,
	stepId: string,
	patch: UpdateStepInput
): Promise<Workflow | null> {
	return wstore.updateStep(requireSettings(), id, stepId, patch);
}

export async function deleteStep(id: string, stepId: string): Promise<Workflow | null> {
	return wstore.deleteStep(requireSettings(), id, stepId);
}

export async function resetWorkflow(id: string): Promise<Workflow | null> {
	return wstore.resetWorkflow(requireSettings(), id);
}
