// Per-User-Webhook-Config (Tägliche-Schul-Tasks-Benachrichtigung):
// Um die konfigurierte Uhrzeit werden alle offenen Tasks mit Priorität
// „Schule" (priority 5) als POST an die Webhook-URL (z. B. T3 Code) gesendet.
//
// Persistenz: DATA_DIR/users/{userId}/notify.json (atomares Schreiben).
// Lauf-Status: DATA_DIR/system/notify-runs.json (letzter Lauf pro User).

import { mkdirSync, readFileSync, writeFileSync, renameSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { DATA_DIR } from '$server/lib/constants';
import type { NotifyConfig, NotifyConfigView, NotifyLastRun } from '$lib/types';

const TIME_RE = /^([01]?\d|2[0-3]):([0-5]\d)$/;
const DEFAULT_TIME = '15:00';

// ── Config ─────────────────────────────────────────────────────────────────

function notifyPath(userId: string): string {
	const p = join(DATA_DIR, 'users', userId);
	mkdirSync(p, { recursive: true });
	return join(p, 'notify.json');
}

/** Config ohne Webhook-URL ist ungültig für den Job; leer = nicht gesetzt. */
export function getNotify(userId: string): NotifyConfig | null {
	const p = notifyPath(userId);
	if (!existsSync(p)) return null;
	try {
		const raw = JSON.parse(readFileSync(p, 'utf8')) as { config?: unknown };
		const c = raw?.config;
		if (c == null || typeof c !== 'object') return null;
		const cfg = c as Partial<NotifyConfig>;
		if (typeof cfg.enabled !== 'boolean' || typeof cfg.time !== 'string') return null;
		return {
			enabled: cfg.enabled,
			time: cfg.time,
			webhookUrl: typeof cfg.webhookUrl === 'string' ? cfg.webhookUrl : ''
		};
	} catch {
		return null;
	}
}

export function saveNotify(
	userId: string,
	input: { enabled: boolean; time: string; webhookUrl?: string }
): NotifyConfig {
	const rawTime = (input.time ?? '').trim();
	if (!TIME_RE.test(rawTime)) throw new Error('Ungültige Uhrzeit (Format: HH:MM, z. B. 15:00).');
	const [h, m] = rawTime.split(':');
	const time = `${h.padStart(2, '0')}:${m}`;

	const current = getNotify(userId) ?? { enabled: false, time: DEFAULT_TIME, webhookUrl: '' };
	let webhookUrl = current.webhookUrl;
	if (input.webhookUrl !== undefined) {
		const u = input.webhookUrl.trim().replace(/\/+$/, '');
		if (u !== '') {
			// Leere Eingabe → gespeicherte URL beibehalten (wie bei Passwörtern).
			let parsed: URL;
			try {
				parsed = new URL(u);
			} catch {
				throw new Error('Ungültige Webhook-URL.');
			}
			if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') {
				throw new Error('Webhook-URL muss eine http(s)-URL sein.');
			}
			webhookUrl = u;
		}
	}

	const config: NotifyConfig = { enabled: Boolean(input.enabled), time, webhookUrl };
	const p = notifyPath(userId);
	const tmp = `${p}.tmp`;
	writeFileSync(tmp, JSON.stringify({ version: 1, config }, null, 2), 'utf8');
	renameSync(tmp, p);
	return config;
}

/** Maskiert das letzte Pfadsegment (den Token) der Webhook-URL. */
export function maskWebhookUrl(raw: string): string {
	try {
		const u = new URL(raw);
		const segs = u.pathname.split('/').filter(Boolean);
		if (segs.length > 0) segs[segs.length - 1] = '••••';
		return `${u.protocol}//${u.host}${segs.length > 0 ? '/' + segs.join('/') : ''}`;
	} catch {
		return raw.slice(0, 40) + '…';
	}
}

export function getNotifyView(userId: string): NotifyConfigView {
	const c = getNotify(userId);
	const lastRun = getRun(userId);
	if (!c) {
		return { enabled: false, time: DEFAULT_TIME, hasWebhookUrl: false, webhookUrlMasked: null, lastRun };
	}
	return {
		enabled: c.enabled,
		time: c.time,
		hasWebhookUrl: Boolean(c.webhookUrl),
		webhookUrlMasked: c.webhookUrl ? maskWebhookUrl(c.webhookUrl) : null,
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
