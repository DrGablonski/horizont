import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { listConnections } from '$server/store/connections';
import { mutateEvent, removeEvent, NotFoundError, ValidationError } from '$server/lib/write';
import { CalDavError } from '$server/caldav/client';
import type { EventUpdateInput } from '$lib/types';

function handleError(e: any) {
	if (e instanceof ValidationError) return json({ error: e.message }, { status: 400 });
	if (e instanceof NotFoundError) return json({ error: e.message }, { status: 404 });
	if (e instanceof CalDavError) return json({ error: e.message }, { status: e.status === 409 ? 409 : 502 });
	return json({ error: e.message ?? 'Unbekannter Fehler' }, { status: 500 });
}

export const PATCH: RequestHandler = async ({ params, request, locals }) => {
	const connections = locals.user ? listConnections(locals.user.id) : [];
	if (connections.length === 0) {
		return json({ error: 'Keine CalDAV-Verbindung konfiguriert.' }, { status: 400 });
	}

	let body: EventUpdateInput;
	try {
		body = await request.json();
	} catch {
		return json({ error: 'Ungültiger JSON-Body.' }, { status: 400 });
	}

	try {
		const item = await mutateEvent(connections, params.calendarId, params.uid, body);
		return json(item);
	} catch (e: any) {
		return handleError(e);
	}
};

export const DELETE: RequestHandler = async ({ params, locals }) => {
	const connections = locals.user ? listConnections(locals.user.id) : [];
	if (connections.length === 0) {
		return json({ error: 'Keine CalDAV-Verbindung konfiguriert.' }, { status: 400 });
	}

	try {
		await removeEvent(connections, params.calendarId, params.uid);
		return json({ ok: true });
	} catch (e: any) {
		return handleError(e);
	}
};
