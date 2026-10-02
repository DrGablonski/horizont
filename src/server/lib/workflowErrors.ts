// Mappt Serverfehler der Workflow-API in HTTP-Antworten (Status + deutsche Meldung).
//
//   - CalDavError  → 502 (DAV-Server nicht erreichbar / abgelehnt)
//   - nicht konfiguriert (requireSettings) → 503
//   - sonst        → 500

import { CalDavError } from '$server/caldav/client';

export function mapError(err: unknown): { status: number; message: string } {
	if (err instanceof CalDavError) {
		return { status: 502, message: 'CalDAV-Verbindung fehlgeschlagen. Bitte die Einstellungen prüfen.' };
	}
	const msg = err instanceof Error ? err.message : String(err);
	if (/nicht konfiguriert/i.test(msg)) {
		return { status: 503, message: msg };
	}
	return { status: 500, message: 'Unerwarteter Fehler beim Zugriff auf Workflows.' };
}
