// Per-User-Verbindungen:
//   GET    → Liste (ohne Passwörter)
//   POST   → externe Verbindung anlegen (User selbst)
//   PATCH  → externe Verbindung ändern
//   DELETE → externe Verbindung löschen
// Die „assigned"-Verbindung (vom Admin) ist read-only.

import { json } from '@sveltejs/kit';
import type { RequestHandler } from '@sveltejs/kit';
import {
	createExternal,
	listConnectionsView,
	removeExternal,
	updateExternal
} from '$server/store/connections';
import type { ExternalConnectionInput } from '$server/store/connections';

function badRequest(msg: string) {
	return json({ error: msg }, { status: 400 });
}

export const GET: RequestHandler = ({ locals }) => {
	if (!locals.user) return json({ error: 'Nicht angemeldet.' }, { status: 401 });
	return json(listConnectionsView(locals.user.id));
};

export const POST: RequestHandler = async ({ request, locals }) => {
	if (!locals.user) return json({ error: 'Nicht angemeldet.' }, { status: 401 });

	const body = (await request.json().catch(() => null)) as Partial<ExternalConnectionInput> | null;
	if (!body || typeof body.url !== 'string' || !body.url.trim()) {
		return badRequest('CalDAV-URL fehlt.');
	}
	const input: ExternalConnectionInput = {
		name: typeof body.name === 'string' ? body.name : '',
		url: body.url,
		username: typeof body.username === 'string' ? body.username : '',
		password: typeof body.password === 'string' ? body.password : ''
	};
	try {
		createExternal(locals.user.id, input);
		return json(listConnectionsView(locals.user.id));
	} catch (e) {
		return badRequest(e instanceof Error ? e.message : 'Ungültige Eingaben.');
	}
};

export const PATCH: RequestHandler = async ({ request, locals }) => {
	if (!locals.user) return json({ error: 'Nicht angemeldet.' }, { status: 401 });

	const body = (await request.json().catch(() => null)) as
		| (Partial<ExternalConnectionInput> & { id?: string; password?: string })
		| null;
	if (!body || typeof body.id !== 'string' || !body.id) {
		return badRequest('Verbindungs-ID fehlt.');
	}
	try {
		updateExternal(locals.user.id, body.id, {
			name: body.name,
			url: body.url,
			username: body.username,
			password: body.password
		});
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
		removeExternal(locals.user.id, body.id);
		return json(listConnectionsView(locals.user.id));
	} catch (e) {
		return badRequest(e instanceof Error ? e.message : 'Ungültige Eingaben.');
	}
};
