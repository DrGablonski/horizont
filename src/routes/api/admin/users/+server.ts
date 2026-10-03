// Admin: User-Verwaltung.
//
//   GET    → alle Users (Admin-View) + Status der System-CALDAV-Konfiguration
//   POST   → User anlegen: App-Account + (falls System-CALDAV konfiguriert)
//            CalDAV-Account via Sidecar + zugewiesene Verbindung.
//            Ergebnis enthält die CalDAV-Zugangsdaten (einmalig, zum Übergeben).

import { json } from '@sveltejs/kit';
import type { RequestHandler } from '@sveltejs/kit';
import {
	createUser,
	getUserByUsername,
	listUsers,
	publicUser,
	removeUser
} from '$server/auth/userStore';
import { getSystemCaldavView } from '$server/store/system';
import { listConnectionsView } from '$server/store/connections';
import { SidecarError } from '$server/admin/caldavAdmin';
import { ensureCaldavForUser } from '$server/admin/provision';
import type { AdminUserView, CreateUserResult, UserRole } from '$lib/types';

function toAdminView(
	userId: string,
	role: UserRole,
	disabled: boolean,
	createdAt: number,
	lastLoginAt: number | null,
	username: string
): AdminUserView {
	const { connections } = listConnectionsView(userId);
	return {
		id: userId,
		username,
		role,
		createdAt,
		lastLoginAt,
		disabled,
		hasAssignedConnection: connections.some((c) => c.kind === 'assigned')
	};
}

export const GET: RequestHandler = ({ locals }) => {
	if (locals.user?.role !== 'admin') return json({ error: 'Keine Berechtigung.' }, { status: 403 });
	const users = listUsers().map((u) =>
		toAdminView(u.id, u.role, u.disabled, u.createdAt, u.lastLoginAt, u.username)
	);
	return json({ users, systemCaldav: getSystemCaldavView() });
};

export const POST: RequestHandler = async ({ request, locals }) => {
	if (locals.user?.role !== 'admin') return json({ error: 'Keine Berechtigung.' }, { status: 403 });

	const body = (await request.json().catch(() => null)) as {
		username?: string;
		password?: string;
	} | null;
	const username = body?.username?.trim() ?? '';
	const password = body?.password ?? '';

	if (!username || !password) {
		return json({ error: 'Benutzername und Passwort sind erforderlich.' }, { status: 400 });
	}
	if (getUserByUsername(username)) {
		return json({ error: `Der Benutzername „${username}“ ist bereits vergeben.` }, { status: 409 });
	}

	let user: ReturnType<typeof createUser>;
	try {
		user = createUser({ username, password, role: 'user' });
	} catch (e) {
		return json({ error: e instanceof Error ? e.message : 'Unbekannter Fehler' }, { status: 400 });
	}

	// CalDAV-Account anlegen (falls System-CALDAV konfiguriert).
	// ensureCaldavForUser ist idempotent: gibt null zurück, wenn nichts zu tun
	// ist (keine Config / bereits zugewiesen), wirft sonst bei Sidecar-Fehler.
	try {
		const caldav = await ensureCaldavForUser(user.id, username);
		return json({ user: publicUser(user), caldav } satisfies CreateUserResult, { status: 201 });
	} catch (e) {
		// CalDAV-Anlage fehlgeschlagen → App-User wieder entfernen (keine Halbzustände).
		removeUser(user.id);
		const msg =
			e instanceof SidecarError
				? `CalDAV-Account konnte nicht angelegt werden: ${e.message}`
				: 'CalDAV-Admin-API nicht erreichbar.';
		return json({ error: msg }, { status: 502 });
	}
};
