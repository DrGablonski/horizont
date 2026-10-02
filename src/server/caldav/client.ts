// CalDAV-Client: PROPFIND (Discovery + Kalender-Liste) und REPORT (Events).
// XML wird namespace-frei geparst; ics-Blöcke werden per Regex aus der rohen
// Antwort gezogen (weder valides XML noch CDATA zuverlässig).

import { createHash } from 'node:crypto';
import { XMLParser } from 'fast-xml-parser';
import Ical from 'ical.js';
import type { CalDavCalendar, CalDavSettings } from '$lib/types';
import { DAV_TIMEOUT_MS } from '$server/lib/constants';

// ── Fehler-Typ ────────────────────────────────────────────────────────────

export class CalDavError extends Error {
	constructor(public status: number, message: string) {
		super(message);
		this.name = 'CalDavError';
	}
}

// ── Deterministische Farbpaletten (8 Farben) ─────────────────────────────
export const PALETTE: string[] = [
	'#2563eb', // blue
	'#dc2626', // red
	'#16a34a', // green
	'#9333ea', // purple
	'#ea580c', // orange
	'#0d9488', // teal
	'#db2777', // pink
	'#7c3aed' // violet
];

// ── XML-Helfer ────────────────────────────────────────────────────────────

// Entfernt Namespace-Präfixe von Tag-Namen (Attribute bleiben unangetastet).
function stripNs(xml: string): string {
	return xml.replace(/<\/?([a-zA-Z][\w]*):([a-zA-Z][\w]*)/g, (m, _a, b) => {
		const slash = m.startsWith('</') ? '</' : '<';
		return `${slash}${b}`;
	});
}

const parser = new XMLParser({
	ignoreAttributes: false,
	attributeNamePrefix: '@_',
	isArray: () => true,
	trimValues: true
});

function parseXml(xml: string): any {
	return parser.parse(stripNs(xml));
}

/** Tritt rekursiv in einen geparsten Baum ein und sammelt alle Werte unter `key`. */
function collect(node: any, key: string): any[] {
	const out: any[] = [];
	if (node == null || typeof node !== 'object') return out;
	if (Array.isArray(node)) {
		for (const n of node) out.push(...collect(n, key));
		return out;
	}
	for (const k of Object.keys(node)) {
		const v = (node as Record<string, any>)[k];
		if (k === key) {
			if (Array.isArray(v)) out.push(...v);
			else out.push(v);
		}
		if (v != null && typeof v === 'object') out.push(...collect(v, key));
	}
	return out;
}

/** Extrahiert Textinhalt aus einem geparsten Knoten (#text / #cdata / text). */
function textOf(node: any): string | undefined {
	if (node == null) return undefined;
	if (typeof node === 'string') return node;
	if (typeof node === 'number') return String(node);
	if (Array.isArray(node)) {
		for (const n of node) {
			const t = textOf(n);
			if (t != null && t !== '') return t;
		}
		return undefined;
	}
	if (typeof node === 'object') {
		const o = node as Record<string, any>;
		if (o['#text'] != null) return String(o['#text']);
		if (o['#cdata'] != null) return String(o['#cdata']);
		if (o['text'] != null) return String(o['text']);
	}
	return undefined;
}

function decodeXmlEntities(s: string): string {
	return s
		.replace(/&lt;/g, '<')
		.replace(/&gt;/g, '>')
		.replace(/&quot;/g, '"')
		.replace(/&apos;/g, "'")
		.replace(/&amp;/g, '&');
}

// ── HTTP ──────────────────────────────────────────────────────────────────

interface DavResponse {
	status: number;
	text: string;
	headers: Record<string, string>;
}

async function davRequest(
	settings: CalDavSettings,
	url: string,
	method: string,
	body: string,
	extraHeaders: Record<string, string> = {}
): Promise<DavResponse> {
	// Zugangsdaten normalisieren: Leading/Trailing-Whitespace erzeugt sonst 401.
	const token = Buffer.from(`${settings.username.trim()}:${settings.password.trim()}`).toString('base64');
	const controller = new AbortController();
	const timer = setTimeout(() => controller.abort(), DAV_TIMEOUT_MS);
	try {
		const res = await fetch(url, {
			method,
			headers: {
				Authorization: `Basic ${token}`,
				'Content-Type': 'application/xml; charset=utf-8',
				...extraHeaders
			},
			body: body || undefined,
			signal: controller.signal
		});
		const text = await res.text();
		const headers: Record<string, string> = {};
		res.headers.forEach((v, k) => {
			headers[k.toLowerCase()] = v;
		});
		return { status: res.status, text, headers };
	} finally {
		clearTimeout(timer);
	}
}

