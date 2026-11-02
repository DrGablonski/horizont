// Task-Kategorien: Name + Farbe, verwaltet pro User (Einstellungen).
// Gespeichert wird der Kategoriename im CalDAV-Feld CATEGORIES der VTODO.
// Abwärtskompatibilität: Tasks ohne CATEGORIES, aber mit PRIORITY (1–9)
// werden ihrem Prioritäts-Namen zugeordnet (1–2 Hoch, 3–7 Schule, 8–9 Niedrig).

import type { TaskCategory } from '$lib/types';

export const DEFAULT_TASK_CATEGORIES: TaskCategory[] = [
	{ name: 'Hoch', color: '#dc2626' },
	{ name: 'Schule', color: '#2563eb' },
	{ name: 'Niedrig', color: '#16a34a' }
];

/** Erlaubter Kategoriename: 1–40 Zeichen ohne iCal-Sonderzeichen (Komma, Semikolon, Backslash). */
const NAME_RE = /^[^,;\\]{1,40}$/;

/** Normalisiert/validiert einen Kategoriennamen; null wenn ungültig. */
export function normalizeCategoryName(raw: unknown): string | null {
	if (typeof raw !== 'string') return null;
	const s = raw.trim().replace(/\s+/g, ' ');
	return NAME_RE.test(s) ? s : null;
}

/** Kategoriename aus einer (alten) CalDAV-Priorität ableiten. */
export function priorityToCategoryName(p: number): string {
	if (p <= 2) return 'Hoch';
	if (p >= 8) return 'Niedrig';
	return 'Schule';
}

/** Effektiver Kategoriename eines Tasks: CATEGORIES schlägt PRIORITY. */
export function categoryNameOf(t: { category?: string; priority?: number }): string | null {
	if (t.category) return t.category;
	if (t.priority != null) return priorityToCategoryName(t.priority);
	return null;
}
