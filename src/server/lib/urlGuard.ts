// SSRF-Schutz für serverseitige Fetches (CalDAV-Verbindungen, Webhook, …).
//
// Es dürfen nur http(s)-Ziele angefasst werden; reservierte interne Bereiche
// (Loopback, „0.", Link-Local/Cloud-Metadaten) werden blockiert — sowohl als
// explizite IP-Literale als auch via DNS-Auflösung des Hostnames.
// Private Netzwerke (192.168.x, 10.x, 172.16–31.x, IPv6-ULA) sind bewusst
// erlaubt: Self-Hosting in lokalen Netzen ist der Haupteinsatzfall
// (Radicale, T3 Code auf dem Heimserver).
//
// Redirects werden manuell gefolgt und jedes Ziel wieder geprüft — sonst
// könnte ein eigener Server mit einem 302 auf 169.254.169.254 (Cloud-
// Metadaten) verweisen. Methode und Body bleiben über Redirects erhalten
// (API-Semantik, nicht Browser-Semantik).
//
// Bekannte Restrisiken: DNS-Rebinding (die Adresse ändert sich zwischen
// Prüfung und Verbindungsaufbau) — für den Self-Hosting-Kontext unkritisch.

import { lookup } from 'node:dns/promises';
import { isIP } from 'node:net';

const MAX_REDIRECT_HOPS = 5;
const REDIRECT_STATUS = new Set([301, 302, 303, 307, 308]);

/**
 * Liefert die 8 normalisierten Hextets (klein, 4-stellig) einer IPv6-Adresse
 * (inkl. IPv4-embeddede Form) oder null, wenn sie sich nicht sauber parsen
 * lässt (z. B. Zone-ID) — null wird beim Aufrufer als „blockiert" gewertet.
 */
function v6Hextets(ip: string): string[] | null {
	const s = ip.toLowerCase();
	if (s.includes('%')) return null; // Zone-ID → nicht sicher einzuordnen
	const ci = s.indexOf('::');
	let left = '';
	let right = '';
	if (ci === -1) {
		left = s;
	} else {
		if (s.indexOf('::', ci + 1) !== -1) return null;
		left = s.slice(0, ci);
		right = s.slice(ci + 2);
	}
	let l = left === '' ? [] : left.split(':');
	let r = right === '' ? [] : right.split(':');
	// IPv4-embeddede Form („…:1.2.3.4"): letztes Element in Hextets wandeln.
	if (r.length > 0 && r[r.length - 1].includes('.')) {
		const octets = r[r.length - 1].split('.');
		if (octets.length !== 4) return null;
		const nums: number[] = [];
		for (const o of octets) {
			if (!/^\d{1,3}$/.test(o)) return null;
			const n = Number(o);
			if (n > 255) return null;
			nums.push(n);
		}
		r = [
			...r.slice(0, -1),
			((nums[0] << 8) | nums[1]).toString(16),
			((nums[2] << 8) | nums[3]).toString(16)
		];
	}
	if (l.length > 7 || r.length > 7) return null;
	if (ci === -1 && l.length !== 8) return null;
	if (ci !== -1 && l.length + r.length > 7) return null;
	for (const p of [...l, ...r]) {
		if (p === '' || p.length > 4 || !/^[0-9a-f]+$/.test(p)) return null;
	}
	const mid = ci === -1 ? [] : Array<string>(8 - l.length - r.length).fill('0');
	return [...l, ...mid, ...r].map((h) => h.padStart(4, '0'));
}

/** True, wenn die IP-Adresse in einem blockierten internen Bereich liegt. */
export function ipBlocked(ip: string): boolean {
	if (isIP(ip) === 4) {
		return ip.startsWith('0.') || ip.startsWith('127.') || ip.startsWith('169.254.');
	}
	const h = v6Hextets(ip);
	if (h === null) return true; // nicht sicher parsierbar → blockieren
	if (h.every((x) => x === '0000')) return true; // ::
	if (h[7] === '0001' && h.slice(0, 7).every((x) => x === '0000')) return true; // ::1
	// ::ffff:a.b.c.d (IPv4-mapped): als IPv4 neu prüfen.
	if (h.slice(0, 5).every((x) => x === '0000') && h[5] === 'ffff') {
		const n = (parseInt(h[6], 16) << 16) | parseInt(h[7], 16);
		return ipBlocked(
			`${(n >>> 24) & 255}.${(n >>> 16) & 255}.${(n >>> 8) & 255}.${n & 255}`
		);
	}
	const first = parseInt(h[0], 16);
	if (first >= 0xfe80 && first <= 0xfebf) return true; // fe80::/10 (Link-Local)
	if (h[0] === '2001' && h[1] === '0000') return true; // 2001:0000::/32 (6to4/Teredo)
	return false;
}

/**
 * Prüft eine URL vor einem serverseitigen Fetch (Scheme, Host, IP-Literal,
 * DNS-Auflösung) und liefert die normalisierte URL.
 * Wirft einen Error mit deutscher, benutzerfreundlicher Meldung.
 */
export async function assertSafeUrl(raw: string, label: string): Promise<string> {
	let u: URL;
	try {
		u = new URL(raw);
	} catch {
		throw new Error(`${label}: Ungültige URL.`);
	}
	if (u.protocol !== 'http:' && u.protocol !== 'https:') {
		throw new Error(`${label}: Nur http(s)-URLs sind erlaubt.`);
	}
	const host = u.hostname.replace(/^\[|\]$/g, '');
	if (host === '' || host === 'localhost') {
		throw new Error(`${label}: Diese Adresse ist nicht erlaubt.`);
	}
	if (isIP(host) !== 0) {
		if (ipBlocked(host)) {
			throw new Error(`${label}: Die Adresse liegt in einem gesperrten internen Bereich.`);
		}
		return u.href;
	}
	// Hostname: alle aufgelösten Adressen müssen okay sein (schon ein
	// einziger Eintrag auf eine interne Adresse wäre problematisch).
	let records: Array<{ address: string }>;
	try {
		records = await lookup(host, { all: true, verbatim: true });
	} catch {
		throw new Error(`${label}: Hostname konnte nicht aufgelöst werden.`);
	}
	if (records.length === 0 || records.some((r) => ipBlocked(r.address))) {
		throw new Error(`${label}: Die Adresse liegt in einem gesperrten internen Bereich.`);
	}
	return u.href;
}

/**
 * fetch() mit SSRF-Schutz: Start-URL und jede Redirect-Zwischenstufe werden
 * geprüft. Methode und Body bleiben über Redirects erhalten.
 */
export async function guardedFetch(
	rawUrl: string,
	label: string,
	init: RequestInit
): Promise<Response> {
	let url = await assertSafeUrl(rawUrl, label);
	for (let hop = 0; ; hop++) {
		const res = await fetch(url, { ...init, redirect: 'manual' });
		if (!REDIRECT_STATUS.has(res.status)) return res;
		if (hop >= MAX_REDIRECT_HOPS) return res;
		const loc = res.headers.get('location');
		if (!loc) return res;
		let next: string;
		try {
			next = await assertSafeUrl(new URL(loc, url).href, label);
		} catch {
			// Weiterleitung auf gesperrtes Ziel: stoppen, Redirect zurückgeben.
			return res;
		}
		url = next;
	}
}
