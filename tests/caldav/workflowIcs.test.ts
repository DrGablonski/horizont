// Tests für die Workflow-ICS-Persistenz (workflowIcs.ts): Round-Trip über das
// X-HORIZONT-Base64-Payload, deterministische Serialisierung, Status-Ableitung
// und die Payload-Validierung.
import { describe, expect, it } from 'vitest';
import type { Workflow } from '$lib/types';
import { unfold } from '$server/caldav/icswriter';
import { buildWorkflowIcs, decodeWorkflow, encodeWorkflow, parseWorkflowIcs } from '$server/caldav/workflowIcs';

function workflow(overrides: Partial<Workflow> = {}): Workflow {
	return {
		id: 'wf-1@test',
		title: 'Umzug',
		notes: 'Kisten & Material besorgen.\nZweite Zeile; mit Sonderzeichen \\ und ;',
		createdAt: Date.UTC(2025, 9, 1, 10, 0, 0),
		updatedAt: Date.UTC(2025, 9, 2, 12, 30, 0),
		completedAt: null,
		activeStepId: 's2',
		steps: [
			{ id: 's1', title: 'Kisten besorgen', done: true, completedAt: Date.UTC(2025, 9, 1, 12, 0, 0) },
			{ id: 's2', title: 'Wohnung < kündigen >', done: false, completedAt: null },
			{ id: 's3', title: 'Nachsendeauftrag', done: false, completedAt: null }
		],
		progress: 1 / 3,
		...overrides
	};
}

function prop(ics: string, name: string): string | undefined {
	const m = new RegExp('^' + name + '(?:;[^:]*)?:(.*)$', 'mi').exec(unfold(ics));
	return m?.[1];
}

describe('buildWorkflowIcs ↔ parseWorkflowIcs Roundtrip', () => {
	it('erhält den vollständigen Workflow über X-HORIZONT', () => {
		const wf = workflow();
		const parsed = parseWorkflowIcs(buildWorkflowIcs(wf));
		expect(parsed).toEqual(wf);
	});

	it('erhält einen leeren Workflow (keine Schritte, keine Notizen)', () => {
		const wf = workflow({
			title: 'Leer',
			notes: '',
			steps: [],
			activeStepId: null,
			progress: 0
		});
		expect(parseWorkflowIcs(buildWorkflowIcs(wf))).toEqual(wf);
	});

	it('übersteht langes, gefaltetes X-HORIZONT-Payload', () => {
		const wf = workflow({
			notes: 'Sehr lange Notiz. '.repeat(120),
			steps: Array.from({ length: 30 }, (_, i) => ({
				id: `s${i}`,
				title: `Schritt ${i} mit ausführlichem Titelstext`,
				done: i % 2 === 0,
				completedAt: i % 2 === 0 ? Date.UTC(2025, 9, 1) : null
			})),
			progress: 0.5
		});
		const ics = buildWorkflowIcs(wf);
		// Das Payload muss tatsächlich gefaltet sein (Fortsetzungszeile mit Leerzeichen).
		expect(ics).toMatch(/X-HORIZONT[;:][^\r\n]*\r\n [A-Za-z0-9+/=]/i);
		expect(parseWorkflowIcs(ics)).toEqual(wf);
	});

	it('erzeugt byte-identisches ICS für denselben Zustand (deterministisch)', () => {
		const wf = workflow();
		expect(buildWorkflowIcs(wf)).toBe(buildWorkflowIcs(structuredClone(wf)));
	});
});

describe('buildWorkflowIcs – Standard-Properties', () => {
	it('setzt UID, SUMMARY, CATEGORIES und abgeleitete Zeiten', () => {
		const ics = buildWorkflowIcs(workflow());
		expect(prop(ics, 'UID')).toBe('wf-1@test');
		expect(prop(ics, 'SUMMARY')).toBe('Workflow: Umzug');
		expect(prop(ics, 'CATEGORIES')).toBe('HORIZONT');
		// DTSTAMP/LAST-MODIFIED aus createdAt/updatedAt (UTC), nicht „now".
		expect(prop(ics, 'DTSTAMP')).toBe('20251001T100000Z');
		expect(prop(ics, 'LAST-MODIFIED')).toBe('20251002T123000Z');
		expect(ics).toContain('BEGIN:VTODO');
	});

	it.each([
		[0, 'NEEDS-ACTION'],
		[0.5, 'IN-PROCESS'],
		[1, 'COMPLETED']
	])('leitet STATUS aus progress=%s ab (%s)', (progress, status) => {
		expect(prop(buildWorkflowIcs(workflow({ progress })), 'STATUS')).toBe(status);
	});

	it('setzt COMPLETED-Status und COMPLETED-Zeitmarke bei completedAt', () => {
		const ics = buildWorkflowIcs(workflow({ completedAt: Date.UTC(2025, 9, 3, 8, 0, 0), progress: 0.999 }));
		expect(prop(ics, 'STATUS')).toBe('COMPLETED');
		expect(prop(ics, 'COMPLETED')).toBe('20251003T080000Z');
	});

	it('rundet PERCENT-COMPLETE auf ganze Prozente', () => {
		expect(prop(buildWorkflowIcs(workflow({ progress: 0.334 })), 'PERCENT-COMPLETE')).toBe('33');
		expect(prop(buildWorkflowIcs(workflow({ progress: 0.336 })), 'PERCENT-COMPLETE')).toBe('34');
	});

	it('trägt das exakte base64(JSON)-Payload ein', () => {
		const wf = workflow();
		expect(prop(buildWorkflowIcs(wf), 'X-HORIZONT')).toBe(encodeWorkflow(wf));
	});

	it('schreibt menschenlesbare Schrittliste in DESCRIPTION', () => {
		const desc = prop(buildWorkflowIcs(workflow()), 'DESCRIPTION') ?? '';
		expect(desc).toContain('Workflow: Umzug');
		expect(desc).toContain('1/3 Schritte erledigt');
		expect(desc).toContain('[x] Kisten besorgen');
		expect(desc).toContain('[ ] Wohnung < kündigen >');
		expect(desc).toContain('aktuell');
		expect(desc).toContain('Notizen:');
	});
});

