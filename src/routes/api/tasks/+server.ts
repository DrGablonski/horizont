import { json } from '@sveltejs/kit';
import { readJsonBody } from '$server/auth/apiHelpers';
import { withUser } from '$server/lib/route';
import { listConnections } from '$server/store/connections';
import { listAllTasks, createTask } from '$server/lib/write';
import type { TaskCreateInput } from '$lib/types';

export const GET = withUser(async ({ locals }) => {
	const connections = listConnections(locals.user.id);
	if (connections.length === 0) {
		return json({ configured: false, tasks: [] });
	}
	try {
		const tasks = await listAllTasks(locals.user.id, connections);
		return json({ configured: true, tasks });
	} catch (e) {
		// Antwortbild stabil halten: tasks bleiben leer, der Fehler steht als Feld dabei.
		return json(
			{
				configured: true,
				tasks: [],
				error: e instanceof Error ? e.message : 'Unbekannter Fehler'
			},
			{ status: 502 }
		);
	}
});

export const POST = withUser(async ({ request, locals }) => {
	const connections = listConnections(locals.user.id);
	if (connections.length === 0) {
		return json({ error: 'Keine CalDAV-Verbindung konfiguriert.' }, { status: 400 });
	}

	const body = await readJsonBody<TaskCreateInput>(request);
	if (!body) return json({ error: 'Ungültiger JSON-Body.' }, { status: 400 });

	// calendarId optional: fehlt ⇒ Server wählt den Standardkalender (resolveWriteTarget).
	const item = await createTask(locals.user.id, connections, body);
	return json(item, { status: 201 });
});
