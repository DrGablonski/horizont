// Tests für den SSRF-Schutz (urlGuard.ts). Es werden ausschließlich
// IP-Literale geprüft – keine DNS-abhängigen Assertions (deterministisch,
// ohne Netzwerk).
import { describe, expect, it } from 'vitest';
import { assertSafeUrl, ipBlocked } from '$server/lib/urlGuard';

describe('ipBlocked – IPv4', () => {
	it.each(['127.0.0.1', '127.255.255.254', '0.0.0.0', '0.255.255.255', '169.254.169.254', '169.254.1.1'])(
		'sperrt interne Adresse %s',
		ip => expect(ipBlocked(ip)).toBe(true)
	);

	it.each([
		'192.168.178.10', // Heimnetz
		'10.255.0.1',
		'172.16.5.4',
		'172.31.255.255',
		'169.253.9.9', // direkt außerhalb 169.254.0.0/16
		'169.255.0.1',
		'100.64.0.1', // CGNAT – laut Doc-Absicht nicht gesperrt
		'8.8.8.8'
	])('erlaubt öffentliche/private Adresse %s', ip => expect(ipBlocked(ip)).toBe(false));
});

describe('ipBlocked – IPv6', () => {
	it.each([
		'::', // nicht spezifiziert
		'::1', // Loopback
		'0000:0000:0000:0000:0000:0000:0000:0001', // Loopback ausgeschriebener Form
		'::ffff:127.0.0.1', // IPv4-mapped Loopback
		'::ffff:7f00:1', // dito, als Hextets
		'::ffff:0.0.0.0', // IPv4-mapped „0."
		'fe80::', // Link-Local
		'fe80::abcd',
		'febf:ffff::', // Grenze fe80::/10
		'FE80::ABCD', // Großbuchstaben
		'2001:0000::1' // 6to4/Teredo-Bereich
	])('sperrt interne Adresse %s', ip => expect(ipBlocked(ip)).toBe(true));

	it.each([
		'::ffff:8.8.8.8', // IPv4-mapped öffentlich
		'::ffff:192.168.1.1', // IPv4-mapped privat → erlaubt
		'64:ff9b::1.2.3.4', // NAT64 mit eingebettetem IPv4
		'fc00::1', // ULA – laut Doc-Absicht erlaubt
		'fd12:3456::1',
		'2001:db8::1', // Dokumentation
		'fec0::1', // ehem. Site-Local, nicht mehr blockiert
		'fe7f::1', // direkt unterhalb fe80::/10
		'::2'
	])('erlaubt Adresse %s', ip => expect(ipBlocked(ip)).toBe(false));
});

describe('ipBlocked – unparsebare Eingaben (im Zweifel gesperrt)', () => {
	it.each([
		'fe80::1%eth0', // Zone-ID
		'127.0.0.1%1', // Zone-ID bei IPv4-Literal
		'not-an-ip',
		'',
		'999.1.1.1',
		'1.2.3.4.5',
		':::',
		'::1::',
		'1:2:3:4:5:6:7:8:9',
		'12345::1' // Hextet mit 5 Ziffern
	])('sperrt %s', ip => expect(ipBlocked(ip)).toBe(true));
});

describe('assertSafeUrl – nur mit IP-Literalen', () => {
	it('lässt private und öffentliche IP-Literale durch', async () => {
		await expect(assertSafeUrl('http://192.168.178.20:8080/dav/', 'CalDAV')).resolves.toBe(
			'http://192.168.178.20:8080/dav/'
		);
		await expect(assertSafeUrl('https://8.8.8.8/', 'CalDAV')).resolves.toBe('https://8.8.8.8/');
		await expect(assertSafeUrl('https://[fd00::5]/x', 'CalDAV')).resolves.toContain('[fd00::5]');
	});

	it.each([
		'http://127.0.0.1/',
		'http://0.0.0.0/',
		'http://169.254.169.254/latest/meta-data/',
		'https://[::1]/',
		'http://[::]/',
		'http://[fe80::1]/',
		'http://[::ffff:127.0.0.1]/'
	])('sperrt %s', async url => {
		await expect(assertSafeUrl(url, 'CalDAV')).rejects.toThrow(/gesperrten internen Bereich/);
	});

	it.each([
		['ftp://10.0.0.1/', /Nur http\(s\)-URLs/],
		['javascript:alert(1)', /Nur http\(s\)-URLs/],
		['http://localhost:3000/', /nicht erlaubt/],
		['kein url', /Ungültige URL/]
	] as const)('lehnt %s mit klarer Meldung ab', async (url, pattern) => {
		await expect(assertSafeUrl(url, 'Webhook')).rejects.toThrow(pattern);
	});
});
