// Persistenz für Workflows (CalDAV) + Auflösung der Primary-Verbindung des Users.
//
// Workflows: CalDAV (Radicale) – VTODO-Objekte im internen „workflows"-Kalender
// der Hauptverbindung (role === 'primary') des Users. Die eigentliche CalDAV-
// Logik liegt in store/workflowStore.ts; hier wird die Verbindung aufgelöst.
//
// Wichtig: Workflows liegen bewusst NIE in sekundären Verbindungen — auch wenn
// dort Kalender beschreibbar sind. Der interne Workflow-Kalender wird aus-
// schließlich in der primary-Verbindung angelegt und gesucht; requirePrimary
// erzwingt das, secondary-Verbindungen sind als Workflow-Speicher tabu.
//
// CalDAV-Verbindungen selbst: siehe store/connections.ts.

import * as wstore from '$server/store/workflowStore';
import { getPrimaryConnection, toSettings } from '$server/store/connections';
import { NotConfiguredError } from '$server/lib/workflowErrors';
import type { CalDavSettings, UpdateStepInput, UpdateWorkflowInput, Workflow } from '$lib/types';

/**
 * Liefert die Settings der Hauptverbindung (role === 'primary') oder wirft
 * NotConfiguredError (→ 503). Darf niemals eine secondary-Verbindung liefern:
 * getPrimaryConnection gibt die primaryId-Verbindung zurück, sonst (Alt-
 * Installationen) die erste Verbindung; fehlt die Hauptverbindung und sind nur
 * secondary-Verbindungen vorhanden, wird hier explizit abgelehnt.
 */
export function requirePrimary(userId: string): CalDavSettings {
	const primary = getPrimaryConnection(userId);
	if (!primary) {
		throw new NotConfiguredError(
			'Keine CalDAV-Verbindung vorhanden. Bitte verbinde zuerst in den Einstellungen einen Kalender.'
		);
	}
	// Explizite Sperre: secondary-Verbindungen sind nie Workflow-Ziel. Verbindungen
	// ohne role-Feld (Altinstallationen vor dem Rollen-Update) bleiben zulässig —
	// für Installationen mit genau einer Verbindung ändert sich nichts.
	if (primary.role === 'secondary') {
		throw new NotConfiguredError(
			'Keine Hauptverbindung gefunden. Lege in den Einstellungen eine Verbindung als Hauptverbindung fest – Workflows liegen immer in deren internem Kalender.'
		);
	}
	return toSettings(primary);
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
