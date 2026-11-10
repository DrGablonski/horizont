// CalDAV-Verbindungen des Users:
//   GET    → Liste (ohne Passwörter)
//   POST   → Verbindung anlegen
//   PATCH  → Verbindung ändern
//   DELETE → Verbindung löschen
// Alle Verbindungen gehören dem User und sind voll editierbar/löschbar.

import { json } from '@sveltejs/kit';
import type { RequestHandler } from '@sveltejs/kit';
import {
	createConnection,
	listConnectionsView,
	removeConnection,
	updateConnection
} from '$server/store/connections';
import type { ConnectionInput } from '$server/store/connections';
import { invalidatePanelCache } from '$server/lib/panelCache';

function badRequest(msg: string) {
	return json({ error: msg }, { status: 400 });
}

export const GET: RequestHandler = ({ locals }) => {
	if (!locals.user) return json({ error: 'Nicht angemeldet.' }, { status: 401 });
	return json(listConnectionsView(locals.user.id));
};

export const POST: RequestHandler = async ({ request, locals }) => {
	if (!locals.user) return json({ error: 'Nicht angemeldet.' }, { status: 401 });

	const body = (await request.json().catch(() => null)) as Partial<ConnectionInput> | null;
	if (!body || typeof body.url !== 'string' || !body.url.trim()) {
		return badRequest('CalDAV-URL fehlt.');
	}
	const input: ConnectionInput = {
		name: typeof body.name === 'string' ? body.name : '',
		url: body.url,
		username: typeof body.username === 'string' ? body.username : '',
		password: typeof body.password === 'string' ? body.password : ''
	};
	try {
		createConnection(locals.user.id, input);
		invalidatePanelCache();
		return json(listConnectionsView(locals.user.id));
	} catch (e) {
		return badRequest(e instanceof Error ? e.message : 'Ungültige Eingaben.');
	}
};

export const PATCH: RequestHandler = async ({ request, locals }) => {
	if (!locals.user) return json({ error: 'Nicht angemeldet.' }, { status: 401 });

	const body = (await request.json().catch(() => null)) as
		| (Partial<ConnectionInput> & { id?: string; password?: string })
		| null;
	if (!body || typeof body.id !== 'string' || !body.id) {
		return badRequest('Verbindungs-ID fehlt.');
	}
	try {
		updateConnection(locals.user.id, body.id, {
			name: body.name,
			url: body.url,
			username: body.username,
			password: body.password
		});
		invalidatePanelCache();
		return json(listConnectionsView(locals.user.id));
	} catch (e) {
		return badRequest(e instanceof Error ? e.message : 'Ungültige Eingaben.');
	}
};

export const DELETE: RequestHandler = async ({ request, locals }) => {
	if (!locals.user) return json({ error: 'Nicht angemeldet.' }, { status: 401 });

	const body = (await request.json().catch(() => null)) as { id?: string } | null;
	if (!body || typeof body.id !== 'string' || !body.id) {
		return badRequest('Verbindungs-ID fehlt.');
	}
	try {
		removeConnection(locals.user.id, body.id);
		invalidatePanelCache();
		return json(listConnectionsView(locals.user.id));
	} catch (e) {
		return badRequest(e instanceof Error ? e.message : 'Ungültige Eingaben.');
	}
};
