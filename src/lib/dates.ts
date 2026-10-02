// Isomorphe Datums-Helfer (Browser + Node). Alle Funktionen sind deterministisch
// und nutzen die lokale Zeitzone des Prozesses (im Container: Europe/Berlin).

export function startOfDayMs(ms: number): number {
	const d = new Date(ms);
	d.setHours(0, 0, 0, 0);
	return d.getTime();
}

/** Tage zu/von einem lokalen Mitternacht-Zeitpunkt verschieben (DST-sicher). */
export function addDaysMs(ms: number, days: number): number {
	const d = new Date(ms);
	d.setDate(d.getDate() + days);
	d.setHours(0, 0, 0, 0);
	return d.getTime();
}

/** Lokaler Tages-Schlüssel YYYY-MM-DD. */
export function dayKey(ms: number): string {
	const d = new Date(ms);
	const y = d.getFullYear();
	const m = String(d.getMonth() + 1).padStart(2, '0');
	const dd = String(d.getDate()).padStart(2, '0');
	return `${y}-${m}-${dd}`;
}

export function todayKey(): string {
	return dayKey(Date.now());
}

/** Lokale Mitternacht für einen Tages-Schlüssel. */
export function msFromKey(key: string): number {
	const [y, m, d] = key.split('-').map(Number);
	return new Date(y, m - 1, d).getTime();
}

export function shiftDayKey(key: string, days: number): string {
	return dayKey(addDaysMs(msFromKey(key), days));
}

export function nextDayKey(key: string): string {
	return shiftDayKey(key, 1);
}

/**
 * Alle lokalen Tages-Schlüssel in [startMs, endMsExcl), aufsteigend.
 * `endMs` ist exklusiv. Start wird auf lokale Mitternacht normalisiert.
 */
export function dayKeysBetween(startMs: number, endMsExcl: number): string[] {
	const keys: string[] = [];
	let cur = startOfDayMs(startMs);
	while (cur < endMsExcl) {
		keys.push(dayKey(cur));
		cur = addDaysMs(cur, 1);
	}
	return keys;
}

// ── Labels (Deutsch) ──────────────────────────────────────────────────────

const WEEKDAYS_SHORT = ['So', 'Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa'];
const MONTHS_SHORT = [
	'Jan',
	'Feb',
	'Mär',
	'Apr',
	'Mai',
	'Jun',
	'Jul',
	'Aug',
	'Sep',
	'Okt',
	'Nov',
	'Dez'
];

/** „Heute", „Gestern", „Morgen" oder „Mo, 29. Sep 2025". */
export function dayLabel(key: string): string {
	const today = todayKey();
	if (key === today) return 'Heute';
	if (key === shiftDayKey(today, -1)) return 'Gestern';
	if (key === shiftDayKey(today, 1)) return 'Morgen';
	const d = new Date(msFromKey(key));
	const wd = WEEKDAYS_SHORT[d.getDay()];
	const day = d.getDate();
	const mon = MONTHS_SHORT[d.getMonth()];
	const yr = d.getFullYear();
	const curYear = new Date().getFullYear();
	return `${wd}, ${day}. ${mon}${yr === curYear ? '' : ` ${yr}`}`;
}

// ── Uhrzeit-Formatierung ─────────────────────────────────────────────────

export function timeShort(ms: number): string {
	const d = new Date(ms);
	const h = String(d.getHours()).padStart(2, '0');
	const m = String(d.getMinutes()).padStart(2, '0');
	return `${h}:${m}`;
}

/** Dauer in „2h 30min" / „45min" / „10h". */
export function durationShort(ms: number): string {
	const totalMin = Math.max(1, Math.round(ms / 60000));
	const h = Math.floor(totalMin / 60);
	const m = totalMin % 60;
	if (h === 0) return `${m}min`;
	if (m === 0) return `${h}h`;
	return `${h}h ${m}min`;
}

// ── datetime-local Konvertierung ─────────────────────────────────────────

/** Epoch ms → "YYYY-MM-DDTHH:MM" für <input type="datetime-local">. */
export function msToLocalInput(ms: number): string {
	const d = new Date(ms);
	const p = (n: number) => String(n).padStart(2, '0');
	return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}`;
}

/** "YYYY-MM-DDTHH:MM" → epoch ms (lokale Zeitzone). */
export function localInputToMs(s: string): number {
	const m = s.match(/^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})/);
	if (!m) throw new Error(`Ungültiges Datumsformat: ${s}`);
	const [, y, mo, d, h, mi] = m;
	return new Date(Number(y), Number(mo) - 1, Number(d), Number(h), Number(mi)).getTime();
}

/** Epoch ms → "YYYY-MM-DD" für <input type="date">. */
export function msToDateInput(ms: number): string {
	const d = new Date(ms);
	const p = (n: number) => String(n).padStart(2, '0');
	return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
}

/** "YYYY-MM-DD" → epoch ms (lokale Mitternacht). Alias für msFromKey. */
export function dateInputToMs(s: string): number {
	return msFromKey(s);
}

/** UTC-Format für iCal/CalDAV (YYYYMMDDTHHMMSSZ). */
export function toIcsUtc(ms: number): string {
	const d = new Date(ms);
	const p = (n: number, l = 2) => String(n).padStart(l, '0');
	return (
		`${d.getUTCFullYear()}${p(d.getUTCMonth() + 1)}${p(d.getUTCDate())}` +
		`T${p(d.getUTCHours())}${p(d.getUTCMinutes())}${p(d.getUTCSeconds())}Z`
	);
}
