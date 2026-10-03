// Zentrales Auth-Gate:
//  - Session-Cookie → event.locals.user
//  - /api/*        → 401 JSON (außer /api/auth/login)
//  - Seiten        → 303-Redirect zu /login bzw. /setup (wenn noch kein User existiert)
//  - /admin*       → 303 /einstellungen (Admin-Funktionen leben dort als Admin-Tabs)

import { redirect } from '@sveltejs/kit';
import type { Handle } from '@sveltejs/kit';
import { SESSION_COOKIE, getSessionUser } from '$server/auth/sessionStore';
import { hasUsers } from '$server/auth/userStore';

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

	// /admin wurde in /einstellungen verlagert (dort für Admins zusätzliche
	// Tabs: Users, System-CALDAV). Alte Links leiten dorthin weiter;
	// /api/admin/* bleibt davon unberührt (wird weiter unten behandelt).
	if (!isApi && (path === '/admin' || path.startsWith('/admin/'))) {
		return redirect(303, '/einstellungen');
	}

	return resolve(event);
};
