// Öffentliche OpenAPI-Spezifikation — Maschinendokumentation der /api-Endpunkte
// für externe Clients (z. B. T3 Code). Enthält keine sensiblen Daten, daher
// ohne Auth (Ausnahme im hooks.server.ts).

import { json } from '@sveltejs/kit';
import type { RequestHandler } from '@sveltejs/kit';

const spec = {
	openapi: '3.1.0',
	info: {
		title: 'Horizont API',
		version: '1.0.0',
		description:
			'Kalender, Termine und Tasks (CalDAV-Backend) des self-hosted Kalenders Horizont.\n\n' +
			'**Auth**: per-User API-Token im Header `Authorization: Bearer <token>` ' +
			'(Token: Horizont → Einstellungen → „API-Token (für T3 Code & Co.)“ → erzeugen). ' +
			'Ohne gültiges Token: HTTP 401.\n\n' +
			'**Fehler**: `{"error": "<Meldung>"}` — 400 (ungültige Eingaben), 401 (kein/ungültiges Token), ' +
			'404 (Kalender/Termine/Task nicht gefunden), 409 (Kollision), 502 (CalDAV-Backend nicht erreichbar).\n\n' +
			'**Workflows**: sequenzielle Aufgaben-Checklisten (eigene App-Funktion, kein CalDAV-Backend).'
	},
	security: [{ bearerAuth: [] }],
	components: {
		securitySchemes: {
			bearerAuth: {
				type: 'http',
				scheme: 'bearer',
				bearerFormat: 'horizont-api-token (hz_…)',
				description: 'Per-User API-Token, erzeugt in den Horizont-Einstellungen.'
			}
		},
		schemas: {
			Err: {
				type: 'object',
				properties: { error: { type: 'string', description: 'Menschenlesbare Fehlermeldung (Deutsch).' } }
			},
			CalDavCalendar: {
				type: 'object',
				properties: {
					id: { type: 'string', description: 'Stable Kalender-ID (Path-Parameter calendarId).' },
					name: { type: 'string' },
					color: { type: 'string', description: 'Hex-Farbe, z. B. #ff0000.' },
					url: { type: 'string' },
					connectionName: { type: 'string', description: 'Quelle, optional.' }
				}
			},
			CalendarsResponse: {
				type: 'object',
				properties: {
					configured: { type: 'boolean', description: 'false = keine CalDAV-Verbindung vorhanden.' },
					calendars: { type: 'array', items: { $ref: '#/components/schemas/CalDavCalendar' } }
				}
			},
			EventItem: {
				type: 'object',
				properties: {
					id: { type: 'string' },
					uid: { type: 'string', description: 'iCal-UID; zusammen mit calendarId Adresse für PATCH/DELETE.' },
					calendarId: { type: 'string' },
					calendarName: { type: 'string' },
					calendarColor: { type: 'string' },
					summary: { type: 'string', description: 'Titel.' },
					location: { type: 'string' },
					description: { type: 'string' },
					startMs: { type: 'integer', description: 'Unix epoch ms.' },
					endMs: { type: 'integer', description: 'Unix epoch ms.' },
					allDay: { type: 'boolean' }
				}
			},
			EventCreateInput: {
				type: 'object',
				required: ['calendarId', 'summary', 'allDay'],
				properties: {
					calendarId: { type: 'string', description: 'Aus GET /api/calendars.' },
					summary: { type: 'string', description: 'Titel.' },
					location: { type: 'string' },
					description: { type: 'string' },
					allDay: { type: 'boolean' },
					dayKey: { type: 'string', description: 'YYYY-MM-DD — eintägiger Termin (ohne allDay nur als Datum).' },
					endDateKey: { type: 'string', description: 'YYYY-MM-DD — letzter Tag eines mehr-tägigen Termins (inklusive).' },
					startMs: { type: 'integer', description: 'Unix epoch ms — bevorzugen, wenn Uhrzeit wichtig ist.' },
					endMs: { type: 'integer', description: 'Unix epoch ms.' }
				}
			},
			EventUpdateInput: {
				type: 'object',
				required: ['summary', 'allDay'],
				description: 'Alle Felder müssen mitgesendet werden (kein Partial-Patch).',
				properties: {
					summary: { type: 'string' },
					location: { type: 'string' },
					description: { type: 'string' },
					allDay: { type: 'boolean' },
					dayKey: { type: 'string', description: 'YYYY-MM-DD.' },
					endDateKey: { type: 'string', description: 'YYYY-MM-DD.' },
					startMs: { type: 'integer' },
					endMs: { type: 'integer' }
				}
			},
			DayGroup: {
				type: 'object',
				properties: {
					dayKey: { type: 'string', description: 'YYYY-MM-DD.' },
					label: { type: 'string' },
					isToday: { type: 'boolean' },
					events: { type: 'array', items: { $ref: '#/components/schemas/EventItem' } }
				}
			},
			MainEventsResponse: {
				type: 'object',
				description: 'Hauptansicht: Vergangenheit (14 Tage), Jetzt (heute + 2), Zukunft (30 Tage).',
				properties: {
					todayKey: { type: 'string' },
					generatedAt: { type: 'integer' },
					configured: { type: 'boolean' },
					error: { type: 'string' },
					panels: {
						type: 'array',
						items: {
							type: 'object',
							properties: {
								id: { type: 'string', enum: ['past', 'now', 'future'] },
								title: { type: 'string' },
								subtitle: { type: 'string' },
								eventCount: { type: 'integer' },
								defaultOpen: { type: 'boolean' },
								days: { type: 'array', items: { $ref: '#/components/schemas/DayGroup' } }
							}
						}
					}
				}
			},
			ArchiveMonth: {
				type: 'object',
				description: 'Archiv: bis zu 365 Tage zurück, als Monatsgrid (Tage mit Einträgen).',
				properties: {
					monthKey: { type: 'string', description: 'YYYY-MM.' },
					days: { type: 'array', items: { $ref: '#/components/schemas/DayGroup' } },
					eventCount: { type: 'integer' },
					rangeStart: { type: 'string' },
					rangeEnd: { type: 'string' },
					canPrev: { type: 'boolean' },
					canNext: { type: 'boolean' },
					configured: { type: 'boolean' },
					error: { type: 'string' }
				}
			},
			TaskItem: {
				type: 'object',
				properties: {
					id: { type: 'string' },
					uid: { type: 'string', description: 'iCal-UID; zusammen mit calendarId Adresse für PATCH/DELETE.' },
					calendarId: { type: 'string' },
					calendarName: { type: 'string' },
					calendarColor: { type: 'string' },
					summary: { type: 'string' },
					description: { type: 'string' },
					completed: { type: 'boolean' },
					dueKey: { type: 'string', description: 'YYYY-MM-DD, falls Datum ohne Uhrzeit.' },
					dueMs: { type: 'integer', description: 'Unix epoch ms, falls Uhrzeit gesetzt.' },
					priority: {
						type: 'integer',
						enum: [1, 5, 9],
						description: '1 = hoch, 5 = Schule, 9 = niedrig.'
					}
				}
			},
			TaskUpdateInput: {
				type: 'object',
				properties: {
					summary: { type: 'string' },
					description: { type: 'string' },
					completed: { type: 'boolean' },
					due: {
						oneOf: [
							{ type: 'object', properties: { kind: { const: 'none' } }, description: 'Fälligkeitsdatum entfernen.' },
							{ type: 'object', properties: { kind: { const: 'date' }, key: { type: 'string', description: 'YYYY-MM-DD.' } }, description: 'Datum ohne Uhrzeit.' },
							{ type: 'object', properties: { kind: { const: 'time' }, ms: { type: 'integer', description: 'Unix epoch ms.' } }, description: 'Datum + Uhrzeit.' }
						]
					},
					priority: { type: ['integer', 'null'], enum: [1, 5, 9, null], description: 'null = Priorität entfernen.' }
				}
			},
			TaskCreateInput: {
				allOf: [
					{ $ref: '#/components/schemas/TaskUpdateInput' },
					{
						type: 'object',
						required: ['summary', 'calendarId'],
						properties: {
							summary: { type: 'string' },
							calendarId: { type: 'string', description: 'Aus GET /api/calendars.' }
						}
					}
				]
			},
			TasksResponse: {
				type: 'object',
				properties: {
					configured: { type: 'boolean' },
					tasks: { type: 'array', items: { $ref: '#/components/schemas/TaskItem' } },
					error: { type: 'string' }
				}
			},
			Workflow: {
				type: 'object',
				description: 'Sequenzielle Aufgaben-Checkliste (Fokus-Modus-Backend).',
				properties: {
					id: { type: 'string' },
					title: { type: 'string' },
					notes: { type: 'string' },
					createdAt: { type: 'integer' },
					updatedAt: { type: 'integer' },
					completedAt: { type: ['integer', 'null'] },
					activeStepId: { type: ['string', 'null'] },
					progress: { type: 'number', description: '0..1.' },
					steps: {
						type: 'array',
						items: {
							type: 'object',
							properties: {
								id: { type: 'string' },
								title: { type: 'string' },
								done: { type: 'boolean' },
								completedAt: { type: ['integer', 'null'] }
							}
						}
					}
				}
			},
			CreateWorkflowInput: {
				type: 'object',
				required: ['title', 'steps'],
				properties: {
					title: { type: 'string' },
					steps: { type: 'array', items: { type: 'string' }, description: 'Schritt-Titel in Reihenfolge.' }
				}
			},
			UpdateWorkflowInput: {
				type: 'object',
				properties: { title: { type: 'string' }, notes: { type: 'string' } }
			},
			UpdateStepInput: {
				type: 'object',
				properties: { title: { type: 'string' }, done: { type: 'boolean' } }
			},
			ApiTokenView: {
				type: 'object',
				properties: {
					hasToken: { type: 'boolean' },
					createdAt: { type: ['integer', 'null'] },
					lastUsedAt: { type: ['integer', 'null'] }
				}
			},
			ApiTokenGenerated: {
				type: 'object',
				description: 'Der Klartext-Token wird nur einmal geliefert — sofort speichern.',
				properties: { token: { type: 'string' }, createdAt: { type: 'integer' } }
			}
		}
	},
	paths: {
		'/api/calendars': {
			get: {
				summary: 'Alle CalDAV-Kalender des Users auflisten',
				responses: {
					'200': { description: 'OK', content: { 'application/json': { schema: { $ref: '#/components/schemas/CalendarsResponse' } } } },
					'401': { description: 'Kein/ungültiges Token' }
				}
			}
		},
		'/api/events': {
			get: {
				summary: 'Termine lesen',
				parameters: [
					{
						name: 'scope',
						in: 'query',
						schema: { type: 'string', enum: ['main', 'archive'], default: 'main' },
						description: 'main = Vergangenheit/Jetzt/Zukunft, archive = Monatsansicht (bis 365 Tage zurück).'
					},
					{
						name: 'monat',
						in: 'query',
						schema: { type: 'string', description: 'YYYY-MM (nur scope=archive; fehlt = neuester Archiv-Monat).' }
					}
				],
				responses: {
					'200': {
						description: 'OK',
						content: {
							'application/json': {
								schema: {
									oneOf: [
										{ $ref: '#/components/schemas/MainEventsResponse' },
										{ $ref: '#/components/schemas/ArchiveMonth' }
									]
								}
							}
						}
					},
					'401': { description: 'Kein/ungültiges Token' }
				}
			},
			post: {
				summary: 'Neuen Termin anlegen',
				requestBody: {
					required: true,
					content: { 'application/json': { schema: { $ref: '#/components/schemas/EventCreateInput' } } }
				},
				responses: {
					'201': { description: 'Angelegt', content: { 'application/json': { schema: { $ref: '#/components/schemas/EventItem' } } } },
					'400': { $ref: '#/components/responses/BadRequest' },
					'401': { description: 'Kein/ungültiges Token' },
					'404': { $ref: '#/components/responses/NotFound' },
					'502': { description: 'CalDAV-Backend nicht erreichbar' }
				}
			}
		},
		'/api/events/{calendarId}/{uid}': {
			parameters: [
				{ name: 'calendarId', in: 'path', required: true, schema: { type: 'string' } },
				{ name: 'uid', in: 'path', required: true, schema: { type: 'string' } }
			],
			patch: {
				summary: 'Termin bearbeiten (volle Update — alle Felder mitsenden)',
				requestBody: {
					required: true,
					content: { 'application/json': { schema: { $ref: '#/components/schemas/EventUpdateInput' } } }
				},
				responses: {
					'200': { description: 'Aktualisiert', content: { 'application/json': { schema: { $ref: '#/components/schemas/EventItem' } } } },
					'400': { $ref: '#/components/responses/BadRequest' },
					'401': { description: 'Kein/ungültiges Token' },
					'404': { $ref: '#/components/responses/NotFound' },
					'409': { description: 'Kollision beim Schreiben' },
					'502': { description: 'CalDAV-Backend nicht erreichbar' }
				}
			},
			delete: {
				summary: 'Termin löschen',
				responses: {
					'200': { description: 'Gelöscht', content: { 'application/json': { schema: { type: 'object', properties: { ok: { type: 'boolean' } } } } } },
					'401': { description: 'Kein/ungültiges Token' },
					'404': { $ref: '#/components/responses/NotFound' },
					'502': { description: 'CalDAV-Backend nicht erreichbar' }
				}
			}
		},
		'/api/tasks': {
			get: {
				summary: 'Alle VTODO-Tasks des Users auflisten',
				responses: {
					'200': { description: 'OK', content: { 'application/json': { schema: { $ref: '#/components/schemas/TasksResponse' } } } },
					'401': { description: 'Kein/ungültiges Token' }
				}
			},
			post: {
				summary: 'Neuen Task anlegen',
				requestBody: {
					required: true,
					content: { 'application/json': { schema: { $ref: '#/components/schemas/TaskCreateInput' } } }
				},
				responses: {
					'201': { description: 'Angelegt', content: { 'application/json': { schema: { $ref: '#/components/schemas/TaskItem' } } } },
					'400': { $ref: '#/components/responses/BadRequest' },
					'401': { description: 'Kein/ungültiges Token' },
					'404': { $ref: '#/components/responses/NotFound' },
					'502': { description: 'CalDAV-Backend nicht erreichbar' }
				}
			}
		},
		'/api/tasks/{calendarId}/{uid}': {
			parameters: [
				{ name: 'calendarId', in: 'path', required: true, schema: { type: 'string' } },
				{ name: 'uid', in: 'path', required: true, schema: { type: 'string' } }
			],
			patch: {
				summary: 'Task bearbeiten (z. B. abhaken: {"completed": true})',
				requestBody: {
					required: true,
					content: { 'application/json': { schema: { $ref: '#/components/schemas/TaskUpdateInput' } } }
				},
				responses: {
					'200': { description: 'Aktualisiert', content: { 'application/json': { schema: { $ref: '#/components/schemas/TaskItem' } } } },
					'400': { $ref: '#/components/responses/BadRequest' },
					'401': { description: 'Kein/ungültiges Token' },
					'404': { $ref: '#/components/responses/NotFound' },
					'502': { description: 'CalDAV-Backend nicht erreichbar' }
				}
			},
			delete: {
				summary: 'Task löschen',
				responses: {
					'200': { description: 'Gelöscht', content: { 'application/json': { schema: { type: 'object', properties: { ok: { type: 'boolean' } } } } } },
					'401': { description: 'Kein/ungültiges Token' },
					'404': { $ref: '#/components/responses/NotFound' },
					'502': { description: 'CalDAV-Backend nicht erreichbar' }
				}
			}
		},
		'/api/workflows': {
			get: {
				summary: 'Alle Workflows (Checklisten) auflisten',
				responses: {
					'200': { description: 'OK', content: { 'application/json': { schema: { type: 'array', items: { $ref: '#/components/schemas/Workflow' } } } } },
					'401': { description: 'Kein/ungültiges Token' }
				}
			},
			post: {
				summary: 'Neuen Workflow anlegen',
				requestBody: { required: true, content: { 'application/json': { schema: { $ref: '#/components/schemas/CreateWorkflowInput' } } } },
				responses: {
					'201': { description: 'Angelegt', content: { 'application/json': { schema: { $ref: '#/components/schemas/Workflow' } } } },
					'400': { $ref: '#/components/responses/BadRequest' },
					'401': { description: 'Kein/ungültiges Token' }
				}
			}
		},
		'/api/workflows/{id}': {
			parameters: [{ name: 'id', in: 'path', required: true, schema: { type: 'string' } }],
			get: {
				summary: 'Workflow laden',
				responses: {
					'200': { description: 'OK', content: { 'application/json': { schema: { $ref: '#/components/schemas/Workflow' } } } },
					'401': { description: 'Kein/ungültiges Token' },
					'404': { $ref: '#/components/responses/NotFound' }
				}
			},
			patch: {
				summary: 'Workflow-Titel/Notizen ändern',
				requestBody: { required: true, content: { 'application/json': { schema: { $ref: '#/components/schemas/UpdateWorkflowInput' } } } },
				responses: {
					'200': { description: 'Aktualisiert', content: { 'application/json': { schema: { $ref: '#/components/schemas/Workflow' } } } },
					'400': { $ref: '#/components/responses/BadRequest' },
					'401': { description: 'Kein/ungültiges Token' },
					'404': { $ref: '#/components/responses/NotFound' }
				}
			},
			delete: {
				summary: 'Workflow löschen',
				responses: {
					'200': { description: 'Gelöscht', content: { 'application/json': { schema: { type: 'object', properties: { ok: { type: 'boolean' } } } } } },
					'401': { description: 'Kein/ungültiges Token' },
					'404': { $ref: '#/components/responses/NotFound' }
				}
			}
		},
		'/api/workflows/{id}/steps': {
			parameters: [{ name: 'id', in: 'path', required: true, schema: { type: 'string' } }],
			post: {
				summary: 'Schritt anhängen (Body: {"title": "…"})',
				responses: {
					'201': { description: 'Angelegt', content: { 'application/json': { schema: { $ref: '#/components/schemas/Workflow' } } } },
					'400': { $ref: '#/components/responses/BadRequest' },
					'401': { description: 'Kein/ungültiges Token' },
					'404': { $ref: '#/components/responses/NotFound' }
				}
			}
		},
		'/api/workflows/{id}/steps/{stepId}': {
			parameters: [
				{ name: 'id', in: 'path', required: true, schema: { type: 'string' } },
				{ name: 'stepId', in: 'path', required: true, schema: { type: 'string' } }
			],
			patch: {
				summary: 'Schritt bearbeiten (z. B. erledigen: {"done": true})',
				requestBody: { required: true, content: { 'application/json': { schema: { $ref: '#/components/schemas/UpdateStepInput' } } } },
				responses: {
					'200': { description: 'Aktualisiert', content: { 'application/json': { schema: { $ref: '#/components/schemas/Workflow' } } } },
					'400': { $ref: '#/components/responses/BadRequest' },
					'401': { description: 'Kein/ungültiges Token' },
					'404': { $ref: '#/components/responses/NotFound' }
				}
			},
			delete: {
				summary: 'Schritt löschen',
				responses: {
					'200': { description: 'Gelöscht', content: { 'application/json': { schema: { $ref: '#/components/schemas/Workflow' } } } },
					'401': { description: 'Kein/ungültiges Token' },
					'404': { $ref: '#/components/responses/NotFound' }
				}
			}
		},
		'/api/workflows/{id}/reset': {
			parameters: [{ name: 'id', in: 'path', required: true, schema: { type: 'string' } }],
			post: {
				summary: 'Workflow zurücksetzen (alle Schritte offen)',
				responses: {
					'200': { description: 'Zurückgesetzt', content: { 'application/json': { schema: { $ref: '#/components/schemas/Workflow' } } } },
					'401': { description: 'Kein/ungültiges Token' },
					'404': { $ref: '#/components/responses/NotFound' }
				}
			}
		},
		'/api/token': {
			security: [],
			'x-auth': 'Browser-Session (Login-Cookie), kein API-Token — das Endpoint verwaltet gerade den Token selbst.',
			get: {
				summary: 'Token-Status',
				responses: {
					'200': { description: 'OK', content: { 'application/json': { schema: { $ref: '#/components/schemas/ApiTokenView' } } } },
					'401': { description: 'Nicht angemeldet' }
				}
			},
			post: {
				summary: 'Neuen Token erzeugen (ersetzt vorhandenen) — Klartext nur einmal',
				responses: {
					'201': { description: 'Erzeugt', content: { 'application/json': { schema: { $ref: '#/components/schemas/ApiTokenGenerated' } } } },
					'401': { description: 'Nicht angemeldet' }
				}
			},
			delete: {
				summary: 'Token ablehnen',
				responses: {
					'200': { description: 'Abgelehnt', content: { 'application/json': { schema: { type: 'object', properties: { ok: { type: 'boolean' } } } } } },
					'401': { description: 'Nicht angemeldet' }
				}
			}
		}
	},
	responses: {
		BadRequest: {
			description: 'Ungültige Eingaben',
			content: { 'application/json': { schema: { $ref: '#/components/schemas/Err' } } }
		},
		NotFound: {
			description: 'Ressource nicht gefunden',
			content: { 'application/json': { schema: { $ref: '#/components/schemas/Err' } } }
		}
	}
};

export const GET: RequestHandler = () =>
	json(spec, { headers: { 'Content-Type': 'application/openapi+json' } });
