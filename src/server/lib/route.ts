// Gemeinsamer Wrapper für alle /api/*-Handler: Auth-Absicherung + eine
// zentrale Fehlerabbildung (statt kopierter handleError-Ketten pro Route).
//
// hooks.server.ts 401t /api/* ohne Session bereits ab — die 401-Absicherung
// hier ist daher faktisch unerreichbar, hält aber das bisherige Antwortbild
// ({ error: 'Nicht angemeldet.' }, 401) und erlaubt Handlern, von einem
// nicht-leeren `locals.user` auszugehen.

import { json } from '@sveltejs/kit';
import type { RequestEvent, RequestHandler } from '@sveltejs/kit';
import { CalDavError } from '$server/caldav/client';
import { NotFoundError, ReadOnlyError, ValidationError } from '$server/lib/write';
import { NotConfiguredError, mapError as mapStoreError } from '$server/lib/workflowErrors';

/** RequestEvent mit garantiert gesetztem `locals.user` (vom Wrapper sichergestellt). */
export type AuthedEvent<E extends RequestEvent = RequestEvent> = Omit<E, 'locals'> & {
	locals: Omit<RequestEvent['locals'], 'user'> & {
		user: NonNullable<RequestEvent['locals']['user']>;
	};
};

/** Bildt einen geworfenen Fehler in eine JSON-Antwort ab. */
export type ErrorHandler = (e: unknown) => Response;

/**
 * Zentrale Fehlerabbildung aller API-Routen (einheitliche Status-Semantik):
 *
 *   - ValidationError → 400, NotFoundError → 404, ReadOnlyError → 403
 *   - NotConfiguredError (keine primäre CalDAV-Verbindung) → 503
 *   - CalDavError → 4xx-Antworten des Servers unverändert durchreichen
 *     (z. B. 409 bei ETag-Konflikt), alles andere → 502
 *   - sonstiger Error → 400 mit seiner (deutschen) Meldung
 *   - unbekannt → 500 'Unbekannter Fehler'
 */
export function mapError(e: unknown): Response {
	if (e instanceof ValidationError) return json({ error: e.message }, { status: 400 });
	if (e instanceof NotFoundError) return json({ error: e.message }, { status: 404 });
	if (e instanceof ReadOnlyError) return json({ error: e.message }, { status: 403 });
	if (e instanceof NotConfiguredError) return json({ error: e.message }, { status: 503 });
	if (e instanceof CalDavError) {
		const status = e.status >= 400 && e.status < 500 ? e.status : 502;
		return json({ error: e.message }, { status });
	}
	if (e instanceof Error) return json({ error: e.message }, { status: 400 });
	return json({ error: 'Unbekannter Fehler' }, { status: 500 });
}

/**
 * Fehlerabbilder der Workflow-Routen: behalten deren eigene Semantik
 * (503/502/500 mit teils fixen Meldungen, siehe $server/lib/workflowErrors)
 * und weichen bewusst von der allgemeinen Zuordnung oben ab.
 */
export function mapWorkflowError(e: unknown): Response {
	const { status, message } = mapStoreError(e);
	return json({ error: message }, { status });
}

/**
 * Umschließt einen Handler: 401-Absicherung (Message/Status wie bisher) und
 * try/catch mit Fehlerabbildung über `onError` (Standard: mapError).
 * Der Handler sieht ein nicht-leeres `locals.user` und kann weiterhin
 * eigene Antworten zurückgeben, z. B. `json({ error: ... }, { status: 400 })`.
 */
export function withUser<E extends RequestEvent = RequestEvent>(
	handler: (event: AuthedEvent<E>) => Response | Promise<Response>,
	onError: ErrorHandler = mapError
): RequestHandler {
	return async (event) => {
		if (!event.locals.user) {
			return json({ error: 'Nicht angemeldet.' }, { status: 401 });
		}
		try {
			return await handler(event as unknown as AuthedEvent<E>);
		} catch (e) {
			return onError(e);
		}
	};
}