function authError(): never {
	throw new Error('CalDAV-Authentifizierung fehlgeschlagen (401/403).');
}

// ── Discovery ─────────────────────────────────────────────────────────────

export interface HomeInfo {
	home: string;
	principal: string | null;
}

export async function resolveHome(settings: CalDavSettings): Promise<HomeInfo> {
	const body = `<?xml version="1.0" encoding="utf-8"?>
<propfind xmlns="DAV:">
  <prop>
    <current-user-principal/>
    <calendar-home-set xmlns="urn:ietf:params:xml:ns:caldav"/>
  </prop>
</propfind>`;

	const base = settings.url.replace(/\/?$/, '/');
	const r = await davRequest(settings, base, 'PROPFIND', body, { Depth: '0' });
	if (r.status === 401 || r.status === 403) authError();
	if (r.status >= 400) {
		// Kein Discovery-Endpunkt – die URL selbst als Basis verwenden.
		return { home: base, principal: null };
	}

	const doc = parseXml(r.text);
	const principalHrefs = collect(doc, 'current-user-principal').map((n: any) => collect(n, 'href').map(textOf).find((t: any) => t));
	const homeHrefs = collect(doc, 'calendar-home-set').map((n: any) => collect(n, 'href').map(textOf).find((t: any) => t));

	const principalHref = principalHrefs.find((h: any) => h);
	const homeHref = homeHrefs.find((h: any) => h);

	let home = base;
	if (homeHref) home = new URL(homeHref, base).toString();
	else if (principalHref) home = new URL(principalHref, base).toString();
	const principal = principalHref ? new URL(principalHref, base).toString() : null;

	return { home, principal };
}

// ── Kalender-Liste ────────────────────────────────────────────────────────

export async function listCalendars(settings: CalDavSettings, home: string): Promise<CalDavCalendar[]> {
	const body = `<?xml version="1.0" encoding="utf-8"?>
<propfind xmlns="DAV:">
  <prop>
    <displayname/>
    <resourcetype/>
  </prop>
</propfind>`;

	const url = home.replace(/\/?$/, '/');
	const r = await davRequest(settings, url, 'PROPFIND', body, { Depth: '1' });
	if (r.status === 401 || r.status === 403) authError();
	if (r.status >= 400) throw new Error(`CalDAV: Kalender-Liste nicht abrufbar (HTTP ${r.status}).`);

	const doc = parseXml(r.text);
	const responses = collect(doc, 'response');
	const out: CalDavCalendar[] = [];
	const seen = new Set<string>();

	for (const block of responses) {
		const calendars = collect(block, 'calendar');
		if (calendars.length === 0) continue; // kein Kalender-Ressource

		const hrefs = collect(block, 'href');
		const href = textOf(hrefs[0]);
		if (!href) continue;
		const full = new URL(href, url).toString();
		if (seen.has(full)) continue;
		seen.add(full);

		const name = textOf(collect(block, 'displayname')[0]) || 'Unbenannter Kalender';
		const hash = createHash('sha256').update(full).digest('hex').slice(0, 12);
		const color = PALETTE[parseInt(hash, 16) % PALETTE.length];

		out.push({ id: hash, name, color, url: full });
	}

	return out.sort((a, b) => a.name.localeCompare(b.name, 'de'));
}

// ── ics-Extraktion (Regex auf Roh-XML) ────────────────────────────────────

function stripCdata(s: string): string {
	let c = s.trim();
	if (c.startsWith('<![CDATA[')) {
		c = c.slice('<![CDATA['.length);
		if (c.endsWith(']]>')) c = c.slice(0, -3);
		c = c.trim();
	}
	return c;
}

function extractIcsFromBlock(block: string): string | null {
	// Fall A: direkter Text / CDATA
	let direct = stripCdata(block);
	if (direct.startsWith('BEGIN:VCALENDAR')) return direct;

	// Fall B: <...calendar-data> ... </...calendar-data>
	const m = block.match(
		/<(?:[a-zA-Z][\w]*:)?calendar-data[^>]*>([\s\S]*?)<\/(?:[a-zA-Z][\w]*:)?calendar-data\s*>/i
	);
	if (m) {
		let inner = stripCdata(m[1]);
		if (inner.startsWith('BEGIN:VCALENDAR')) return decodeXmlEntities(inner);
	}
	return null;
}

