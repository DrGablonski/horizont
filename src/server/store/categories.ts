// Per-User-Kategorie-Verwaltung (Aufgaben-Kategorien, Name + Farbe).
// Kategorien sind reine Server-Metadaten: Tasks referenzieren den Namen im
// CalDAV-Feld CATEGORIES; die Liste liefert die farbige Darstellung.
//
// Persistenz: DATA_DIR/users/{userId}/categories.json (atomares Schreiben).

import { mkdirSync, readFileSync, writeFileSync, renameSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { DATA_DIR } from '$server/lib/constants';
import { DEFAULT_TASK_CATEGORIES, normalizeCategoryName } from '$lib/categories';
import type { TaskCategory } from '$lib/types';

const HEX_RE = /^#[0-9a-fA-F]{6}$/;
const DEFAULT_COLOR = '#64748b';
const MAX_CATEGORIES = 50;

function categoriesPath(userId: string): string {
	const p = join(DATA_DIR, 'users', userId);
	mkdirSync(p, { recursive: true });
	return join(p, 'categories.json');
}

/** Normalisiert eine Rohliste: Namen validiert + eindeutig, Farbe #rrggbb. */
function normalizeList(raw: unknown): TaskCategory[] {
	if (!Array.isArray(raw)) throw new Error('Ungültige Kategorienliste.');
	if (raw.length > MAX_CATEGORIES) throw new Error(`Maximal ${MAX_CATEGORIES} Kategorien.`);
	const out: TaskCategory[] = [];
	const seen = new Set<string>();
	for (const item of raw) {
		if (item == null || typeof item !== 'object') throw new Error('Ungültige Kategorie.');
		const c = item as Partial<TaskCategory>;
		const name = normalizeCategoryName(c.name);
		if (!name) throw new Error('Ungültiger Kategoriename (1–40 Zeichen, ohne Komma/Semikolon).');
		const key = name.toLowerCase();
		if (seen.has(key)) throw new Error(`Doppelter Kategoriename "${name}".`);
		seen.add(key);
		const color = typeof c.color === 'string' && HEX_RE.test(c.color) ? c.color.toLowerCase() : DEFAULT_COLOR;
		out.push({ name, color });
	}
	return out;
}

/** Liest die Kategorien; ohne Datei: Default-Set (Hoch/Schule/Niedrig). */
export function getCategories(userId: string): TaskCategory[] {
	const p = categoriesPath(userId);
	if (!existsSync(p)) return DEFAULT_TASK_CATEGORIES.map((c) => ({ ...c }));
	try {
		const raw = JSON.parse(readFileSync(p, 'utf8')) as { categories?: unknown };
		return normalizeList(raw?.categories);
	} catch {
		return DEFAULT_TASK_CATEGORIES.map((c) => ({ ...c }));
	}
}

/** Speichert die komplette Liste (Ersetzen). */
export function saveCategories(userId: string, input: unknown): TaskCategory[] {
	const categories = normalizeList(input);
	const p = categoriesPath(userId);
	const tmp = `${p}.tmp`;
	writeFileSync(tmp, JSON.stringify({ version: 1, categories }, null, 2), 'utf8');
	renameSync(tmp, p);
	return categories;
}

/** true wenn der Name (case-insensitive) existiert. */
export function hasCategory(userId: string, name: string): boolean {
	const key = name.trim().toLowerCase();
	return getCategories(userId).some((c) => c.name.toLowerCase() === key);
}
