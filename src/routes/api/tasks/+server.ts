import { json } from '@sveltejs/kit';
import { getSettings } from '$server/store/store';
import { listAllTasks, createTask, NotFoundError, ValidationError } from '$server/lib/write';
import { CalDavError } from '$server/caldav/client';
import type { TaskCreateInput } from '$lib/types';

export async function GET() {
	const settings = getSettings();
	if (!settings) {
		return json({ configured: false, tasks: [] });
	}
	try {
		const tasks = await listAllTasks(settings);
		return json({ configured: true, tasks });
	} catch (e: any) {
		return json({ configured: true, tasks: [], error: e.message ?? 'Unbekannter Fehler' }, { status: 502 });
	}
}

export async function POST({ request }: { request: Request }) {
	const settings = getSettings();
	if (!settings) return json({ error: 'Keine CalDAV-Konfiguration.' }, { status: 400 });

	let body: TaskCreateInput;
	try {
		body = await request.json();
	} catch {
		return json({ error: 'Ungültiger JSON-Body.' }, { status: 400 });
	}

	try {
		const item = await createTask(settings, body);
		return json(item, { status: 201 });
	} catch (e: any) {
		if (e instanceof ValidationError) return json({ error: e.message }, { status: 400 });
		if (e instanceof NotFoundError) return json({ error: e.message }, { status: 404 });
		if (e instanceof CalDavError) return json({ error: e.message }, { status: 502 });
		return json({ error: e.message ?? 'Unbekannter Fehler' }, { status: 500 });
	}
}