describe('parseWorkflowIcs – fehlertolerant', () => {
	it('liefert null bei komplett leerer Eingabe', () => {
		// Ical.parse('') liefert ein Component ohne jCal-Zweig; der Aufruf von
		// getAllSubcomponents liegt daher bewusst innerhalb des try.
		expect(parseWorkflowIcs('')).toBeNull();
	});

	it('liefert null bei kaputtem oder fremdem ICS', () => {
		expect(parseWorkflowIcs('kein ics')).toBeNull();
		expect(parseWorkflowIcs('BEGIN:VCALENDAR\r\nVERSION:2.0\r\nEND:VCALENDAR')).toBeNull();
		expect(
			parseWorkflowIcs('BEGIN:VCALENDAR\r\nBEGIN:VTODO\r\nUID:x\r\nSUMMARY:Fremd\r\nEND:VTODO\r\nEND:VCALENDAR')
		).toBeNull();
		// VEVENT statt VTODO → kein Workflow-Objekt
		expect(
			parseWorkflowIcs(
				'BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:x\r\nX-HORIZONT:' +
					encodeWorkflow(workflow()) +
					'\r\nEND:VEVENT\r\nEND:VCALENDAR'
			)
		).toBeNull();
	});

	it('liefert null, wenn das X-HORIZONT-Payload kein gültiger Workflow ist', () => {
		const ics =
			'BEGIN:VCALENDAR\r\nBEGIN:VTODO\r\nUID:x\r\nX-HORIZONT:' +
			Buffer.from('{"id":"","title":"x","steps":[]}', 'utf8').toString('base64') +
			'\r\nEND:VTODO\r\nEND:VCALENDAR';
		expect(parseWorkflowIcs(ics)).toBeNull();
	});
});

describe('decodeWorkflow', () => {
	it('rundekodiert verlustfrei', () => {
		const wf = workflow();
		expect(decodeWorkflow(encodeWorkflow(wf))).toEqual(wf);
	});

	it('liefert null bei Müll-Eingaben', () => {
		expect(decodeWorkflow('!!!keine-base64!!!')).toBeNull();
		expect(decodeWorkflow(Buffer.from('kein json', 'utf8').toString('base64'))).toBeNull();
		expect(decodeWorkflow(Buffer.from('"nur ein string"', 'utf8').toString('base64'))).toBeNull();
		expect(decodeWorkflow(Buffer.from('null', 'utf8').toString('base64'))).toBeNull();
	});

	it('verwirft Objekte ohne Pflichtfelder', () => {
		const b64 = (o: unknown) => Buffer.from(JSON.stringify(o), 'utf8').toString('base64');
		expect(decodeWorkflow(b64({ title: 'ohne id', steps: [] }))).toBeNull();
		expect(decodeWorkflow(b64({ id: 'a', title: 'ohne steps' }))).toBeNull();
		expect(decodeWorkflow(b64({ id: 'a', title: 't', steps: [{ title: 'ohne id' }] }))).toBeNull();
	});

	it('normalisiert fehlende optionale Felder', () => {
		const out = decodeWorkflow(
			Buffer.from(
				JSON.stringify({
					id: 'a',
					title: 't',
					steps: [{ id: 's', title: 'x', done: 'yes', completedAt: 'müll' }]
				}),
				'utf8'
			).toString('base64')
		);
		expect(out).toEqual({
			id: 'a',
			title: 't',
			notes: '',
			createdAt: 0,
			updatedAt: 0,
			completedAt: null,
			activeStepId: null,
			steps: [{ id: 's', title: 'x', done: true, completedAt: null }],
			progress: 0
		});
	});
});
