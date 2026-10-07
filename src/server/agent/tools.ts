// Tool-Schemas für den KI-Agent (OpenAI-Function-Calling-Format).
// Read-Tools werden direkt ausgeführt; Write-Tools erfordern eine
// Bestätigungs-Karte im Chat (siehe loop.ts).

import type { ToolDef } from './types';

const str = (d: string) => ({ type: 'string', description: d });
const num = (d: string) => ({ type: 'integer', description: d });

const calendarIdParam = str('ID des Kalenders (aus list_calendars)');
const uidParam = str('UID des Eintrags (aus search_events bzw. list_tasks)');

export const AGENT_TOOLS: ToolDef[] = [
	// ── Read: Kalender & Events ────────────────────────────────────────────
	{
		name: 'list_calendars',
		description: 'Alle Kalender des Users auflisten (mit ID, Name, Farbe, Verbindung). Vor create_event/create_task aufrufen, um die richtige calendarId zu bekommen.',
		parameters: { type: 'object', properties: {}, required: [] },
		effect: 'read'
	},
	{
		name: 'search_events',
		description:
			'Events des Users suchen/listen. query = Text im Titel/Ort/Beschreibung; fromMs/toMs = Zeitfenster (epoch ms, UTC), Standard: −30 bis +30 Tage. Liefert ID- und Zeitangaben für spätere Änderungen.',
		parameters: {
			type: 'object',
			properties: {
				query: str('Suchtext (optional)'),
				fromMs: num('Frühester Zeitpunkt, epoch ms (optional)'),
				toMs: num('Spätester Zeitpunkt, epoch ms (optional)'),
				limit: num('Max. Treffer, Standard 30, max 100')
			},
			required: []
		},
		effect: 'read'
	},
	{
		name: 'list_tasks',
		description: 'Aufgaben (Tasks) des Users auflisten. onlyOpen=true (Standard) blendet erledigte aus.',
		parameters: {
			type: 'object',
			properties: { onlyOpen: { type: 'boolean', description: 'Nur offene Aufgaben (Standard true)' } },
			required: []
		},
		effect: 'read'
	},
	{
		name: 'list_workflows',
		description: 'Workflows des Users auflisten (mit Schritten, Status, Fortschritt).',
		parameters: { type: 'object', properties: {}, required: [] },
		effect: 'read'
	},

	// ── Write: Events ──────────────────────────────────────────────────────
	{
		name: 'create_event',
		description:
			'Einen neuen Kalendereintrag anlegen. allDay=true → dayKey (YYYY-MM-DD, optional endDateKey für mehrere Tage). allDay=false → startMs/endMs (epoch ms, UTC; Endzeit muss nach Startzeit liegen).',
		parameters: {
			type: 'object',
			properties: {
				calendarId: calendarIdParam,
				summary: str('Titel des Termins'),
				location: str('Ort (optional)'),
				description: str('Beschreibung (optional)'),
				allDay: { type: 'boolean', description: 'Ganztägig?' },
				dayKey: str('Startdatum YYYY-MM-DD (Pflicht bei allDay=true)'),
				endDateKey: str('Enddatum YYYY-MM-DD, inklusiv (optional)'),
				startMs: num('Startzeit epoch ms UTC (Pflicht bei allDay=false)'),
				endMs: num('Endzeit epoch ms UTC, > startMs (Pflicht bei allDay=false)')
			},
			required: ['calendarId', 'summary', 'allDay']
		},
		effect: 'write'
	},
	{
		name: 'update_event',
		description:
			'Ein bestehendes Event vollständig aktualisieren (Felder, die nicht angegeben werden, bleiben leer). uid und calendarId aus search_events. Gleiche Zeit-Regeln wie create_event.',
		parameters: {
			type: 'object',
			properties: {
				calendarId: calendarIdParam,
				uid: uidParam,
				summary: str('Neuer Titel'),
				location: str('Neuer Ort (optional)'),
				description: str('Neue Beschreibung (optional)'),
				allDay: { type: 'boolean', description: 'Ganztägig?' },
				dayKey: str('Startdatum YYYY-MM-DD'),
				endDateKey: str('Enddatum YYYY-MM-DD, inklusiv (optional)'),
				startMs: num('Startzeit epoch ms UTC'),
				endMs: num('Endzeit epoch ms UTC, > startMs')
			},
			required: ['calendarId', 'uid', 'summary', 'allDay']
		},
		effect: 'write'
	},
	{
		name: 'delete_event',
		description: 'Ein Kalendereintrag löschen. uid und calendarId aus search_events.',
		parameters: {
			type: 'object',
			properties: { calendarId: calendarIdParam, uid: uidParam },
			required: ['calendarId', 'uid']
		},
		effect: 'write'
	},

	// ── Write: Tasks ───────────────────────────────────────────────────────
	{
		name: 'create_task',
		description:
			'Eine neue Aufgabe anlegen. calendarId optional (Default: erster Kalender). due: {kind:"none"} | {kind:"date", key:"YYYY-MM-DD"} | {kind:"time", ms: epoch ms}. priority 1=hoch … 9=niedrig (optional).',
		parameters: {
			type: 'object',
			properties: {
				calendarId: str('Kalender-ID (optional, Default: erster Kalender)'),
				summary: str('Aufgabentitel'),
				description: str('Details (optional)'),
				completed: { type: 'boolean', description: 'Erledigt? Standard false' },
				due: {
					type: 'object',
					description: 'Fälligkeitsdatum',
					properties: {
						kind: { type: 'string', enum: ['none', 'date', 'time'] },
						key: str('Datum YYYY-MM-DD (bei kind="date")'),
						ms: num('Zeitpunkt epoch ms (bei kind="time")')
					},
					required: ['kind']
				},
				priority: num('Priorität 1 (hoch) … 9 (niedrig)')
			},
			required: ['summary']
		},
		effect: 'write'
	},
	{
		name: 'update_task',
		description: 'Eine Aufgabe ändern (nur die angegebenen Felder). uid und calendarId aus list_tasks.',
		parameters: {
			type: 'object',
			properties: {
				calendarId: calendarIdParam,
				uid: uidParam,
				summary: str('Neuer Titel'),
				description: str('Neue Beschreibung'),
				completed: { type: 'boolean', description: 'Erledigt?' },
				due: {
					type: 'object',
					description: 'Fälligkeitsdatum ändern',
					properties: {
						kind: { type: 'string', enum: ['none', 'date', 'time'] },
						key: str('Datum YYYY-MM-DD'),
						ms: num('Zeitpunkt epoch ms')
					},
					required: ['kind']
				},
				priority: num('Priorität 1 (hoch) … 9 (niedrig)')
			},
			required: ['calendarId', 'uid']
		},
		effect: 'write'
	},
	{
		name: 'delete_task',
		description: 'Eine Aufgabe löschen. uid und calendarId aus list_tasks.',
		parameters: {
			type: 'object',
			properties: { calendarId: calendarIdParam, uid: uidParam },
			required: ['calendarId', 'uid']
		},
		effect: 'write'
	},

	// ── Write: Workflows ───────────────────────────────────────────────────
	{
		name: 'create_workflow',
		description: 'Einen neuen Workflow mit Schritten anlegen.',
		parameters: {
			type: 'object',
			properties: {
				title: str('Titel des Workflows'),
				steps: { type: 'array', items: str('Schritt-Titel'), description: 'Schritte in Reihenfolge' }
			},
			required: ['title', 'steps']
		},
		effect: 'write'
	},
	{
		name: 'update_workflow',
		description: 'Titel oder Notiz eines Workflows ändern. id aus list_workflows.',
		parameters: {
			type: 'object',
			properties: {
				id: str('Workflow-ID (aus list_workflows)'),
				title: str('Neuer Titel (optional)'),
				notes: str('Neue Notiz (optional)')
			},
			required: ['id']
		},
		effect: 'write'
	},
	{
		name: 'add_workflow_step',
		description: 'Einen Schritt an einen Workflow anhängen.',
		parameters: {
			type: 'object',
			properties: {
				id: str('Workflow-ID (aus list_workflows)'),
				title: str('Titel des neuen Schritts')
			},
			required: ['id', 'title']
		},
		effect: 'write'
	},
	{
		name: 'set_workflow_step',
		description: 'Einen Workflow-Schritt als erledigt markieren oder wieder öffnen.',
		parameters: {
			type: 'object',
			properties: {
				id: str('Workflow-ID (aus list_workflows)'),
				stepId: str('Schritt-ID (aus list_workflows)'),
				done: { type: 'boolean', description: 'true = erledigt, false = öffnen' }
			},
			required: ['id', 'stepId', 'done']
		},
		effect: 'write'
	},
	{
		name: 'delete_workflow',
		description: 'Einen Workflow mitsamt Schritten löschen.',
		parameters: {
			type: 'object',
			properties: { id: str('Workflow-ID (aus list_workflows)') },
			required: ['id']
		},
		effect: 'write'
	},
	{
		name: 'reset_workflow',
		description: 'Einen Workflow zurücksetzen (alle Schritte erneut offen).',
		parameters: {
			type: 'object',
			properties: { id: str('Workflow-ID (aus list_workflows)') },
			required: ['id']
		},
		effect: 'write'
	}
];

export const TOOL_BY_NAME: Map<string, ToolDef> = new Map(AGENT_TOOLS.map((t) => [t.name, t]));

/** Deutsch-Anzeige für die Approval-Karte. */
export const TOOL_LABELS: Record<string, string> = {
	list_calendars: 'Kalender auflisten',
	search_events: 'Events durchsuchen',
	list_tasks: 'Auflagen auflisten',
	list_workflows: 'Workflows auflisten',
	create_event: 'Termin anlegen',
	update_event: 'Termin ändern',
	delete_event: 'Termin löschen',
	create_task: 'Aufgabe anlegen',
	update_task: 'Aufgabe ändern',
	delete_task: 'Aufgabe löschen',
	create_workflow: 'Workflow anlegen',
	update_workflow: 'Workflow ändern',
	add_workflow_step: 'Schritt hinzufügen',
	set_workflow_step: 'Schritt abhaken',
	delete_workflow: 'Workflow löschen',
	reset_workflow: 'Workflow zurücksetzen'
};
