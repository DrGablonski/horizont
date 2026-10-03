// User-Store: Persistenz (JSON) + scrypt-Passwort-Hashing.
//
// users.json im Datenverzeichnis, atomares Schreiben (tmp + rename).
// Sessions sind rein in-memory (siehe sessionStore.ts) — nach einem
// Container-Neustart sind alle Users automatisch abgemeldet.

import { randomUUID, scryptSync, timingSafeEqual } from 'node:crypto';
import { mkdirSync, readFileSync, writeFileSync, renameSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { DATA_DIR } from '$server/lib/constants';
import type { AppUser, UserRole } from '$lib/types';

const USERS_FILE = 'users.json';
const SALT_BYTES = 16;
const KEY_BYTES = 64;
const SCRYPT_OPTS = { N: 16384, r: 8, p: 1 };

export interface StoredUser {
	id: string;
	username: string;
	salt: string; // hex
	passwordHash: string; // hex
	role: UserRole;
	disabled: boolean;
	createdAt: number;
	lastLoginAt: number | null;
}

interface UsersFile {
	version: 1;
	users: StoredUser[];
}

const USERNAME_RE = /^[a-zA-Z0-9][a-zA-Z0-9._-]{1,31}$/;

function dataPath(file: string): string {
	mkdirSync(DATA_DIR, { recursive: true });
	return join(DATA_DIR, file);
}

function readJson<T>(file: string, fallback: T): T {
	const p = dataPath(file);
	if (!existsSync(p)) return fallback;
	try {
		return JSON.parse(readFileSync(p, 'utf8')) as T;
	} catch {
		return fallback;
	}
}

function writeJsonAtomic(file: string, data: unknown): void {
	const p = dataPath(file);
	const tmp = `${p}.tmp`;
	writeFileSync(tmp, JSON.stringify(data, null, 2), 'utf8');
	renameSync(tmp, p);
}

// ── Lese-/Schreibzugriff ──────────────────────────────────────────────────

export function listUsers(): StoredUser[] {
	const file = readJson<UsersFile>(USERS_FILE, { version: 1, users: [] });
	if (!Array.isArray(file.users)) return [];
	return file.users.filter((u) => u && typeof u.id === 'string' && typeof u.username === 'string');
}

function saveUsers(users: StoredUser[]): void {
	writeJsonAtomic(USERS_FILE, { version: 1, users });
}

export function hasUsers(): boolean {
	return listUsers().length > 0;
}

export function getUserById(id: string): StoredUser | null {
	return listUsers().find((u) => u.id === id) ?? null;
}

/** Case-insensitive Username-Lookup. */
export function getUserByUsername(username: string): StoredUser | null {
	const needle = username.toLowerCase();
	return listUsers().find((u) => u.username.toLowerCase() === needle) ?? null;
}

// ── Passwort-Hashing (scrypt) ─────────────────────────────────────────────

export function hashPassword(password: string): { salt: string; hash: string } {
	const salt = randomUUID().replace(/-/g, '').slice(0, SALT_BYTES * 2);
	const hash = scryptSync(password, salt, KEY_BYTES, SCRYPT_OPTS).toString('hex');
	return { salt, hash };
}

export function verifyPassword(user: StoredUser, password: string): boolean {
	const { hash } = hashPasswordWithSalt(password, user.salt);
	const a = Buffer.from(hash, 'hex');
	const b = Buffer.from(user.passwordHash, 'hex');
	return a.length === b.length && timingSafeEqual(a, b);
}

function hashPasswordWithSalt(password: string, saltHex: string): { hash: string } {
	const hash = scryptSync(password, saltHex, KEY_BYTES, SCRYPT_OPTS).toString('hex');
	return { hash };
}

// ── Validierung ───────────────────────────────────────────────────────────

function assertUsername(username: string): void {
	if (!USERNAME_RE.test(username)) {
		throw new Error(
			'Benutzername: 2–32 Zeichen, beginnt mit Buchstabe/Ziffer, erlaubte Zeichen a–z A–Z 0–9 . _ -'
		);
	}
}

function assertPassword(password: string): void {
	if (typeof password !== 'string' || password.length < 8) {
		throw new Error('Passwort: mindestens 8 Zeichen.');
	}
}

// ── Mutationen ────────────────────────────────────────────────────────────

export function createUser(input: {
	username: string;
	password: string;
	role: UserRole;
}): StoredUser {
	const username = input.username.trim();
	const password = input.password;
	assertUsername(username);
	assertPassword(password);

	const users = listUsers();
	if (users.some((u) => u.username.toLowerCase() === username.toLowerCase())) {
		throw new Error(`Der Benutzername „${username}“ ist bereits vergeben.`);
	}

	const { salt, hash } = hashPassword(password);
	const now = Date.now();
	const user: StoredUser = {
		id: randomUUID(),
		username,
		salt,
		passwordHash: hash,
		role: input.role,
		disabled: false,
		createdAt: now,
		lastLoginAt: null
	};
	users.push(user);
	saveUsers(users);
	return user;
}

export function patchUser(
	id: string,
	patch: { role?: UserRole; disabled?: boolean; password?: string }
): StoredUser {
	const users = listUsers();
	const idx = users.findIndex((u) => u.id === id);
	if (idx === -1) throw new Error('User nicht gefunden.');

	if (patch.role !== undefined && patch.role !== users[idx].role) {
		// Letzter aktiver Admin darf kein User mehr werden.
		const activeAdmins = users.filter((u) => u.role === 'admin' && !u.disabled);
		if (users[idx].role === 'admin' && !users[idx].disabled && activeAdmins.length <= 1) {
			throw new Error('Der letzte aktive Admin kann nicht herabgestuft werden.');
		}
		users[idx].role = patch.role;
	}
	if (patch.disabled !== undefined) {
		if (patch.disabled) {
			const activeAdmins = users.filter((u) => u.role === 'admin' && !u.disabled);
			if (users[idx].role === 'admin' && !users[idx].disabled && activeAdmins.length <= 1) {
				throw new Error('Der letzte aktive Admin kann nicht deaktiviert werden.');
			}
		}
		users[idx].disabled = patch.disabled;
	}
	if (patch.password !== undefined && patch.password !== '') {
		assertPassword(patch.password);
		const { salt, hash } = hashPassword(patch.password);
		users[idx].salt = salt;
		users[idx].passwordHash = hash;
	}

	saveUsers(users);
	return users[idx];
}

export function removeUser(id: string): void {
	const users = listUsers();
	const next = users.filter((u) => u.id !== id);
	if (next.length === users.length) throw new Error('User nicht gefunden.');
	if (next.filter((u) => u.role === 'admin' && !u.disabled).length === 0) {
		throw new Error('Der letzte aktive Admin kann nicht gelöscht werden.');
	}
	saveUsers(next);
}

export function touchLastLogin(id: string): void {
	const users = listUsers();
	const u = users.find((x) => x.id === id);
	if (!u) return;
	u.lastLoginAt = Date.now();
	saveUsers(users);
}

// ── Views ─────────────────────────────────────────────────────────────────

export function publicUser(u: StoredUser): AppUser {
	return {
		id: u.id,
		username: u.username,
		role: u.role,
		createdAt: u.createdAt,
		lastLoginAt: u.lastLoginAt
	};
}
