// System-CALDAV-Konfiguration (Admin): Zielserver, an den CalDAV-Accounts
// für neue User angelegt werden (über den caldav-admin-Sidecar).
//
// Persistenz: DATA_DIR/system/caldav.json (atomares Schreiben).

import { mkdirSync, readFileSync, writeFileSync, renameSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { DATA_DIR } from '$server/lib/constants';
import type { SystemCaldavConfig, SystemCaldavConfigView } from '$lib/types';

const FILE = join('system', 'caldav.json');

function dataPath(): string {
	mkdirSync(join(DATA_DIR, 'system'), { recursive: true });
	return join(DATA_DIR, FILE);
}

function readJson(): { version: 1; config: SystemCaldavConfig | null } {
	const p = dataPath();
	if (!existsSync(p)) return { version: 1, config: null };
	try {
		return JSON.parse(readFileSync(p, 'utf8')) as { version: 1; config: SystemCaldavConfig | null };
	} catch {
		return { version: 1, config: null };
	}
}

export function getSystemCaldav(): SystemCaldavConfig | null {
	const { config } = readJson();
	if (!config || !config.baseUrl || !config.adminApiUrl) return null;
	return config;
}

export function saveSystemCaldav(input: {
	baseUrl: string;
	adminApiUrl: string;
	adminToken?: string;
}): SystemCaldavConfig {
	const current = getSystemCaldav();
	const baseUrl = (input.baseUrl ?? '').trim().replace(/\/+$/, '');
	const adminApiUrl = (input.adminApiUrl ?? '').trim().replace(/\/+$/, '');
	if (!baseUrl) throw new Error('Basis-URL fehlt.');
	if (!adminApiUrl) throw new Error('Admin-API-URL fehlt.');

	const config: SystemCaldavConfig = {
		baseUrl,
		adminApiUrl,
		adminToken:
			input.adminToken && input.adminToken.trim() !== ''
				? input.adminToken.trim()
				: current?.adminToken ?? ''
	};

	const p = dataPath();
	const tmp = `${p}.tmp`;
	writeFileSync(tmp, JSON.stringify({ version: 1, config }, null, 2), 'utf8');
	renameSync(tmp, p);
	return config;
}

export function getSystemCaldavView(): SystemCaldavConfigView {
	const c = getSystemCaldav();
	if (!c) {
		return { configured: false, baseUrl: '', adminApiUrl: '', hasToken: false };
	}
	return {
		configured: true,
		baseUrl: c.baseUrl,
		adminApiUrl: c.adminApiUrl,
		hasToken: Boolean(c.adminToken)
	};
}