export function extractAllIcs(xml: string): string[] {
	const out: string[] = [];
	const openRe = /<(?:[a-zA-Z][\w]*:)?response\b[^>]*>/g;
	let m: RegExpExecArray | null;
	while ((m = openRe.exec(xml))) {
		const startIdx = m.index + m[0].length;
		const rest = xml.slice(startIdx);
		const cm = rest.match(/<\/(?:[a-zA-Z][\w]*:)?response\s*>/);
		if (!cm || cm.index == null) continue;
		const endIdx = startIdx + cm.index;
		const block = xml.slice(startIdx, endIdx);
		const ics = extractIcsFromBlock(block);
		if (ics) out.push(ics);
	}
	return out;
}

// ── Event-Abfrage ─────────────────────────────────────────────────────────

export async function fetchCalendarIcs(
	settings: CalDavSettings,
	calendar: CalDavCalendar,
	startIcs: string,
	endIcs: string
): Promise<string[]> {
	const report = `<?xml version="1.0" encoding="utf-8"?>
<C:calendar-query xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">
  <D:prop>
    <D:getetag/>
  </D:prop>
  <C:filter>
    <C:comp-filter name="VCALENDAR">
      <C:comp-filter name="VEVENT">
        <C:time-range start="${startIcs}" end="${endIcs}"/>
      </C:comp-filter>
    </C:comp-filter>
  </C:filter>
</C:calendar-query>`;

	const url = calendar.url.replace(/\/?$/, '/');
	let r = await davRequest(settings, url, 'REPORT', report, {
		Depth: '1',
		Accept: 'application/xml, text/calendar, */*'
	});

	// Fallback: REPORT nicht unterstützt → PROPFIND + GET pro .ics
	if (r.status === 400 || r.status === 501 || r.status === 500 || extractAllIcs(r.text).length === 0) {
		const list = await listCalendarsEvents(settings, calendar.url);
		const icsList: string[] = [];
		for (const icsUrl of list) {
			const gr = await davRequest(settings, icsUrl, 'GET', '');
			if (gr.status === 200 && gr.text.includes('BEGIN:VCALENDAR')) {
				icsList.push(gr.text);
			}
		}
		return icsList;
	}

	if (r.status === 401 || r.status === 403) authError();
	if (r.status >= 400) throw new Error(`CalDAV: Event-Abfrage fehlgeschlagen (HTTP ${r.status}).`);
	return extractAllIcs(r.text);
}

async function listCalendarsEvents(settings: CalDavSettings, calendarUrl: string): Promise<string[]> {
	const base = calendarUrl.replace(/\/?$/, '/');
	const body = `<?xml version="1.0" encoding="utf-8"?>
<propfind xmlns="DAV:">
  <prop>
    <getetag/>
  </prop>
</propfind>`;
	const r = await davRequest(settings, base, 'PROPFIND', body, { Depth: '1' });
	if (r.status >= 400) return [];
	const doc = parseXml(r.text);
	const responses = collect(doc, 'response');
	const urls: string[] = [];
	for (const block of responses) {
		const href = textOf(collect(block, 'href')[0]);
		if (!href) continue;
		if (!href.toLowerCase().endsWith('.ics')) continue;
		if (href.toLowerCase().includes('collection')) continue;
		urls.push(new URL(href, base).toString());
	}
	return urls;
}

// ── Objekt-Liste (PROPFIND mit etag) ──────────────────────────────────────

export interface CalendarObject {
	url: string;
	etag: string;
}

export async function listCalendarObjects(
	settings: CalDavSettings,
	calendarUrl: string
): Promise<CalendarObject[]> {
	const base = calendarUrl.replace(/\/?$/, '/');
	const body = `<?xml version="1.0" encoding="utf-8"?>
<propfind xmlns="DAV:">
  <prop>
    <getetag/>
  </prop>
</propfind>`;
	const r = await davRequest(settings, base, 'PROPFIND', body, { Depth: '1' });
	if (r.status === 401 || r.status === 403) authError();
	if (r.status >= 400) throw new CalDavError(r.status, `CalDAV: Objekt-Liste nicht abrufbar (HTTP ${r.status}).`);

	const doc = parseXml(r.text);
	const responses = collect(doc, 'response');
	const out: CalendarObject[] = [];

	for (const block of responses) {
		const href = textOf(collect(block, 'href')[0]);
		if (!href) continue;
		if (!href.toLowerCase().endsWith('.ics')) continue;
		if (href.toLowerCase().includes('collection')) continue;
		const full = new URL(href, base).toString();
		const etag = textOf(collect(block, 'getetag')[0]) ?? '';
		out.push({ url: full, etag });
	}

	return out;
}

