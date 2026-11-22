// Tests für die ics-Extraktion aus rohem CalDAV-XML (client.ts) und die
// URL-Normalisierung. Keine Netzwerkzugriffe – reine String-Fixtures.
import { describe, expect, it } from 'vitest';
import { extractAllIcs, normalizeCalDavUrl } from '$server/caldav/client';
import {
	ICS_A,
	ICS_B,
	MULTISTATUS_CDATA,
	MULTISTATUS_CDATA_DIRECT,
	MULTISTATUS_DIRECT,
	MULTISTATUS_ENTITIES,
	MULTISTATUS_MULTI,
	MULTISTATUS_NAMESPACED,
	MULTISTATUS_NO_ICS,
	MULTISTATUS_PLAIN,
	MULTISTATUS_WITH_ATTRS
} from '../fixtures/caldavXml';

describe('extractAllIcs', () => {
	it('findet nacktes <calendar-data> im <response>', () => {
		const out = extractAllIcs(MULTISTATUS_PLAIN);
		expect(out).toHaveLength(1);
		expect(out[0]).toBe(ICS_A);
	});

	it('findet namesierte Präfixe (C:calendar-data, D:href, D:response)', () => {
		const out = extractAllIcs(MULTISTATUS_NAMESPACED);
		expect(out).toHaveLength(1);
		expect(out[0]).toBe(ICS_B);
	});

	it('ignoriert Attribute am calendar-data-Element', () => {
		expect(extractAllIcs(MULTISTATUS_WITH_ATTRS)).toEqual([ICS_A]);
	});

	it('entpackt CDATA um das ICS', () => {
		expect(extractAllIcs(MULTISTATUS_CDATA)).toEqual([ICS_A]);
	});

	it('entpackt CDATA direkt im response-Block', () => {
		expect(extractAllIcs(MULTISTATUS_CDATA_DIRECT)).toEqual([ICS_B]);
	});

	it('akzeptiert ICS direkt im response-Block ohne calendar-data', () => {
		expect(extractAllIcs(MULTISTATUS_DIRECT)).toEqual([ICS_A]);
	});

	it('decodiert XML-Entities im calendar-data-Inhalt', () => {
		const out = extractAllIcs(MULTISTATUS_ENTITIES);
		expect(out).toHaveLength(1);
		expect(out[0]).toContain('SUMMARY:Meeting <Q2> Planung');
		// Einfaches, geordnetes Decoding: &amp;lt; → &lt; (kein Doppel-Decoding),
		// nacktes &amp; → & (Entities werden in einem Wertedurchlauf gelöst).
		expect(out[0]).toContain('DESCRIPTION:Escaped: &lt; & und <b>fett</b>');
		expect(out[0].startsWith('BEGIN:VCALENDAR')).toBe(true);
	});

	it('liefert mehrere ICS-Blöcke in Dokumentreihenfolge', () => {
		expect(extractAllIcs(MULTISTATUS_MULTI)).toEqual([ICS_A, ICS_B]);
	});

	it('überspringt responses ohne calendar-data', () => {
		expect(extractAllIcs(MULTISTATUS_NO_ICS)).toEqual([]);
	});

	it('überspringt einen einzelnen response ohne ICS in einer Mischung', () => {
		const icsOhne = '<response><href>/x.ics</href><getetag>"1"</getetag></response>';
		expect(extractAllIcs(icsOhne + MULTISTATUS_PLAIN)).toEqual([ICS_A]);
	});

	it('ignoriert unclosed response-Tags', () => {
		const unclosed = MULTISTATUS_PLAIN.replace('</response>', '');
		expect(extractAllIcs(unclosed)).toEqual([]);
	});

	it('liefert leere Arrays für unpassendes oder kaputtes XML', () => {
		expect(extractAllIcs('')).toEqual([]);
		expect(extractAllIcs('kein xml')).toEqual([]);
		expect(extractAllIcs('<multistatus/>')).toEqual([]);
		expect(extractAllIcs('<response></response>')).toEqual([]);
		// <responses> (Plural) ist kein <response>-öffnendes Tag
		expect(extractAllIcs('<responses>BEGIN:VCALENDAR</responses>')).toEqual([]);
	});

	it('bricht nicht ab, wenn calendar-data kein VCALENDAR enthält', () => {
		const vcard = `<response><calendar-data>BEGIN:VCARD\r\nEND:VCARD</calendar-data></response>`;
		expect(extractAllIcs(vcard)).toEqual([]);
	});
});

describe('normalizeCalDavUrl', () => {
	it('ergänzt https bei nackten Domains', () => {
		expect(normalizeCalDavUrl('kalender.example.com')).toBe('https://kalender.example.com');
		expect(normalizeCalDavUrl(' kalender.example.com ')).toBe('https://kalender.example.com');
	});

	it('ergänzt https bei Domain mit Pfad und innerem Whitespace', () => {
		expect(normalizeCalDavUrl('kalender.example. com/dav')).toBe('https://kalender.example.com/dav');
	});

	it('lässt http(s)-URLs unverändert', () => {
		expect(normalizeCalDavUrl('http://heim.local:8080/dav')).toBe('http://heim.local:8080/dav');
		expect(normalizeCalDavUrl('https://dav.example.com/')).toBe('https://dav.example.com/');
		expect(normalizeCalDavUrl('HTTPS://Dav.Example.com')).toBe('HTTPS://Dav.Example.com');
	});

	it('liefert leere Zeichenkette bei leerer Eingabe', () => {
		expect(normalizeCalDavUrl('')).toBe('');
		expect(normalizeCalDavUrl('   ')).toBe('');
	});
});
