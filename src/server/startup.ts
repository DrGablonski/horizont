// Einmalige Start-Nebeneffekte des Servers.
//
// Lag früher als Modul-Seiteneffekte in hooks.server.ts — hierhin ausgelagert,
// damit klar ist, was beim Server-Start passiert. `initStartup()` ist
// idempotent und wird von hooks.server.ts beim Modul-Laden aufgerufen
// (gleichzeitiges Verhalten wie zuvor).

import { removeLegacyAgentFiles } from '$server/lib/legacyCleanup';
import { startNotifyJob } from '$server/jobs/notify';

let initialized = false;

/** Führt die Start-Effekte genau einmal aus (wiederholte Aufrufe sind no-op). */
export function initStartup(): void {
	if (initialized) return;
	initialized = true;

	// Beim Start: verwaiste Agent-Config-Dateien entfernen (Funktion entfernt).
	removeLegacyAgentFiles();

	// Täglicher Benachrichtigungs-Job (offene Schul-Tasks per Webhook).
	startNotifyJob();
}
