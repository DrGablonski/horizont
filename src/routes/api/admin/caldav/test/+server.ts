// POST /api/admin/caldav/test — Sidecar-Erreichbarkeit + Token prüfen.
// Body: { baseUrl, adminApiUrl, adminToken? } — wenn kein Token, wird der
// gespeuchte verwendet.

import { json } from '@sveltejs/kit';
import type { RequestHandler } from '@sveltejs/kit';
import { getSystemCaldav } from '$server/store/system';
import { checkCaldavAdmin } from '$server/admin/caldavAdmin';
import type { SystemCaldavConfig } from '$lib/types';

export const POST: RequestHandler = async ({ request, locals }) => {
	if (locals.user?.role !== 'admin') return json({ error: 'Keine Berechtigung.' }, { status: 403 });

	const body = (await request.json().catch(() => null)) as {
		baseUrl?: string;
		adminApiUrl?: string;
		adminToken?: string;
	} | null;

	const stored = getSystemCaldav();
	let cfg: SystemCaldavConfig | null = null;
	if (body?.adminApiUrl?.trim()) {
		const token = (body.adminToken ?? '').trim();
		cfg = {
			baseUrl: (body.baseUrl ?? '').trim().replace(/\/+$/, ''),
			adminApiUrl: body.adminApiUrl.trim().replace(/\/+$/, ''),
			adminToken: token || stored?.adminToken || ''
		};
	} else {
		cfg = stored;
	}

	if (!cfg) {
		return json({ ok: false, error: 'Keine Konfiguration zum Testen vorhanden.' }, { status: 400 });
	}

	const result = await checkCaldavAdmin(cfg);
	return json(result);
};
