// Täglicher Benachrichtigungs-Job (Webhook, z. B. an T3 Code):
// Um die konfigurierte Uhrzeit (pro User, Default 15:00) werden alle
// offenen Tasks mit Priorität „Schule" (priority 5) als Klartext an die
// konfigurierte Webhook-URL POSTet.
//
// In-Prozess-Timer (exakt eine Instanz pro Deployment, siehe
// docker-compose.yml): Alle 60 s wird geprüft, ob bei einem User die
// konfigurierte Zeit vergangen und heute noch nicht gelaufen ist. Der
// Lauf-Status (DATA_DIR/system/notify-runs.json) ist persistiert — ein
// Neustart NACH der konfigurierten Zeit führt zu einem Nachhol-Lauf.
// Fehlgeschlagene Läufe werden alle 10 Minuten wiederholt, bis sie
// erfolgreich sind oder der Tag vorbei ist.

import { listUsers } from '$server/auth/userStore';
import { listConnections } from '$server/store/connections';
import { getNotify, getRun, setRun } from '$server/store/notify';
import { listAllTasks } from '$server/lib/write';
import type { NotifyConfig, TaskItem } from '$lib/types';

const TICK_MS = 60_000;
const POST_TIMEOUT_MS = 15_000;
const ERROR_RETRY_MS = 10 * 60_000;
// Priorität „Schule" (siehe TaskEditor: 9=Niedrig, 5=Schule, 1=Hoch).
const SCHOOL_PRIORITY = 5;

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

function dueAt(cfgTime: string, now: Date): Date {
	const [h, m] = cfgTime.split(':').map(Number);
	const t = new Date(now);
	t.setHours(h, m, 0, 0);
	return t;
}

// ── Tick ───────────────────────────────────────────────────────────────────

async function tick(): Promise<void> {
	if (running) return;
	running = true;
	try {
		const now = new Date();
		const today = dateKey(now);
		for (const user of listUsers()) {
			if (user.disabled) continue;
			const cfg = getNotify(user.id);
			if (!cfg || !cfg.enabled || !cfg.webhookUrl) continue;
			if (now < dueAt(cfg.time, now)) continue; // noch zu früh
			const run = getRun(user.id);
			if (run?.date === today) {
				if (run.status === 'error') {
					// Fehler-Lauf: alle 10 Minuten erneut versuchen.
					if (run.at != null && now.getTime() - run.at < ERROR_RETRY_MS) continue;
				} else {
					continue; // ok/skipped: maximal 1× pro Tag
				}
			}
			await runForUser(user.id, cfg, now, today);
		}
	} catch (e) {
		console.error('[notify]', e instanceof Error ? e.message : e);
	} finally {
		running = false;
	}
}

async function runForUser(userId: string, cfg: NotifyConfig, now: Date, today: string): Promise<void> {
	try {
		const connections = listConnections(userId);
		if (connections.length === 0) {
			setRun(userId, { date: today, status: 'skipped', error: 'Keine CalDAV-Verbindung' });
			return;
		}
		const tasks = await listAllTasks(connections);
		const open = tasks.filter((t) => !t.completed && t.priority === SCHOOL_PRIORITY);
		if (open.length === 0) {
			// Keine offenen Schul-Tasks → keine Nachricht (keinerlei Spam).
			setRun(userId, { date: today, status: 'skipped', error: 'Keine offenen Schul-Tasks' });
			return;
		}
		const body = formatNotifyMessage(open, now);
		const res = await postNotify(cfg.webhookUrl, body, today);
		if (!res.ok) throw new Error(`Webhook hat ${res.status} geantwortet`);
		setRun(userId, { date: today, status: 'ok' });
	} catch (e) {
		const msg = e instanceof Error ? e.message : String(e);
		console.error(`[notify] user ${userId}: ${msg}`);
		setRun(userId, { date: today, status: 'error', error: msg, at: Date.now() });
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

/** Klartext-Nachricht im Format, das T3 Code per {{body}} rendert. */
export function formatNotifyMessage(tasks: TaskItem[], now: Date): string {
	const sorted = [...tasks].sort((a, b) => taskDueMs(a) - taskDueMs(b));
	const lines = sorted.map((t, i) => {
		const due = t.dueKey ?? (t.dueMs != null ? dueMsLabel(t.dueMs) : undefined);
		return `${i + 1}. ${t.summary}${due ? ` — Fällig: ${due}` : ''}`;
	});
	const stamp = `${dateKey(now)}, ${pad2(now.getHours())}:${pad2(now.getMinutes())}`;
	return `Offene Schul-Tasks — Stand ${stamp} (${tasks.length} offen):\n\n${lines.join('\n')}`;
}

export async function postNotify(url: string, body: string, runDate: string): Promise<Response> {
	// x-run-date: erlaubt in T3 Code Dedupe per replayKey {{headers.x-run-date}}
	// (zweite Sendung am selben Tag wird dort als „duplicate" erkannt).
	return fetch(url, {
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
