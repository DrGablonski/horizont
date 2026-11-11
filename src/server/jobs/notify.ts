// Benachrichtigungs-Job (Webhook): offene Tasks mit den eingestellten
// Kategorien werden je nach Automatisierung (cfg.frequency) automatisch an
// die konfigurierte Webhook-URL POSTet:
//   manual   → nie automatisch (nur „Jetzt senden" / POST /api/notify/send)
//   daily    → einmal täglich ab der konfigurierten Uhrzeit (cfg.time)
//   weekly   → einmal wöchentlich am gewählten Wochentag (cfg.weekday) um cfg.time
//   interval → alle cfg.intervalHours Stunden (zeitbasiert über letzten Lauf)
//
// In-Prozess-Timer (exakt eine Instanz pro Deployment, siehe
// docker-compose.yml): Alle 60 s wird geprüft, ob bei einem User ein Lauf
// fällig ist. Der Lauf-Status (DATA_DIR/system/notify-runs.json) ist
// persistiert — ein Neustart nach der Fälligkeit führt zu einem Nachhol-Lauf.
// daily/weekly dedupen datumsbasiert (weekly über die Wochen-Montags-Kette),
// interval über den at-Zeitstempel des letzten Laufs. Fehlgeschlagene Läufe
// werden alle 10 Minuten wiederholt.

import { listUsers } from '$server/auth/userStore';
import { listConnections } from '$server/store/connections';
import { DEFAULT_NOTIFY_PROMPT, getNotify, getRun, setRun, webhookUrlOf } from '$server/store/notify';
import { listAllTasks } from '$server/lib/write';
import { guardedFetch } from '$server/lib/urlGuard';
import { categoryNameOf } from '$lib/categories';
import type { NotifyConfig, NotifySendResult, TaskItem } from '$lib/types';

const TICK_MS = 60_000;
const POST_TIMEOUT_MS = 15_000;
const ERROR_RETRY_MS = 10 * 60_000;

let timer: ReturnType<typeof setInterval> | null = null;
let running = false;

/** Startet den Timer genau einmal (wird aus hooks.server.ts aufgerufen). */
export function startNotifyJob(): void {
	if (timer) return;
	timer = setInterval(() => {
		void tick();
	}, TICK_MS);
	timer.unref?.();
	void tick(); // beim Start: überfällige Läufe nachholen
}

// ── Zeit-Helfer ────────────────────────────────────────────────────────────

function pad2(n: number): string {
	return String(n).padStart(2, '0');
}

