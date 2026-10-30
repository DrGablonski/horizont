// Zentrales Auth-Gate:
//  - Session-Cookie        → event.locals.user
//  - API-Token (Bearer)    → event.locals.user (nur /api/*, für externe Tools)
//  - /api/*                → 401 JSON (außer /api/auth/* und der OpenAPI-Spec)
//  - Seiten                 → 303-Redirect zu /login bzw. /setup (wenn noch kein User existiert)

import { redirect } from '@sveltejs/kit';
import type { Handle } from '@sveltejs/kit';
import { SESSION_COOKIE, getSessionUser } from '$server/auth/sessionStore';
import { hasUsers } from '$server/auth/userStore';
import { resolveApiTokenUser } from '$server/auth/apiToken';
import { removeLegacyAgentFiles } from '$server/lib/legacyCleanup';
import { startNotifyJob } from '$server/jobs/notify';

// Beim Start: verwaiste Agent-Config-Dateien entfernen (Funktion entfernt).
removeLegacyAgentFiles();

// Täglicher Benachrichtigungs-Job (offene Schul-Tasks per Webhook).
startNotifyJob();

function notLoggedIn(): Response {
	return new Response(JSON.stringify({ error: 'Nicht angemeldet.' }), {
		status: 401,
		headers: { 'Content-Type': 'application/json' }
	});
}

function forbidden(): Response {
	return new Response(JSON.stringify({ error: 'Keine Berechtigung.' }), {
		status: 403,
		headers: { 'Content-Type': 'application/json' }
	});
}

// Globale Body-Obergrenze: JSON-Payloads sind klein; größere Bodies haben
// keinen Sinn und würden sonst Speicherressourcen binden (DoS).
const MAX_REQUEST_BODY_BYTES = 1024 * 1024; // 1 MiB

export const handle: Handle = ({ event, resolve }) => {
	const path = event.url.pathname;

	// Body-Limit (Content-Length bekannt). Chunked-Bodies ohne Content-Length
	// werden zusätzlich von readJsonBody (login/setup) streamend begrenzt.
	if (['POST', 'PUT', 'PATCH'].includes(event.request.method)) {
		const len = Number(event.request.headers.get('content-length') ?? '');
		if (Number.isFinite(len) && len > MAX_REQUEST_BODY_BYTES) {
			return new Response(JSON.stringify({ error: 'Anfrage zu groß.' }), {
				status: 413,
				headers: { 'Content-Type': 'application/json' }
			});
		}
	}

	const isApi = path.startsWith('/api/');
	const isAuthApi = path === '/api/auth/login' || path === '/api/auth/setup';
	// Öffentliche Spezifikation — enthält keine sensiblen Daten.
	const isOpenApi = path === '/api/openapi.json';
	const isPublicPage = path === '/login' || path === '/setup';

	const cookieToken = event.cookies.get(SESSION_COOKIE);
	let user = getSessionUser(cookieToken);

	// API-Token (Maschinen-Auth, z. B. für T3 Code): nur auf /api/* und nur,
	// wenn keine Session existiert. `Authorization: Bearer <token>`.
	if (user == null && isApi) {
		const auth = event.request.headers.get('authorization') ?? '';
		const m = auth.match(/^Bearer\s+(.+)$/i);
		if (m) user = resolveApiTokenUser(m[1].trim());
	}
	event.locals.user = user;

	// ── Nicht angemeldet ───────────────────────────────────────────────────
	if (user == null) {
		if (isApi) {
			// Login/Setup und die OpenAPI-Spec sind die öffentlichen Endpunkte.
			if (isAuthApi && event.request.method === 'POST') return resolve(event);
			if (isOpenApi && event.request.method === 'GET') return resolve(event);
			return notLoggedIn();
		}
		// Seiten: Setup ist nur öffentlich, solange es gar keinen User gibt.
		if (isPublicPage && path === '/setup' && !hasUsers()) return resolve(event);
		if (isPublicPage && path === '/login') return resolve(event);
		return redirect(303, hasUsers() ? '/login' : '/setup');
	}

	// ── Angemeldet ─────────────────────────────────────────────────────────
	if (path === '/login') return redirect(303, '/');
	if (path === '/setup') return redirect(303, '/');

	return resolve(event);
};
