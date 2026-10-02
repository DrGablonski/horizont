import { json } from '@sveltejs/kit';
import { getSettings } from '$server/store/store';
import { mutateTask, removeTask, NotFoundError, ValidationError } from '$server/lib/write';
import { CalDavError } from '$server/caldav/client';
import type { TaskUpdateInput } from '$lib/types';

function handleError(e: any) {
	if (e instanceof ValidationError) return json({ error: e.message }, { status: 400 });
	if (e instanceof NotFoundError) return json({ error: e.message }, { status: 404 });
	if (e instanceof CalDavError) return json({ error: e.message }, { status: e.status === 409 ? 409 : 502 });
	return json({ error: e.message ?? 'Unbekannter Fehler' }, { status: 500 });
}

export async function PATCH({ params, request }: { params: { calendarId: string; uid: string }; request: Request }) {
	const settings = getSettings();
	if (!settings) return json({ error: 'Keine CalDAV-Konfiguration.' }, { status: 400 });

	let body: TaskUpdateInput;
	try {
		body = await request.json();
	} catch {
		return json({ error: 'Ungültiger JSON-Body.' }, { status: 400 });
	}

	try {
		const item = await mutateTask(settings, params.calendarId, params.uid, body);
		return json(item);
	} catch (e: any) {
		return handleError(e);
	}
}

export async function DELETE({ params }: { params: { calendarId: string; uid: string } }) {
	const settings = getSettings();
	if (!settings) return json({ error: 'Keine CalDAV-Konfiguration.' }, { status: 400 });

	try {
		await removeTask(settings, params.calendarId, params.uid);
		return json({ ok: true });
	} catch (e: any) {
		return handleError(e);
	}
}
