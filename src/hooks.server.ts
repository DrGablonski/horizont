// Zentrales Auth-Gate:
//  - Session-Cookie → event.locals.user
//  - /api/*        → 401 JSON (außer /api/auth/login)
//  - Seiten        → 303-Redirect zu /login bzw. /setup (wenn noch kein User existiert)

import { redirect } from '@sveltejs/kit';
import type { Handle } from '@sveltejs/kit';
import { SESSION_COOKIE, getSessionUser } from '$server/auth/sessionStore';
import { hasUsers } from '$server/auth/userStore';
import { removeLegacyAgentFiles } from '$server/lib/legacyCleanup';

// Beim Start: verwaiste Agent-Config-Dateien entfernen (Funktion entfernt).
removeLegacyAgentFiles();

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

export const handle: Handle = ({ event, resolve }) => {
	const token = event.cookies.get(SESSION_COOKIE);
	const user = getSessionUser(token);
	event.locals.user = user;

	const path = event.url.pathname;
	const isApi = path.startsWith('/api/');
	const isAuthApi = path === '/api/auth/login' || path === '/api/auth/setup';
	const isPublicPage = path === '/login' || path === '/setup';

	// ── Nicht angemeldet ───────────────────────────────────────────────────
	if (user == null) {
		if (isApi) {
			// Login/Setup sind die einzigen öffentlichen API-Endpunkte.
			if (isAuthApi && event.request.method === 'POST') return resolve(event);
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
