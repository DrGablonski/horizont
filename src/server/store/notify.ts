// Per-User-Webhook-Config (Tasks-Benachrichtigung):
// Je nach gewählter Automatisierung (frequency) werden offene Tasks mit den
// eingestellten Kategorien automatisch an die Webhook-URL gesendet —
// nie (manual), täglich (daily), wöchentlich (weekly) oder alle N Stunden
// (interval). Manuell senden kann der Nutzer jederzeit über „Jetzt senden".
//
// Persistenz: DATA_DIR/users/{userId}/notify.json (atomares Schreiben).
// Lauf-Status: DATA_DIR/system/notify-runs.json (letzter Lauf pro User).

import { mkdirSync, readFileSync, writeFileSync, renameSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { DATA_DIR } from '$server/lib/constants';
import { normalizeCategoryName, priorityToCategoryName } from '$lib/categories';
import type { NotifyConfig, NotifyConfigView, NotifyFrequency, NotifyLastRun } from '$lib/types';

const TIME_RE = /^([01]?\d|2[0-3]):([0-5]\d)$/;
const DEFAULT_TIME = '15:00';
/** Wochentag für weekly: 0=Mo … 6=So (Standard: Montag). */
const DEFAULT_WEEKDAY = 0;
/** Abstand für interval in Stunden (Standard: alle 6 Stunden). */
const DEFAULT_INTERVAL_HOURS = 6;
const FREQUENCIES: NotifyFrequency[] = ['manual', 'daily', 'weekly', 'interval'];
/** Standard-Template: {{body}} = Task-Liste, {{stand}} = Datum/Uhrzeit + Anzahl. */
export const DEFAULT_NOTIFY_PROMPT = 'Offene Aufgaben — Stand {{stand}}:\n\n{{body}}';
/** Standard: nur Kategorie „Schule" (wie früher Priorität 5). */
const DEFAULT_NOTIFY_CATEGORIES = ['Schule'];
const MAX_PROMPT_LEN = 4000;
const MAX_TOKEN_LEN = 512;

/** Vollständige Webhook-URL aus Basis-URL + Token zusammensetzen. */
export function webhookUrlOf(cfg: Pick<NotifyConfig, 'url' | 'token'>): string {
	return `${cfg.url.replace(/\/+$/, '')}/${cfg.token}`;
}

/**
 * Vollständige Webhook-URL (z. B. aus dem Empfänger-Dienst kopiert) in Basis-URL
 * und Token aufteilen — der Token ist das letzte Pfadsegment.
 */
export function splitWebhookUrl(full: string): { url: string; token: string } | null {
	const t = full.trim().replace(/\/+$/, '');
	const i = t.lastIndexOf('/');
	if (i <= 0) return null;
	return { url: t.slice(0, i), token: t.slice(i + 1) };
}

// ── Config ─────────────────────────────────────────────────────────────────

function notifyPath(userId: string): string {
	const p = join(DATA_DIR, 'users', userId);
	mkdirSync(p, { recursive: true });
	return join(p, 'notify.json');
}

/**
 * Liest die Config und normalisiert sie auf das aktuelle Format.
 * Alte Configs mit einer einzigen `webhookUrl` werden dabei in
 * `url` + `token` aufgeteilt (Token = letztes Pfadsegment); fehlende
 * `categories` werden aus alten `priorities` migriert oder fallen auf
 * Standard „Schule" zurück. Fehlende `frequency` wird aus dem alten
 * `enabled` abgeleitet (true ⇒ 'daily', false ⇒ 'manual').
 */
/** Kategoriennamen normalisieren: gültige Namen, dedupliziert (case-insensitive). */
function normalizeNotifyCategories(v: unknown): string[] | null {
	if (!Array.isArray(v)) return null;
	const out: string[] = [];
	const seen = new Set<string>();
	for (const item of v) {
		const name = normalizeCategoryName(item);
		if (!name) continue;
		const key = name.toLowerCase();
		if (seen.has(key)) continue;
		seen.add(key);
		out.push(name);
	}
	return out;
}

/** Alte Configs: Prioritäts-Buckets → Kategorienamen (1→Hoch, 5→Schule, 9→Niedrig). */
function migratePriorities(v: unknown): string[] | null {
	if (!Array.isArray(v)) return null;
	const out: string[] = [];
	for (const p of v) {
		const n = Number(p);
		if (n >= 1 && n <= 9) {
			const name = priorityToCategoryName(n);
			if (!out.includes(name)) out.push(name);
		}
	}
	return out.length > 0 ? out : null;
}

export function getNotify(userId: string): NotifyConfig | null {
	const p = notifyPath(userId);
	if (!existsSync(p)) return null;
	try {
		const raw = JSON.parse(readFileSync(p, 'utf8')) as { config?: unknown };
		const c = raw?.config;
		if (c == null || typeof c !== 'object') return null;
		const cfg = c as Partial<NotifyConfig> & { webhookUrl?: unknown; priorities?: unknown };
		if (typeof cfg.time !== 'string') return null;
		if (typeof cfg.enabled !== 'boolean' && typeof cfg.frequency !== 'string') return null;

		// Migration: fehlende frequency aus dem alten enabled ableiten.
		const frequency: NotifyFrequency = FREQUENCIES.includes(cfg.frequency as NotifyFrequency)
			? (cfg.frequency as NotifyFrequency)
			: cfg.enabled
				? 'daily'
				: 'manual';

		const weekday =
			typeof cfg.weekday === 'number' && Number.isInteger(cfg.weekday) && cfg.weekday >= 0 && cfg.weekday <= 6
				? cfg.weekday
				: DEFAULT_WEEKDAY;
		const intervalHours =
			typeof cfg.intervalHours === 'number' &&
			Number.isInteger(cfg.intervalHours) &&
			cfg.intervalHours >= 1 &&
			cfg.intervalHours <= 23
				? cfg.intervalHours
				: DEFAULT_INTERVAL_HOURS;

		let url = typeof cfg.url === 'string' ? cfg.url : '';
		let token = typeof cfg.token === 'string' ? cfg.token : '';
		if (!url && !token && typeof cfg.webhookUrl === 'string' && cfg.webhookUrl.trim() !== '') {
			const split = splitWebhookUrl(cfg.webhookUrl);
			if (split) {
				url = split.url;
				token = split.token;
			}
		}
		return {
			enabled: frequency !== 'manual',
			frequency,
			time: cfg.time,
			weekday,
			intervalHours,
			url,
			token,
			prompt: typeof cfg.prompt === 'string' && cfg.prompt !== '' ? cfg.prompt : DEFAULT_NOTIFY_PROMPT,
			categories:
				normalizeNotifyCategories(cfg.categories) ??
				migratePriorities(cfg.priorities) ??
				[...DEFAULT_NOTIFY_CATEGORIES]
		};
	} catch {
		return null;
	}
}

function validateUrl(u: string): string {
	let parsed: URL;
	try {
		parsed = new URL(u);
	} catch {
		throw new Error('Ungültige Webhook-URL.');
	}
	if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') {
		throw new Error('Webhook-URL muss eine http(s)-URL sein.');
	}
	return u;
}

