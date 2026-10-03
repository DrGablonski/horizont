// Client für den caldav-admin-Sidecar (läuft auf dem Radicale-Host).
// Der Sidecar verwaltet die htpasswd-User + Collection-Verzeichnisse von Radicale,
// da Radicale selbst keine Admin-API hat.
//
// Endpunkte (Basis = adminApiUrl):
//   GET  /health                → { ok: true }
//   POST /api/v1/users          → { login, password }
//   DELETE /api/v1/users/{login} → { ok: true }  (löscht User + Collections)

import type { SystemCaldavConfig } from '$lib/types';

export class SidecarError extends Error {
	status: number;
	constructor(msg: string, status: number) {
		super(msg);
		this.name = 'SidecarError';
		this.status = status;
	}
}

async function call(
	base: string,
	path: string,
	token: string,
	init?: RequestInit
): Promise<Response> {
	const res = await fetch(`${base.replace(/\/+$/, '')}${path}`, {
		...init,
		headers: {
			'Content-Type': 'application/json',
			'X-Admin-Token': token,
			...(init?.headers as Record<string, string> | undefined)
		}
	});
	if (res.status === 401 || res.status === 403) {
		throw new SidecarError('Admin-Token ungültig (403).', res.status);
	}
	if (!res.ok) {
		let msg = `Admin-API ${res.status}`;
		try {
			const body = (await res.json()) as { error?: string };
			if (body?.error) msg = body.error;
		} catch {
			/* kein JSON */
		}
		throw new SidecarError(msg, res.status);
	}
	return res;
}

/** Erzeugt einen CalDAV-User beim Radicale (via Sidecar). */
export async function createCaldavUser(
	cfg: SystemCaldavConfig,
	login: string,
	password: string
): Promise<void> {
	await call(cfg.adminApiUrl, '/api/v1/users', cfg.adminToken, {
		method: 'POST',
		body: JSON.stringify({ login, password })
	});
}

/** Löscht einen CalDAV-User inkl. aller Collections (via Sidecar). */
export async function deleteCaldavUser(cfg: SystemCaldavConfig, login: string): Promise<void> {
	await call(cfg.adminApiUrl, `/api/v1/users/${encodeURIComponent(login)}`, cfg.adminToken, {
		method: 'DELETE'
	});
}

/** Erreichbarkeit + Token-Prüfung. */
export async function checkCaldavAdmin(cfg: SystemCaldavConfig): Promise<{ ok: boolean; error?: string }> {
	try {
		const res = await call(cfg.adminApiUrl, '/health', cfg.adminToken);
		const body = (await res.json()) as { ok?: boolean };
		return { ok: body.ok === true };
	} catch (e) {
		return { ok: false, error: e instanceof Error ? e.message : String(e) };
	}
}