// ── GET einzelnes Objekt ──────────────────────────────────────────────────

export async function getObjectIcs(settings: CalDavSettings, url: string): Promise<string | null> {
	const r = await davRequest(settings, url, 'GET', '');
	if (r.status === 200 && r.text.includes('BEGIN:VCALENDAR')) return r.text;
	return null;
}

// ── UID-Suche (list + parallel GET mit Early-Exit) ───────────────────────

const SEARCH_CONCURRENCY = 8;

function uidMatchesIcs(ics: string, uid: string): boolean {
	try {
		const j = Ical.parse(ics.replace(/\r\n[ \t]/g, '').replace(/\n[ \t]/g, '')) as any;
		const comp = new Ical.Component(j);
		const vevents: any[] = comp.getAllSubcomponents('vevent') ?? [];
		const vtodos: any[] = comp.getAllSubcomponents('vtodo') ?? [];
		for (const v of [...vevents, ...vtodos]) {
			if (v.getFirstPropertyValue?.('uid') === uid) return true;
		}
	} catch {
		/* parse failed */
	}
	return false;
}

export async function findObjectByUid(
	settings: CalDavSettings,
	calendar: CalDavCalendar,
	uid: string
): Promise<{ url: string; etag: string; ics: string } | null> {
	const objects = await listCalendarObjects(settings, calendar.url);
	if (objects.length === 0) return null;

	let found: { url: string; etag: string; ics: string } | null = null;
	let stop = false;

	for (let i = 0; i < objects.length && !stop; i += SEARCH_CONCURRENCY) {
		const batch = objects.slice(i, i + SEARCH_CONCURRENCY);
		const results = await Promise.all(
			batch.map(async (obj) => {
				if (stop) return null;
				const ics = await getObjectIcs(settings, obj.url);
				if (ics == null) return null;
				if (uidMatchesIcs(ics, uid)) {
					if (!stop) {
						stop = true;
						return { url: obj.url, etag: obj.etag, ics };
					}
				}
				return null;
			})
		);
		for (const r of results) {
			if (r != null) {
				found = r;
				stop = true;
				break;
			}
		}
	}

	return found;
}

// ── PUT (schreiben/aktualisieren) ────────────────────────────────────────

export async function putIcs(
	settings: CalDavSettings,
	url: string,
	ics: string,
	etag?: string
): Promise<string | null> {
	const extraHeaders: Record<string, string> = {
		'Content-Type': 'text/calendar; charset=utf-8'
	};
	if (etag) extraHeaders['If-Match'] = etag;
	const r = await davRequest(settings, url, 'PUT', ics, extraHeaders);
	if (r.status === 412) {
		throw new CalDavError(
			409,
			'ETag-Mismatch: Der Eintrag wurde seit der Abfrage verändert. Bitte aktualisieren und erneut versuchen.'
		);
	}
	if (r.status === 401 || r.status === 403) authError();
	if (r.status >= 400) throw new CalDavError(r.status, `CalDAV: PUT fehlgeschlagen (HTTP ${r.status}).`);
	return r.headers['etag'] ?? null;
}

// ── DELETE ────────────────────────────────────────────────────────────────

export async function deleteIcs(settings: CalDavSettings, url: string, etag?: string): Promise<void> {
	const extraHeaders: Record<string, string> = {};
	if (etag) extraHeaders['If-Match'] = etag;
	const r = await davRequest(settings, url, 'DELETE', '', extraHeaders);
	if (r.status === 412) {
		throw new CalDavError(409, 'ETag-Mismatch: Der Eintrag wurde seit der Abfrage verändert.');
	}
	if (r.status === 401 || r.status === 403) authError();
	if (r.status >= 400 && r.status !== 404) {
		throw new CalDavError(r.status, `CalDAV: DELETE fehlgeschlagen (HTTP ${r.status}).`);
	}
}
