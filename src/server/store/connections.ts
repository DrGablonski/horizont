// Per-User-Verbindungs-Store: CalDAV-Verbindungen (1× zugewiesen + n× extern).
//
// Persistenz: DATA_DIR/users/{userId}/connections.json (atomares Schreiben).
// Die „assigned"-Verbindung (vom Admin beim User-Setup erzeugt) ist für den
// User read-only; externe Verbindungen (z. B. iCloud) verwaltet der User selbst.

import { mkdirSync, readFileSync, writeFileSync, renameSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { randomUUID } from 'node:crypto';
import { DATA_DIR } from '$server/lib/constants';
import type { CalDavConnection, CalDavSettings, ConnectionsResponse, ConnectionView } from '$lib/types';

const LEGACY_SETTINGS_FILE = 'settings.json';

function userDir(userId: string): string {
	const p = join(DATA_DIR, 'users', userId);
	mkdirSync(p, { recursive: true });
	return p;
}

function connsPath(userId: string): string {
	return join(userDir(userId), 'connections.json');
}

function readConns(userId: string): CalDavConnection[] {
	const p = connsPath(userId);
	if (!existsSync(p)) return [];
	try {
		const raw = JSON.parse(readFileSync(p, 'utf8')) as { connections?: unknown };
		if (!Array.isArray(raw.connections)) return [];
		return raw.connections.filter(
			(c): c is CalDavConnection =>
				c != null &&
				typeof c === 'object' &&
				typeof (c as CalDavConnection).id === 'string' &&
				typeof (c as CalDavConnection).url === 'string'
		);
	} catch {
		return [];
	}
}

function writeConns(userId: string, conns: CalDavConnection[]): void {
	const p = connsPath(userId);
	const tmp = `${p}.tmp`;
	writeFileSync(tmp, JSON.stringify({ version: 1, connections: conns }, null, 2), 'utf8');
	renameSync(tmp, p);
}

// ── Lesezugriff ───────────────────────────────────────────────────────────

export function listConnections(userId: string): CalDavConnection[] {
	return readConns(userId);
}

/** Die vom Admin zugewiesene Verbindung (primary) oder null. */
export function getAssigned(userId: string): CalDavConnection | null {
	return listConnections(userId).find((c) => c.kind === 'assigned') ?? null;
}

/** Credentials-Teil einer Verbindung (für den CalDAV-Client). */
export function toSettings(conn: CalDavConnection): CalDavSettings {
	return { url: conn.url, username: conn.username, password: conn.password };
}

export function listConnectionsView(userId: string): ConnectionsResponse {
	const conns = listConnections(userId);
	const views: ConnectionView[] = conns.map((c) => ({
		id: c.id,
		name: c.name,
		kind: c.kind,
		url: c.url,
		username: c.username,
		hasPassword: Boolean(c.password)
	}));
	return { configured: conns.length > 0, connections: views };
}

// ── Mutationen: assigned (nur Admin) ──────────────────────────────────────

export function setAssigned(userId: string, settings: CalDavSettings): CalDavConnection {
	const conns = readConns(userId);
	const conn: CalDavConnection = {
		id: randomUUID(),
		name: 'Zugewiesener CalDAV',
		kind: 'assigned',
		url: settings.url.trim().replace(/\/+$/, ''),
		username: settings.username.trim(),
		password: settings.password
	};
	const next = [conn, ...conns.filter((c) => c.kind !== 'assigned')];
	writeConns(userId, next);
	return conn;
}

// ── Mutationen: external (User selbst) ────────────────────────────────────

export interface ExternalConnectionInput {
	name: string;
	url: string;
	username: string;
	password: string;
}

export function createExternal(userId: string, input: ExternalConnectionInput): CalDavConnection {
	const url = (input.url ?? '').trim().replace(/\/+$/, '');
	if (!url) throw new Error('CalDAV-URL fehlt.');
	const username = (input.username ?? '').trim();
	const password = input.password ?? '';
	const name = (input.name ?? '').trim() || 'CalDAV';
	const conn: CalDavConnection = {
		id: randomUUID(),
		name,
		kind: 'external',
		url,
		username,
		password
	};
	writeConns(userId, [...listConnections(userId), conn]);
	return conn;
}

export function updateExternal(
	userId: string,
	connId: string,
	input: Partial<ExternalConnectionInput> & { password?: string }
): CalDavConnection {
	const conns = listConnections(userId);
	const idx = conns.findIndex((c) => c.id === connId && c.kind === 'external');
	if (idx === -1) throw new Error('Verbindung nicht gefunden.');

	const cur = conns[idx];
	let { url, username, password } = cur;
	if (input.url !== undefined) {
		url = input.url.trim().replace(/\/+$/, '');
		if (!url) throw new Error('CalDAV-URL fehlt.');
	}
	if (input.username !== undefined) username = input.username.trim();
	if (input.password !== undefined && input.password !== '') password = input.password;
	const name = input.name !== undefined && input.name.trim() !== '' ? input.name.trim() : cur.name;

	const next: CalDavConnection = { ...cur, name, url, username, password };
	conns[idx] = next;
	writeConns(userId, conns);
	return next;
}

export function removeExternal(userId: string, connId: string): void {
	const conns = listConnections(userId);
	const next = conns.filter((c) => !(c.id === connId && c.kind === 'external'));
	if (next.length === conns.length) throw new Error('Verbindung nicht gefunden.');
	writeConns(userId, next);
}

// ── Aufräumen bei User-Löschung ───────────────────────────────────────────

import { rmSync } from 'node:fs';

export function wipeUserData(userId: string): void {
	const p = join(DATA_DIR, 'users', userId);
	if (existsSync(p)) rmSync(p, { recursive: true, force: true });
}

// ── Legacy-Migration ──────────────────────────────────────────────────────

/**
 * Übernimmt die alte Einzel-User-Konfiguration (DATA_DIR/settings.json) als
 * „assigned"-Verbindung des ersten Admins und archiviert die Datei.
 * Wird genau einmal beim Setup aufgerufen; tut nichts, wenn die Datei fehlt.
 */
export function migrateLegacySettings(adminId: string): void {
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
		setAssigned(adminId, {
			url: raw.url,
			username: raw.username ?? '',
			password: raw.password ?? ''
		});
	}
	// Datei archivieren (nicht löschen, damit kein Data-Verlust entsteht).
	renameSync(legacy, `${legacy}.legacy`);
}
