// Mappt Serverfehler der Workflow-API in HTTP-Antworten (Status + deutsche Meldung).
//
//   - NotConfiguredError (keine oder keine primäre CalDAV-Verbindung, z. B.
//     nur secondary-Verbindungen vorhanden) → 503
//   - CalDavError → 502 (DAV-Server nicht erreichbar / abgelehnt)
//   - sonst → 500

import { CalDavError } from '$server/caldav/client';

/** Geworfene, wenn der User keine als primär markierte CalDAV-Verbindung hat. */
export class NotConfiguredError extends Error {
	constructor(msg: string) {
		super(msg);
		this.name = 'NotConfiguredError';
	}
}

export function mapError(err: unknown): { status: number; message: string } {
	if (err instanceof NotConfiguredError) {
		return { status: 503, message: err.message };
	}
	if (err instanceof CalDavError) {
		return {
			status: 502,
			message: 'CalDAV-Verbindung fehlgeschlagen. Bitte die Einstellungen prüfen.'
		};
	}
	return { status: 500, message: 'Unerwarteter Fehler beim Zugriff auf Workflows.' };
}
