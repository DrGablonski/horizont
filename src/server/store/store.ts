// Persistenz für Workflows (CalDAV) + Auflösung der Primary-Verbindung pro User.
//
// Workflows: CalDAV (Radicale) – VTODO-Objekte im internen „workflows"-Kalender
// der dem User zugewiesenen Verbindung. Die eigentliche CalDAV-Logik liegt in
// store/workflowStore.ts; hier wird die Verbindung des Users aufgelöst.
//
// CalDAV-Verbindungen selbst: siehe store/connections.ts (per User).

import * as wstore from '$server/store/workflowStore';
import { getAssigned, toSettings } from '$server/store/connections';
import { NotConfiguredError } from '$server/lib/workflowErrors';
import type { CalDavSettings, UpdateStepInput, UpdateWorkflowInput, Workflow } from '$lib/types';

/** Liefert die dem User zugewiesene Verbindung (primary) oder wirft (→ 503). */
export function requirePrimary(userId: string): CalDavSettings {
	const assigned = getAssigned(userId);
	if (!assigned) {
		throw new NotConfiguredError(
			'Keine zugewiesene CalDAV-Verbindung vorhanden. Bitte beim Administrator melden, dass eine Verbindung zugeordnet wird.'
		);
	}
	return toSettings(assigned);
}

// ── Workflows (delegiert an CalDAV; asynchron) ────────────────────────────

export async function listWorkflows(userId: string): Promise<Workflow[]> {
	return wstore.listWorkflows(requirePrimary(userId));
}

export async function getWorkflow(userId: string, id: string): Promise<Workflow | null> {
	return wstore.getWorkflow(requirePrimary(userId), id);
}

export async function createWorkflow(userId: string, input: { title: string; steps: string[] }): Promise<Workflow> {
	return wstore.createWorkflow(requirePrimary(userId), input);
}

export async function updateWorkflow(userId: string, id: string, patch: UpdateWorkflowInput): Promise<Workflow | null> {
	return wstore.updateWorkflow(requirePrimary(userId), id, patch);
}

export async function deleteWorkflow(userId: string, id: string): Promise<boolean> {
	return wstore.deleteWorkflow(requirePrimary(userId), id);
}

export async function addStep(userId: string, id: string, title: string): Promise<Workflow | null> {
	return wstore.addStep(requirePrimary(userId), id, title);
}

export async function updateStep(
	userId: string,
	id: string,
	stepId: string,
	patch: UpdateStepInput
): Promise<Workflow | null> {
	return wstore.updateStep(requirePrimary(userId), id, stepId, patch);
}

export async function deleteStep(userId: string, id: string, stepId: string): Promise<Workflow | null> {
	return wstore.deleteStep(requirePrimary(userId), id, stepId);
}

export async function resetWorkflow(userId: string, id: string): Promise<Workflow | null> {
	return wstore.resetWorkflow(requirePrimary(userId), id);
}
