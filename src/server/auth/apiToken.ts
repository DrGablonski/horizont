// Per-User API-Token (Maschinen-Auth für /api/*, z. B. für externe Tools/MCP):
// Der Token wird einmal erzeugt und im UI angezeigt, danach nur noch als
// scrypt-Hash gespeichert (SHA-256-Digest als schneller Lookup-Key).
//
// Persistenz: DATA_DIR/users/<id>/api-token.json (atomares Schreiben).
// Bei User-Löschung verschwindet die Datei mit dem User-Verzeichnis.

import { createHash, randomBytes, scryptSync, timingSafeEqual } from 'node:crypto';
import { mkdirSync, readFileSync, writeFileSync, renameSync, existsSync, unlinkSync } from 'node:fs';
import { join } from 'node:path';
import { DATA_DIR } from '$server/lib/constants';
import { listUsers, publicUser } from '$server/auth/userStore';
import type { ApiTokenView, AppUser } from '$lib/types';

const SALT_BYTES = 16;
const KEY_BYTES = 64;
const SCRYPT_OPTS = { N: 16384, r: 8, p: 1 };
const TOKEN_PREFIX = 'hz_';
const MIN_TOKEN_LEN = TOKEN_PREFIX.length + 64;
/** lastUsedAt wird höchstens so häufig neu geschrieben (vermeidet Schreib-Churn). */
const LAST_USED_MIN_INTERVAL_MS = 5 * 60 * 1000;

interface TokenFile {
	version: 1;
	digest: string; // sha256 hex des Klartext-Tokens (Lookup)
	salt: string; // hex
	hash: string; // scrypt hex
	createdAt: number;
	lastUsedAt: number | null;
}

function tokenPath(userId: string): string {
	const dir = join(DATA_DIR, 'users', userId);
	mkdirSync(dir, { recursive: true });
	return join(dir, 'api-token.json');
}

function readToken(userId: string): TokenFile | null {
	const p = tokenPath(userId);
	if (!existsSync(p)) return null;
	try {
		const raw = JSON.parse(readFileSync(p, 'utf8')) as Partial<TokenFile>;
		if (
			typeof raw?.digest !== 'string' ||
			typeof raw.salt !== 'string' ||
			typeof raw.hash !== 'string' ||
			typeof raw.createdAt !== 'number'
		) {
			return null;
		}
		return raw as TokenFile;
	} catch {
		return null;
	}
}

function writeTokenAtomic(userId: string, data: TokenFile): void {
	const p = tokenPath(userId);
	const tmp = `${p}.tmp`;
	writeFileSync(tmp, JSON.stringify(data, null, 2), 'utf8');
	renameSync(tmp, p);
}

function scryptOf(token: string, saltHex: string): string {
	return scryptSync(token, saltHex, KEY_BYTES, SCRYPT_OPTS).toString('hex');
}

/**
 * Erzeugt einen neuen Token (ersetzt einen vorhandenen) und liefert ihn
 * einmalig im Klartext zurück.
 */
export function generateApiToken(userId: string): { token: string; createdAt: number } {
	const token = `${TOKEN_PREFIX}${randomBytes(32).toString('hex')}`;
	const salt = randomBytes(SALT_BYTES).toString('hex');
	const createdAt = Date.now();
	writeTokenAtomic(userId, {
		version: 1,
		digest: createHash('sha256').update(token).digest('hex'),
		salt,
		hash: scryptOf(token, salt),
		createdAt,
		lastUsedAt: null
	});
	return { token, createdAt };
}

/** Lehnt den Token ab (no-op, wenn keiner vorhanden ist). */
export function revokeApiToken(userId: string): void {
	const p = tokenPath(userId);
	if (!existsSync(p)) return;
	try {
		unlinkSync(p);
	} catch {
		// Best-Effort.
	}
}

export function getApiTokenView(userId: string): ApiTokenView {
	const t = readToken(userId);
	return {
		hasToken: Boolean(t),
		createdAt: t?.createdAt ?? null,
		lastUsedAt: t?.lastUsedAt ?? null
	};
}

/**
 * Löst einen Bearer-Token in einen User auf.
 *
 * Ablauf: SHA-256-Digest (billig) über alle User-Dateien vergleichen,
 * scrypt-Verifikation nur beim Digest-Treffer. Deaktivierte User werden
 * übersprungen; die letzten-Nutzung wird (gedrosselt) mitgespeichert.
 */
export function resolveApiTokenUser(token: string): AppUser | null {
	if (typeof token !== 'string' || token.length < MIN_TOKEN_LEN || !token.startsWith(TOKEN_PREFIX)) {
		return null;
	}
	const digest = createHash('sha256').update(token).digest('hex');
	for (const u of listUsers()) {
		if (u.disabled) continue;
		const t = readToken(u.id);
		if (!t || t.digest !== digest) continue;
		const a = Buffer.from(scryptOf(token, t.salt), 'hex');
		const b = Buffer.from(t.hash, 'hex');
		if (a.length !== b.length || !timingSafeEqual(a, b)) continue;
		const now = Date.now();
		if (t.lastUsedAt == null || now - t.lastUsedAt >= LAST_USED_MIN_INTERVAL_MS) {
			t.lastUsedAt = now;
			writeTokenAtomic(u.id, t);
		}
		return publicUser(u);
	}
	return null;
}