/** Lokales Datum als YYYY-MM-DD. */
export function dateKey(d: Date): string {
	return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}`;
}

/** Wochentag wie in der Config: 0=Mo … 6=So (JS-getDay: 0=So … 6=Sa). */
function weekdayOf(d: Date): number {
	return (d.getDay() + 6) % 7;
}

/** Dedupe-Schlüssel für weekly: YYYY-MM-DD des Montags der Woche von d. */
function weekKey(d: Date): string {
	const mon = new Date(d);
	mon.setDate(mon.getDate() - weekdayOf(d));
	return dateKey(mon);
}

function dueAt(cfgTime: string, now: Date): Date {
	const [h, m] = cfgTime.split(':').map(Number);
	const t = new Date(now);
	t.setHours(h, m, 0, 0);
	return t;
}

/**
 * Fehler-Lauf? Dann alle 10 Minuten erneut versuchen; ok/skipped → nicht
 * erneut (Dedupe für das laufende Zeitfenster ist bereits geprüft).
 */
function retryError(run: { status: string; at?: number } | null, now: Date): boolean {
	return run?.status === 'error' && (run.at == null || now.getTime() - run.at >= ERROR_RETRY_MS);
}

// ── Tick ───────────────────────────────────────────────────────────────────

async function tick(): Promise<void> {
	if (running) return;
	running = true;
	try {
		const now = new Date();
		const today = dateKey(now);
		for (const user of listUsers()) {
			const cfg = getNotify(user.id);
			if (!cfg || cfg.frequency === 'manual' || !cfg.url || !cfg.token) continue;
			const run = getRun(user.id);

			if (cfg.frequency === 'daily') {
				if (now < dueAt(cfg.time, now)) continue; // noch zu früh
				if (run?.date === today && !retryError(run, now)) continue;
			} else if (cfg.frequency === 'weekly') {
				if (weekdayOf(now) !== cfg.weekday) continue; // heute nicht dran
				if (now < dueAt(cfg.time, now)) continue; // noch zu früh
				const wk = weekKey(now);
				if (run?.weekKey === wk && !retryError(run, now)) continue;
			} else if (cfg.frequency === 'interval') {
				// Zeitbasiert: letzter Lauf (at) + Abstand; Fehler erneut nach 10 min.
				if (run?.at != null) {
					const waitMs = run.status === 'error' ? ERROR_RETRY_MS : cfg.intervalHours * 3_600_000;
					if (now.getTime() - run.at < waitMs) continue;
				}
			} else {
				continue; // unbekannte frequency: nichts tun
			}

			await sendMessageForUser(user.id, cfg, now);
		}
	} catch (e) {
		console.error('[notify]', e instanceof Error ? e.message : e);
	} finally {
		running = false;
	}
}

// ── Versand (Job + manueller Trigger /api/notify/send) ─────────────────────

/**
 * Sendet die aktuelle Task-Nachricht wirklich und aktualisiert den
 * Lauf-Status — wird für den manuellen Trigger genau so verwendet wie für
 * den Timer (unabhängig von der frequency-Einstellung).
 */
export async function sendMessageForUser(userId: string, cfg: NotifyConfig, now: Date): Promise<NotifySendResult> {
	const today = dateKey(now);
	const week = cfg.frequency === 'weekly' ? weekKey(now) : undefined;
	try {
		const connections = listConnections(userId);
		if (connections.length === 0) {
			setRun(userId, { date: today, weekKey: week, status: 'skipped', error: 'Keine CalDAV-Verbindung', at: Date.now() });
			return { ok: false, skipped: true, error: 'Keine CalDAV-Verbindung' };
		}
		const tasks = await listAllTasks(userId, connections);
		const open = tasks.filter(
			(t) => {
				const cat = categoryNameOf(t);
				return !t.completed && cat != null && cfg.categories.includes(cat);
			}
		);
		if (open.length === 0) {
			// Keine offenen Tasks mit den gewählten Kategorien → keine Nachricht (keinerlei Spam).
			setRun(userId, {
				date: today,
				weekKey: week,
				status: 'skipped',
				error: 'Keine offenen Tasks (gewählte Kategorien)',
				at: Date.now()
			});
			return { ok: false, skipped: true, error: 'Keine offenen Tasks in den gewählten Kategorien.' };
		}
		const text = composeMessage(cfg.prompt || DEFAULT_NOTIFY_PROMPT, open, now);
		const res = await postNotify(webhookUrlOf(cfg), text, today);
		if (!res.ok) throw new Error(`Webhook hat ${res.status} geantwortet`);
		setRun(userId, { date: today, weekKey: week, status: 'ok', at: Date.now() });
		return { ok: true, status: res.status, outcome: res.headers.get('x-t3-hook-outcome') ?? undefined };
	} catch (e) {
		const msg = e instanceof Error ? e.message : String(e);
		console.error(`[notify] user ${userId}: ${msg}`);
		setRun(userId, { date: today, weekKey: week, status: 'error', error: msg, at: Date.now() });
		return { ok: false, error: msg };
	}
}

// ── Nachricht & Versand (auch für den Test-Button wiederverwendet) ────────

function taskDueMs(t: TaskItem): number {
	if (t.dueMs != null) return t.dueMs;
	if (t.dueKey) {
		const ms = Date.parse(`${t.dueKey}T12:00:00`);
		if (!Number.isNaN(ms)) return ms;
	}
	return Infinity;
}

function dueMsLabel(ms: number): string {
	const d = new Date(ms);
	if (d.getHours() === 0 && d.getMinutes() === 0) return dateKey(d);
	return `${dateKey(d)} ${pad2(d.getHours())}:${pad2(d.getMinutes())}`;
}

/** Nummerierte Task-Liste (ersetzt {{body}} im Prompt-Template). */
export function formatTaskList(tasks: TaskItem[]): string {
	const sorted = [...tasks].sort((a, b) => taskDueMs(a) - taskDueMs(b));
	return sorted
		.map((t, i) => {
			const due = t.dueKey ?? (t.dueMs != null ? dueMsLabel(t.dueMs) : undefined);
			return `${i + 1}. ${t.summary}${due ? ` — Fällig: ${due}` : ''}`;
		})
		.join('\n');
}

/** Ersetzt die Platzhalter im Template: {{body}} = Liste, {{stand}} = Zeitstempel. */
export function renderPrompt(template: string, body: string, stand: string): string {
	return template.replaceAll('{{body}}', body).replaceAll('{{stand}}', stand);
}

/** Fertige Nachricht aus Template + Tasks (Job und Test-Endpunkt). */
export function composeMessage(template: string, tasks: TaskItem[], now: Date): string {
	const body = formatTaskList(tasks);
	const stand = `${dateKey(now)}, ${pad2(now.getHours())}:${pad2(now.getMinutes())} (${tasks.length} offen)`;
	return renderPrompt(template, body, stand);
}

export async function postNotify(url: string, body: string, runDate: string): Promise<Response> {
	// x-run-date: erlaubt Dedupe beim Empfänger (z. B. Replay-Key aus
	// {{headers.x-run-date}} — eine zweite Sendung am selben Tag wird dort als
	// „duplicate" erkannt).
	// guardedFetch: SSRF-Schutz (nur http(s), keine internen/gesperrten Ziele,
	// Redirect-Zwischenstufen werden ebenfalls geprüft).
	return guardedFetch(url, 'Webhook-URL', {
		method: 'POST',
		headers: {
			'content-type': 'text/plain; charset=utf-8',
			'x-run-date': runDate,
			'user-agent': 'Horizont-Notify/1'
		},
		body,
		signal: AbortSignal.timeout(POST_TIMEOUT_MS)
	});
}
