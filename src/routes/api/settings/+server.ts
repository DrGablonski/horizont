// CalDAV-Verbindungen des Users:
//   GET    → Liste (ohne Passwörter, inkl. role/provider/primaryId)
//   POST   → Verbindung anlegen (provider wählbar; role:'primary' → setPrimaryConnection)
//   PATCH  → Verbindung ändern (provider; role:'primary' → setPrimaryConnection)
//   DELETE → Verbindung löschen
// Alle Verbindungen gehören dem User und sind voll editierbar/löschbar.
// Rollenwechsel (Hochstufen) ausschließlich über setPrimaryConnection; eine
// Herabstufung ergibt sich automatisch, wenn eine andere Verbindung primary wird.

import { json } from '@sveltejs/kit';
import type { RequestHandler } from '@sveltejs/kit';
import {
	createConnection,
	listConnectionsView,
	removeConnection,
	setPrimaryConnection,
	updateConnection
} from '$server/store/connections';
import type { ConnectionInput } from '$server/store/connections';
import { invalidatePanelCache } from '$server/lib/panelCache';
import type { CalDavProvider } from '$lib/types';

const PROVIDERS: readonly string[] = [
	'generic',
	'icloud',
	'google',
	'nextcloud',
	'radicale',
	'bailkal',
	'fastmail'
];

/** Anbieter aus dem Body übernehmen, unbekannte Werte → 'generic'. */
function readProvider(value: unknown): CalDavProvider {
	return typeof value === 'string' && PROVIDERS.includes(value) ? (value as CalDavProvider) : 'generic';
}

function badRequest(msg: string) {
	return json({ error: msg }, { status: 400 });
}

export const GET: RequestHandler = ({ locals }) => {
	if (!locals.user) return json({ error: 'Nicht angemeldet.' }, { status: 401 });
	return json(listConnectionsView(locals.user.id));
};

export const POST: RequestHandler = async ({ request, locals }) => {
	if (!locals.user) return json({ error: 'Nicht angemeldet.' }, { status: 401 });

	const body = (await request.json().catch(() => null)) as
		| (Partial<ConnectionInput> & { provider?: unknown; role?: unknown })
		| null;
	if (!body || typeof body.url !== 'string' || !body.url.trim()) {
		return badRequest('CalDAV-URL fehlt.');
	}
	const input: ConnectionInput & { provider: CalDavProvider } = {
		name: typeof body.name === 'string' ? body.name : '',
		url: body.url,
		username: typeof body.username === 'string' ? body.username : '',
		password: typeof body.password === 'string' ? body.password : '',
		provider: readProvider(body.provider)
	};
	try {
		const conn = createConnection(locals.user.id, input);
		// Gewünschtes primary: erst anlegen, dann hochstufen (erste Verbindung ist es ohnehin).
		if (body.role === 'primary') setPrimaryConnection(locals.user.id, conn.id);
		invalidatePanelCache();
		return json(listConnectionsView(locals.user.id));
	} catch (e) {
		return badRequest(e instanceof Error ? e.message : 'Ungültige Eingaben.');
	}
};

export const PATCH: RequestHandler = async ({ request, locals }) => {
	if (!locals.user) return json({ error: 'Nicht angemeldet.' }, { status: 401 });

	const body = (await request.json().catch(() => null)) as
		| (Partial<ConnectionInput> & { id?: string; password?: string; provider?: unknown; role?: unknown })
		| null;
	if (!body || typeof body.id !== 'string' || !body.id) {
		return badRequest('Verbindungs-ID fehlt.');
	}
	try {
		const patch: Partial<ConnectionInput> & { password?: string; provider?: CalDavProvider } = {
			name: body.name,
			url: body.url,
			username: body.username,
			password: body.password
		};
		// provider nur mitschicken, wenn er im Body vorkommt (sonst bleibt er unverändert).
		if (body.provider !== undefined) patch.provider = readProvider(body.provider);
		updateConnection(locals.user.id, body.id, patch);
		// Rollenwechsel: nur das Hochstufen auf primary ist möglich.
		if (body.role === 'primary') setPrimaryConnection(locals.user.id, body.id);
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
