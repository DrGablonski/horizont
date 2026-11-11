// Verbindungs-Store: CalDAV-Verbindungen des Users (alle voll editierbar).
//
// Persistenz: DATA_DIR/users/{userId}/connections.json (atomares Schreiben).
// Pro Deployment gibt es genau einen User; sämtliche Verbindungen gehören ihm
// und werden in den Einstellungen selbst angelegt, geändert und gelöscht.
//
// Dateiformat (Version 2): { version: 2, connections: CalDavConnection[], primaryId }.
// Genau eine Verbindung ist `primary` (Workflows, Standardziele), alle anderen
// `secondary`. Version 1 ohne primaryId wird rückwärtskompatibel gelesen
// (primaryId = erste Verbindung).

import { mkdirSync, readFileSync, writeFileSync, renameSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { randomUUID } from 'node:crypto';
import { DATA_DIR } from '$server/lib/constants';
import { normalizeCalDavUrl } from '$server/caldav/client';
import type {
	CalDavConnection,
	CalDavProvider,
	CalDavSettings,
	ConnectionRole,
	ConnectionsResponse,
	ConnectionView
} from '$lib/types';

const LEGACY_SETTINGS_FILE = 'settings.json';

function userDir(userId: string): string {
	const p = join(DATA_DIR, 'users', userId);
	mkdirSync(p, { recursive: true });
	return p;
}

function connsPath(userId: string): string {
	return join(userDir(userId), 'connections.json');
}

function isValidProvider(value: unknown): value is CalDavProvider {
	return (
		value === 'generic' ||
		value === 'icloud' ||
		value === 'google' ||
		value === 'nextcloud' ||
		value === 'radicale' ||
		value === 'bailkal' ||
		value === 'fastmail'
	);
}

interface StoreData {
	connections: CalDavConnection[];
	primaryId: string | null;
}

/** Liest die Verbindungsdatei und leitet primaryId sowie die Rollen ab. */
function readStore(userId: string): StoreData {
	const p = connsPath(userId);
	if (!existsSync(p)) return { connections: [], primaryId: null };
	let raw: { connections?: unknown; primaryId?: unknown };
	try {
		raw = JSON.parse(readFileSync(p, 'utf8')) as { connections?: unknown; primaryId?: unknown };
	} catch {
		return { connections: [], primaryId: null };
	}
	if (!Array.isArray(raw.connections)) return { connections: [], primaryId: null };

	const parsed: Omit<CalDavConnection, 'role'>[] = [];
	for (const item of raw.connections) {
		if (item == null || typeof item !== 'object') continue;
		const c = item as Partial<CalDavConnection>;
		if (typeof c.id !== 'string' || typeof c.url !== 'string') continue;
		parsed.push({
			id: c.id,
			name: typeof c.name === 'string' && c.name.trim() !== '' ? c.name : 'CalDAV',
			url: c.url,
			username: typeof c.username === 'string' ? c.username : '',
			password: typeof c.password === 'string' ? c.password : '',
			provider: isValidProvider(c.provider) ? c.provider : 'generic'
		});
	}

	// primaryId: Version-2-Wert, sonst erste Verbindung (Version 1, Abwärtskompatibilität).
	let primaryId = typeof raw.primaryId === 'string' ? raw.primaryId : null;
	if (!primaryId || !parsed.some((c) => c.id === primaryId)) primaryId = parsed[0]?.id ?? null;

	// Rollen leiten sich eindeutig von primaryId ab → genau eine primary.
	const connections = parsed.map(
		(c): CalDavConnection => ({ ...c, role: c.id === primaryId ? 'primary' : 'secondary' })
	);
	return { connections, primaryId };
}

function writeConns(userId: string, conns: CalDavConnection[], primaryId: string | null): void {
	const p = connsPath(userId);
	const tmp = `${p}.tmp`;
	// Rollen beim Speichern an primaryId ausrichten (Invariant: genau eine primary).
	const normalized: CalDavConnection[] = conns.map((c) => ({
		...c,
		role: c.id === primaryId ? 'primary' : 'secondary'
	}));
	writeFileSync(tmp, JSON.stringify({ version: 2, connections: normalized, primaryId }, null, 2), 'utf8');
	renameSync(tmp, p);
}

// ── Lesezugriff ───────────────────────────────────────────────────────────

export function listConnections(userId: string): CalDavConnection[] {
	return readStore(userId).connections;
}

/** Einzelne Verbindung per ID oder null. */
export function getConnectionById(userId: string, connId: string): CalDavConnection | null {
	return listConnections(userId).find((c) => c.id === connId) ?? null;
}

/** Die Hauptverbindung (primaryId, sonst erste Verbindung) oder null. */
export function getPrimaryConnection(userId: string): CalDavConnection | null {
	const { connections, primaryId } = readStore(userId);
	if (primaryId) {
		const found = connections.find((c) => c.id === primaryId);
		if (found) return found;
	}
	return connections[0] ?? null;
}

/** Credentials-Teil einer Verbindung (für den CalDAV-Client). */
export function toSettings(conn: CalDavConnection): CalDavSettings {
	return { url: conn.url, username: conn.username, password: conn.password };
}

export function listConnectionsView(userId: string): ConnectionsResponse {
	const { connections, primaryId } = readStore(userId);
	const views: ConnectionView[] = connections.map((c) => ({
		id: c.id,
		name: c.name,
		url: c.url,
		username: c.username,
		hasPassword: Boolean(c.password),
		role: c.role,
		provider: c.provider
	}));
	return { configured: connections.length > 0, connections: views, primaryId };
}

// ── Mutationen (der User selbst) ──────────────────────────────────────────

export interface ConnectionInput {
	name: string;
	url: string;
	username: string;
	password: string;
}

/**
 * Legt eine Verbindung an. Die erste wird automatisch `primary`, jede weitere
 * `secondary`; ein Rollenwechsel ist ausschließlich über setPrimaryConnection möglich.
 */
export function createConnection(
	userId: string,
	input: ConnectionInput & { provider?: CalDavProvider; role?: ConnectionRole }
): CalDavConnection {
	const url = normalizeCalDavUrl(input.url ?? '').replace(/\/+$/, '');
	if (!url) throw new Error('CalDAV-URL fehlt.');
	const username = (input.username ?? '').trim();
	const password = input.password ?? '';
	const name = (input.name ?? '').trim() || 'CalDAV';

	const store = readStore(userId);
	const isFirst = store.connections.length === 0;
	const role: ConnectionRole = isFirst ? 'primary' : 'secondary';
	const provider: CalDavProvider = isValidProvider(input.provider) ? input.provider : 'generic';

	const conn: CalDavConnection = { id: randomUUID(), name, url, username, password, role, provider };
	const primaryId = isFirst ? conn.id : store.primaryId;
	writeConns(userId, [...store.connections, conn], primaryId);
	return conn;
}

export function updateConnection(
	userId: string,
	connId: string,
	input: Partial<ConnectionInput> & { password?: string; provider?: CalDavProvider; role?: ConnectionRole }
): CalDavConnection {
	const store = readStore(userId);
	const idx = store.connections.findIndex((c) => c.id === connId);
	if (idx === -1) throw new Error('Verbindung nicht gefunden.');

	const cur = store.connections[idx];
	let { url, username, password } = cur;
	if (input.url !== undefined) {
		url = normalizeCalDavUrl(input.url).replace(/\/+$/, '');
		if (!url) throw new Error('CalDAV-URL fehlt.');
	}
	if (input.username !== undefined) username = input.username.trim();
	if (input.password !== undefined && input.password !== '') password = input.password;
	const name = input.name !== undefined && input.name.trim() !== '' ? input.name.trim() : cur.name;
	const provider: CalDavProvider = isValidProvider(input.provider) ? input.provider : cur.provider;
	// provider wird mitgeschrieben; die Rolle bleibt unverändert, da das Hoch-/
	// Herunterstufen ausschließlich setPrimaryConnection vorbehalten ist.
	const role: ConnectionRole = cur.role;

	const next: CalDavConnection = { ...cur, name, url, username, password, provider, role };
	store.connections[idx] = next;
	writeConns(userId, store.connections, store.primaryId);
	return next;
}

/** Macht die angegebene Verbindung zur einzigen primary, alle anderen zu secondary. */
export function setPrimaryConnection(userId: string, connId: string): CalDavConnection {
	const store = readStore(userId);
	const idx = store.connections.findIndex((c) => c.id === connId);
	if (idx === -1) throw new Error('Verbindung nicht gefunden.');

	writeConns(userId, store.connections, connId);
	return { ...store.connections[idx], role: 'primary' };
}

export function removeConnection(userId: string, connId: string): void {
	const store = readStore(userId);
	const next = store.connections.filter((c) => c.id !== connId);
	if (next.length === store.connections.length) throw new Error('Verbindung nicht gefunden.');
	// War die gelöschte Verbindung die primary, rückt die erste verbleibende nach.
	const primaryId = store.primaryId === connId ? next[0]?.id ?? null : store.primaryId;
	writeConns(userId, next, primaryId);
}

// ── Legacy-Migration ──────────────────────────────────────────────────────

/**
 * Übernimmt die alte Einzel-User-Konfiguration (DATA_DIR/settings.json) als
 * Verbindung des Setups-Users und archiviert die Datei.
 * Wird genau einmal beim Setup aufgerufen; tut nichts, wenn die Datei fehlt.
 */
export function migrateLegacySettings(userId: string): void {
	const legacy = join(DATA_DIR, LEGACY_SETTINGS_FILE);
	if (!existsSync(legacy)) return;

	let raw: CalDavSettings | null = null;
	try {
		const parsed = JSON.parse(readFileSync(legacy, 'utf8')) as CalDavSettings;
		if (parsed && typeof parsed.url === 'string' && parsed.url.trim() !== '') raw = parsed;
	} catch {
		// defekte Datei → nicht übernehmbar
	}

	if (raw) {
		// Erste Verbindung des Setups → wird automatisch zur primary.
		createConnection(userId, {
			name: 'CalDAV',
			url: raw.url,
			username: raw.username ?? '',
			password: raw.password ?? ''
		});
	}
	// Datei archivieren (nicht löschen, damit kein Data-Verlust entsteht).
	renameSync(legacy, `${legacy}.legacy`);
}
