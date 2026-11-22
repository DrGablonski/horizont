import { json } from '@sveltejs/kit';
import { readJsonBody } from '$server/auth/apiHelpers';
import { withUser } from '$server/lib/route';
import { buildArchiveMonthResponse, buildMainResponse } from '$server/lib/panels';
import { listConnections } from '$server/store/connections';
import { createEvent } from '$server/lib/write';
import type { EventCreateInput } from '$lib/types';

export const GET = withUser(async ({ url, locals }) => {
	const userId = locals.user.id;
	const connections = listConnections(userId);
	const scope = url.searchParams.get('scope') ?? 'main';
	if (scope === 'archive') {
		// `monat` = YYYY-MM (optional, ohne/ungültig → neuester Archiv-Monat)
		const month = url.searchParams.get('monat');
		return json(await buildArchiveMonthResponse(userId, connections, month));
	}
	return json(await buildMainResponse(userId, connections));
});

export const POST = withUser(async ({ request, locals }) => {
	const connections = listConnections(locals.user.id);
	if (connections.length === 0) {
		return json({ error: 'Keine CalDAV-Verbindung konfiguriert.' }, { status: 400 });
	}

	const body = await readJsonBody<EventCreateInput>(request);
	if (!body) return json({ error: 'Ungültiger JSON-Body.' }, { status: 400 });

	// calendarId optional: fehlt ⇒ Server wählt den Standardkalender (resolveWriteTarget).
	const item = await createEvent(locals.user.id, connections, body);
	return json(item, { status: 201 });
});
