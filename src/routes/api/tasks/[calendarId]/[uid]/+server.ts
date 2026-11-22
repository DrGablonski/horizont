import { json } from '@sveltejs/kit';
import type { RequestEvent } from './$types';
import { readJsonBody } from '$server/auth/apiHelpers';
import { withUser } from '$server/lib/route';
import { listConnections } from '$server/store/connections';
import { mutateTask, removeTask } from '$server/lib/write';
import type { TaskUpdateInput } from '$lib/types';

export const PATCH = withUser<RequestEvent>(async ({ params, request, locals }) => {
	const connections = listConnections(locals.user.id);
	if (connections.length === 0) {
		return json({ error: 'Keine CalDAV-Verbindung konfiguriert.' }, { status: 400 });
	}

	const body = await readJsonBody<TaskUpdateInput>(request);
	if (!body) return json({ error: 'Ungültiger JSON-Body.' }, { status: 400 });

	const item = await mutateTask(locals.user.id, connections, params.calendarId, params.uid, body);
	return json(item);
});

export const DELETE = withUser<RequestEvent>(async ({ params, locals }) => {
	const connections = listConnections(locals.user.id);
	if (connections.length === 0) {
		return json({ error: 'Keine CalDAV-Verbindung konfiguriert.' }, { status: 400 });
	}

	await removeTask(locals.user.id, connections, params.calendarId, params.uid);
	return json({ ok: true });
});
