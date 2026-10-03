// Admin: Einzelnen User bearbeiten / löschen.
//
//   PATCH  → Rolle, deaktiviert, Passwort, (optional) CalDAV-Verbindung manuell zuordnen
//   DELETE → Kaskade: CalDAV-Account (via Sidecar, falls zutreffend) + alle Userdaten löschen

import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getUserById, patchUser, publicUser, removeUser } from '$server/auth/userStore';
import { getAssigned, setAssigned, wipeUserData } from '$server/store/connections';
import { getSystemCaldav } from '$server/store/system';
import { deleteCaldavUser, SidecarError } from '$server/admin/caldavAdmin';
import type { UserRole, CalDavSettings } from '$lib/types';

export const PATCH: RequestHandler = async ({ params, request, locals }) => {
	if (locals.user?.role !== 'admin') return json({ error: 'Keine Berechtigung.' }, { status: 403 });

	const body = (await request.json().catch(() => ({}))) as {
		role?: UserRole;
		disabled?: boolean;
		password?: string;
		caldav?: CalDavSettings | null;
	};

	const target = getUserById(params.id);
	if (!target) return json({ error: 'User nicht gefunden.' }, { status: 404 });

	if (body.role !== undefined || body.disabled !== undefined || body.password !== undefined) {
		try {
			patchUser(params.id, {
				role: body.role,
				disabled: body.disabled,
				password: body.password
			});
		} catch (e) {
			return json({ error: e instanceof Error ? e.message : 'Unbekannter Fehler' }, { status: 400 });
		}
	}

	if (body.caldav !== undefined) {
		if (body.caldav === null) {
			return json({ error: 'Zugewiesene Verbindung kann nicht entfernt werden.' }, { status: 400 });
		}
		const c = body.caldav;
		if (!c.url || !c.url.trim()) {
			return json({ error: 'CalDAV-URL fehlt.' }, { status: 400 });
		}
		setAssigned(params.id, { url: c.url, username: c.username ?? '', password: c.password ?? '' });
	}

	const updated = getUserById(params.id)!;
	return json(publicUser(updated));
};

export const DELETE: RequestHandler = async ({ params, locals }) => {
	if (locals.user?.role !== 'admin') return json({ error: 'Keine Berechtigung.' }, { status: 403 });

	const target = getUserById(params.id);
	if (!target) return json({ error: 'User nicht gefunden.' }, { status: 404 });
	if (params.id === locals.user!.id) {
		return json({ error: 'Du kannst dich nicht selbst löschen.' }, { status: 400 });
	}

	// 1) CalDAV-Account löschen (falls die zugewiesene Verbindung zum System-CALDAV gehört).
	const assigned = getAssigned(target.id);
	const cfg = getSystemCaldav();
	const isSystemConn =
		assigned !== null &&
		cfg !== null &&
		assigned.url.replace(/\/+$/, '') === cfg.baseUrl.replace(/\/+$/, '');

	if (isSystemConn && cfg) {
		try {
			await deleteCaldavUser(cfg, target.username);
		} catch (e) {
			const msg =
				e instanceof SidecarError
					? `CalDAV-Account konnte nicht gelöscht werden: ${e.message}`
					: 'CalDAV-Admin-API nicht erreichbar.';
			return json({ error: msg }, { status: 502 });
		}
	}

	// 2) Alle lokalen Userdaten (Verbindungen etc.) löschen.
	wipeUserData(target.id);

	// 3) App-Account löschen (wirft, wenn letzter aktiver Admin).
	try {
		removeUser(target.id);
	} catch (e) {
		return json({ error: e instanceof Error ? e.message : 'Unbekannter Fehler' }, { status: 400 });
	}

	return json({ ok: true });
};
