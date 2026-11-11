// Per-User-Kalender-Präferenzen (Sichtbarkeit, Farbe, Schreibschutz, Standard, Sortierung).
// Präferenzen sind reine Server-Metadaten zu fernen Kalendern: sie ändern nichts
// am CalDAV-Server, sondern nur die Darstellung in Horizont.
//
// Persistenz: DATA_DIR/users/{userId}/calendar-prefs.json (atomares Schreiben).

import { mkdirSync, readFileSync, writeFileSync, renameSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { DATA_DIR } from '$server/lib/constants';
import { invalidatePanelCache } from '$server/lib/panelCache';
import type { CalendarPref } from '$lib/types';

const HEX_RE = /^#[0-9a-fA-F]{6}$/;

function prefsPath(userId: string): string {
	const p = join(DATA_DIR, 'users', userId);
	mkdirSync(p, { recursive: true });
	return join(p, 'calendar-prefs.json');
}

/** Baut aus einem Rohwert einen sauberen Eintrag: nur bekannte Felder, defensiv geprüft; leer ⇒ null. */
function normalizePref(raw: unknown): CalendarPref | null {
	if (raw == null || typeof raw !== 'object' || Array.isArray(raw)) return null;
	const c = raw as Record<string, unknown>;
	const out: CalendarPref = {};
	if (typeof c.hidden === 'boolean') out.hidden = c.hidden;
	if (typeof c.writeDisabled === 'boolean') out.writeDisabled = c.writeDisabled;
	if (typeof c.isDefault === 'boolean') out.isDefault = c.isDefault;
	if (typeof c.order === 'number' && Number.isFinite(c.order)) out.order = c.order;
	if (typeof c.color === 'string' && HEX_RE.test(c.color)) out.color = c.color.toLowerCase();
	const name = typeof c.name === 'string' ? c.name.trim() : '';
	if (name) out.name = name.slice(0, 80);
	return Object.keys(out).length === 0 ? null : out;
}

/** Baut aus einem Rohwert die Präferenz-Map: unbekannte Felder verwerfen, leere Einträge entfernen. */
function normalizePrefs(raw: unknown): Record<string, CalendarPref> {
	if (raw == null || typeof raw !== 'object' || Array.isArray(raw)) return {};
	const out: Record<string, CalendarPref> = {};
	for (const [id, value] of Object.entries(raw as Record<string, unknown>)) {
		if (!id) continue;
		const pref = normalizePref(value);
		if (pref) out[id] = pref;
	}
	return out;
}

/** Liest alle Präferenzen; ohne Datei oder bei defektem JSON: leeres Objekt. */
export function getCalendarPrefs(userId: string): Record<string, CalendarPref> {
	const p = prefsPath(userId);
	if (!existsSync(p)) return {};
	try {
		const raw = JSON.parse(readFileSync(p, 'utf8')) as { prefs?: unknown };
		return normalizePrefs(raw?.prefs);
	} catch {
		return {};
	}
}

/** Speichert die komplette Präferenz-Map (Ersetzen, normalisiert). */
export function setCalendarPrefs(userId: string, prefs: Record<string, CalendarPref>): void {
	const p = prefsPath(userId);
	const tmp = `${p}.tmp`;
	writeFileSync(tmp, JSON.stringify({ version: 1, prefs: normalizePrefs(prefs) }, null, 2), 'utf8');
	renameSync(tmp, p);
}

/** Patcht (oder löscht bei null) einen Kalender-Eintrag; leere Objekte werden entfernt. Invalidiert den Panel-Cache. */
export function updateCalendarPref(userId: string, calendarId: string, patch: Partial<CalendarPref> | null): Record<string, CalendarPref> {
	const prefs = getCalendarPrefs(userId);
	if (patch === null) {
		delete prefs[calendarId];
	} else {
		const merged: Record<string, unknown> = { ...prefs[calendarId] };
		for (const [key, value] of Object.entries(patch)) {
			if (value === undefined) delete merged[key];
			else merged[key] = value;
		}
		const clean = normalizePref(merged);
		if (clean) prefs[calendarId] = clean;
		else delete prefs[calendarId];
	}
	const saved = normalizePrefs(prefs);
	setCalendarPrefs(userId, saved);
	invalidatePanelCache();
	return saved;
}

/** Setzt (oder löscht bei null) den Standardkalender; entwertet alle anderen isDefault. Invalidiert den Panel-Cache. */
export function setDefaultCalendar(userId: string, calendarId: string | null): Record<string, CalendarPref> {
	const prefs = getCalendarPrefs(userId);
	// Bisherige Standardeinträge entwerten (fehlendes Feld = nicht Standard); leere Überreste entfallen unten.
	for (const [id, pref] of Object.entries(prefs)) {
		if (!pref?.isDefault) continue;
		const next = { ...pref };
		delete next.isDefault;
		prefs[id] = next;
	}
	if (calendarId !== null) {
		prefs[calendarId] = { ...prefs[calendarId], isDefault: true };
	}
	const saved = normalizePrefs(prefs);
	setCalendarPrefs(userId, saved);
	invalidatePanelCache();
	return saved;
}

/** Id des aktuellen Standardkalenders, sonst null. */
export function getDefaultCalendarId(userId: string): string | null {
	const prefs = getCalendarPrefs(userId);
	for (const [id, pref] of Object.entries(prefs)) {
		if (pref?.isDefault) return id;
	}
	return null;
}
