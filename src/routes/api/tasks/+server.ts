import { json } from '@sveltejs/kit';
import type { RequestHandler } from '@sveltejs/kit';
import { listConnections } from '$server/store/connections';
import { listAllTasks, createTask, NotFoundError, ReadOnlyError, ValidationError } from '$server/lib/write';
import { CalDavError } from '$server/caldav/client';
import type { TaskCreateInput } from '$lib/types';

export const GET: RequestHandler = async ({ locals }) => {
	const connections = locals.user ? listConnections(locals.user.id) : [];
	if (connections.length === 0) {
		return json({ configured: false, tasks: [] });
	}
	try {
		const tasks = await listAllTasks(locals.user?.id ?? '', connections);
		return json({ configured: true, tasks });
	} catch (e: any) {
		return json(
			{ configured: true, tasks: [], error: e.message ?? 'Unbekannter Fehler' },
			{ status: 502 }
		);
	}
};

export const POST: RequestHandler = async ({ request, locals }) => {
	const connections = locals.user ? listConnections(locals.user.id) : [];
	if (connections.length === 0) {
		return json({ error: 'Keine CalDAV-Verbindung konfiguriert.' }, { status: 400 });
	}

	let body: TaskCreateInput;
	try {
		body = await request.json();
	} catch {
		return json({ error: 'Ungültiger JSON-Body.' }, { status: 400 });
	}

	try {
		// calendarId optional: fehlt ⇒ Server wählt den Standardkalender (resolveWriteTarget).
		const item = await createTask(locals.user?.id ?? '', connections, body);
		return json(item, { status: 201 });
	} catch (e: any) {
		if (e instanceof ValidationError) return json({ error: e.message }, { status: 400 });
		if (e instanceof NotFoundError) return json({ error: e.message }, { status: 404 });
		if (e instanceof ReadOnlyError) return json({ error: e.message }, { status: 403 });
		if (e instanceof CalDavError) return json({ error: e.message }, { status: 502 });
		return json({ error: e.message ?? 'Unbekannter Fehler' }, { status: 500 });
	}
};
