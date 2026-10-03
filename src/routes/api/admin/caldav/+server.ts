// Admin: System-CALDAV-Konfiguration (Zielserver für die automatische
// CalDAV-User-Anlage/-Löschung über den caldav-admin-Sidecar).
//
//   GET  → aktueller Status (Token nie im Klartext)
//   POST → speichern (Token nur setzen, wenn neues angegeben wird)

import { json } from '@sveltejs/kit';
import type { RequestHandler } from '@sveltejs/kit';
import { getSystemCaldavView, saveSystemCaldav } from '$server/store/system';
import { ensureCaldavForAllUsers } from '$server/admin/provision';

export const GET: RequestHandler = ({ locals }) => {
	if (locals.user?.role !== 'admin') return json({ error: 'Keine Berechtigung.' }, { status: 403 });
	return json(getSystemCaldavView());
};

export const POST: RequestHandler = async ({ request, locals }) => {
	if (locals.user?.role !== 'admin') return json({ error: 'Keine Berechtigung.' }, { status: 403 });

	const body = (await request.json().catch(() => null)) as {
		baseUrl?: string;
		adminApiUrl?: string;
		adminToken?: string;
	} | null;

	if (!body || !body.baseUrl?.trim() || !body.adminApiUrl?.trim()) {
		return json(
			{ error: 'Basis-URL und Admin-API-URL sind erforderlich.' },
			{ status: 400 }
		);
	}

	try {
		saveSystemCaldav({
			baseUrl: body.baseUrl,
			adminApiUrl: body.adminApiUrl,
			adminToken: body.adminToken
		});
	} catch (e) {
		return json({ error: e instanceof Error ? e.message : 'Unbekannter Fehler' }, { status: 400 });
	}

	// Rückwirkende Provisionierung: bestehende Users, die noch keinen
	// CalDAV-Account haben, bekommen jetzt einen (idempotent, nie fatal).
	const provisioning = await ensureCaldavForAllUsers();

	return json({ ...getSystemCaldavView(), provisioning });
};
