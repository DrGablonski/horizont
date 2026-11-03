import { json } from '@sveltejs/kit';
import type { RequestHandler } from '@sveltejs/kit';
import { buildArchiveMonthResponse, buildMainResponse } from '$server/lib/panels';
import { listConnections } from '$server/store/connections';
import { createEvent, NotFoundError, ValidationError } from '$server/lib/write';
import { CalDavError } from '$server/caldav/client';
import type { EventCreateInput } from '$lib/types';

export const GET: RequestHandler = async ({ url, locals }) => {
	const connections = locals.user ? listConnections(locals.user.id) : [];
	const scope = url.searchParams.get('scope') ?? 'main';
	if (scope === 'archive') {
		// `monat` = YYYY-MM (optional, ohne/ungültig → neuester Archiv-Monat)
		const month = url.searchParams.get('monat');
		return json(await buildArchiveMonthResponse(connections, month, locals.user?.id));
	}
	return json(await buildMainResponse(connections, locals.user?.id));
};

export const POST: RequestHandler = async ({ request, locals }) => {
	const connections = locals.user ? listConnections(locals.user.id) : [];
	if (connections.length === 0) {
		return json({ error: 'Keine CalDAV-Verbindung konfiguriert.' }, { status: 400 });
	}

	let body: EventCreateInput;
	try {
		body = await request.json();
	} catch {
		return json({ error: 'Ungültiger JSON-Body.' }, { status: 400 });
	}

	try {
		const item = await createEvent(connections, body);
		return json(item, { status: 201 });
	} catch (e: any) {
		if (e instanceof ValidationError) return json({ error: e.message }, { status: 400 });
		if (e instanceof NotFoundError) return json({ error: e.message }, { status: 404 });
		if (e instanceof CalDavError) {
			return json({ error: e.message }, { status: e.status >= 400 && e.status < 500 ? e.status : 502 });
		}
		return json({ error: e.message ?? 'Unbekannter Fehler' }, { status: 500 });
	}
};