export function saveNotify(
	userId: string,
	input: {
		frequency: NotifyFrequency;
		time: string;
		weekday?: number;
		intervalHours?: number;
		url?: string;
		token?: string;
		prompt?: string;
		categories?: string[];
	}
): NotifyConfig {
	const rawTime = (input.time ?? '').trim();
	if (!TIME_RE.test(rawTime)) throw new Error('Ungültige Uhrzeit (Format: HH:MM, z. B. 15:00).');
	const [h, m] = rawTime.split(':');
	const time = `${h.padStart(2, '0')}:${m}`;

	if (!FREQUENCIES.includes(input.frequency)) {
		throw new Error('Ungültige Automatisierung (manual, daily, weekly oder interval).');
	}

	const current =
		getNotify(userId) ??
		{
			enabled: false,
			frequency: 'manual' as NotifyFrequency,
			time: DEFAULT_TIME,
			weekday: DEFAULT_WEEKDAY,
			intervalHours: DEFAULT_INTERVAL_HOURS,
			url: '',
			token: '',
			prompt: DEFAULT_NOTIFY_PROMPT,
			categories: [...DEFAULT_NOTIFY_CATEGORIES]
		};

	// Wochentag (0=Mo … 6=So) und Stunden-Abstand (1–23): fehlend = behalten.
	let weekday = current.weekday;
	if (input.weekday !== undefined) {
		if (!Number.isInteger(input.weekday) || input.weekday < 0 || input.weekday > 6) {
			throw new Error('Ungültiger Wochentag (0=Mo … 6=So).');
		}
		weekday = input.weekday;
	}
	let intervalHours = current.intervalHours;
	if (input.intervalHours !== undefined) {
		if (!Number.isInteger(input.intervalHours) || input.intervalHours < 1 || input.intervalHours > 23) {
			throw new Error('Ungültiger Stunden-Abstand (1–23).');
		}
		intervalHours = input.intervalHours;
	}

	// Leere Eingaben → gespeicherten Wert beibehalten (wie bei Passwörtern).
	let url = current.url;
	if (typeof input.url === 'string' && input.url.trim() !== '') {
		url = validateUrl(input.url.trim()).replace(/\/+$/, '');
	}

	let token = current.token;
	if (typeof input.token === 'string' && input.token.trim() !== '') {
		const t = input.token.trim();
		if (t.length > MAX_TOKEN_LEN) throw new Error('Token ist zu lang.');
		token = t;
	}

	let prompt = current.prompt;
	if (typeof input.prompt === 'string' && input.prompt.trim() !== '') {
		if (input.prompt.length > MAX_PROMPT_LEN) throw new Error('Prompt ist zu lang.');
		prompt = input.prompt;
	}

	// Kategorien: fehlend → gespeichert behalten; sonst validieren (mindestens einer).
	let categories = current.categories;
	if (Array.isArray(input.categories)) {
		const valid = normalizeNotifyCategories(input.categories) ?? [];
		if (valid.length === 0) throw new Error('Bitte mindestens eine Kategorie auswählen.');
		categories = valid;
	}

	const config: NotifyConfig = {
		enabled: input.frequency !== 'manual',
		frequency: input.frequency,
		time,
		weekday,
		intervalHours,
		url,
		token,
		prompt,
		categories
	};
	const p = notifyPath(userId);
	const tmp = `${p}.tmp`;
	writeFileSync(tmp, JSON.stringify({ version: 2, config }, null, 2), 'utf8');
	renameSync(tmp, p);
	return config;
}

