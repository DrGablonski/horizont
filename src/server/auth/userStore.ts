// User-Store: Persistenz (JSON) + scrypt-Passwort-Hashing.
//
// Pro Deployment gibt es genau EINEN User; /setup legt ihn an, danach ist
// /setup geschlossen (hasUsers()).
//
// users.json im Datenverzeichnis, atomares Schreiben (tmp + rename).
// Sessions sind rein in-memory (siehe sessionStore.ts) — nach einem
// Container-Neustart sind alle Sessions automatisch ungültig.

import { randomUUID, scryptSync, timingSafeEqual } from 'node:crypto';
import { mkdirSync, readFileSync, writeFileSync, renameSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { DATA_DIR } from '$server/lib/constants';
import type { AppUser } from '$lib/types';

const USERS_FILE = 'users.json';
const SALT_BYTES = 16;
const KEY_BYTES = 64;
const SCRYPT_OPTS = { N: 16384, r: 8, p: 1 };

export interface StoredUser {
	id: string;
	username: string;
	salt: string; // hex
	passwordHash: string; // hex
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

export function createUser(input: { username: string; password: string }): StoredUser {
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
		createdAt: now,
		lastLoginAt: null
	};
	users.push(user);
	saveUsers(users);
	return user;
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
		createdAt: u.createdAt,
		lastLoginAt: u.lastLoginAt
	};
}
