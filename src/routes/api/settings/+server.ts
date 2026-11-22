// CalDAV-Verbindungen des Users:
//   GET    → Liste (ohne Passwörter, inkl. role/provider/primaryId)
//   POST   → Verbindung anlegen (provider wählbar; role:'primary' → setPrimaryConnection)
//   PATCH  → Verbindung ändern (provider; role:'primary' → setPrimaryConnection)
//   DELETE → Verbindung löschen
// Alle Verbindungen gehören dem User und sind voll editierbar/löschbar.
// Rollenwechsel (Hochstufen) ausschließlich über setPrimaryConnection; eine
// Herabstufung ergibt sich automatisch, wenn eine andere Verbindung primary wird.
// Fehler werfen die Store-Funktionen (mit deutscher Meldung) → mapError: 400.

import { json } from '@sveltejs/kit';
import { withUser } from '$server/lib/route';
import {
	createConnection,
	listConnectionsView,
	removeConnection,
	setPrimaryConnection,
	updateConnection
} from '$server/store/connections';
import type { ConnectionInput } from '$server/store/connections';
import { invalidatePanelCache } from '$server/lib/panelCache';
import { readJsonBody } from '$server/auth/apiHelpers';
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

export const GET = withUser(({ locals }) => json(listConnectionsView(locals.user.id)));

export const POST = withUser(async ({ request, locals }) => {
	const body = await readJsonBody<Partial<ConnectionInput> & { provider?: unknown; role?: unknown }>(
		request
	);
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
	const conn = createConnection(locals.user.id, input);
	// Gewünschtes primary: erst anlegen, dann hochstufen (erste Verbindung ist es ohnehin).
	if (body.role === 'primary') setPrimaryConnection(locals.user.id, conn.id);
	invalidatePanelCache();
	return json(listConnectionsView(locals.user.id));
});

export const PATCH = withUser(async ({ request, locals }) => {
	const body = await readJsonBody<
		Partial<ConnectionInput> & { id?: string; password?: string; provider?: unknown; role?: unknown }
	>(request);
	if (!body || typeof body.id !== 'string' || !body.id) {
		return badRequest('Verbindungs-ID fehlt.');
	}
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
});

export const DELETE = withUser(async ({ request, locals }) => {
	const body = await readJsonBody<{ id?: string }>(request);
	if (!body || typeof body.id !== 'string' || !body.id) {
		return badRequest('Verbindungs-ID fehlt.');
	}
	removeConnection(locals.user.id, body.id);
	invalidatePanelCache();
	return json(listConnectionsView(locals.user.id));
});