export function getNotifyView(userId: string): NotifyConfigView {
	const c = getNotify(userId);
	const lastRun = getRun(userId);
	if (!c) {
		return {
			frequency: 'manual',
			time: DEFAULT_TIME,
			weekday: DEFAULT_WEEKDAY,
			intervalHours: DEFAULT_INTERVAL_HOURS,
			url: null,
			hasToken: false,
			prompt: DEFAULT_NOTIFY_PROMPT,
			categories: [...DEFAULT_NOTIFY_CATEGORIES],
			lastRun
		};
	}
	return {
		frequency: c.frequency,
		time: c.time,
		weekday: c.weekday,
		intervalHours: c.intervalHours,
		url: c.url || null,
		hasToken: Boolean(c.token),
		prompt: c.prompt,
		categories: c.categories,
		lastRun
	};
}

// ── Lauf-Status ────────────────────────────────────────────────────────────

const RUNS_FILE = 'system/notify-runs.json';

function runsPath(): string {
	mkdirSync(join(DATA_DIR, 'system'), { recursive: true });
	return join(DATA_DIR, RUNS_FILE);
}

function readRuns(): Record<string, NotifyLastRun> {
	const p = runsPath();
	if (!existsSync(p)) return {};
	try {
		const raw = JSON.parse(readFileSync(p, 'utf8')) as { runs?: unknown };
		if (raw == null || typeof raw !== 'object' || raw.runs == null || typeof raw.runs !== 'object') {
			return {};
		}
		return raw.runs as Record<string, NotifyLastRun>;
	} catch {
		return {};
	}
}

export function getRuns(): Record<string, NotifyLastRun> {
	return readRuns();
}

export function getRun(userId: string): NotifyLastRun | null {
	return readRuns()[userId] ?? null;
}

export function setRun(userId: string, run: NotifyLastRun): void {
	const runs = readRuns();
	runs[userId] = run;
	const p = runsPath();
	const tmp = `${p}.tmp`;
	writeFileSync(tmp, JSON.stringify({ version: 1, runs }, null, 2), 'utf8');
	renameSync(tmp, p);
}
