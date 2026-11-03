// Gemeinsame Typen (Client + Server)

// ── Auth ──────────────────────────────────────────────────────────────────

export type UserRole = 'admin' | 'user';

/** Öffentliche User-Daten (ohne Hashes). */
export interface AppUser {
	id: string;
	username: string;
	role: UserRole;
	createdAt: number;
	lastLoginAt: number | null;
}

/** Admin-View eines Users (zusätzliche Felder). */
export interface AdminUserView extends AppUser {
	disabled: boolean;
	/** Hat der User eine zugewiesene CalDAV-Verbindung? */
	hasAssignedConnection: boolean;
}

/** Ergebnis einer User-Anlage: CalDAV-Handover für die Übergabe an den User. */
export interface CaldavHandover {
	url: string;
	username: string;
	password: string;
}

export interface CreateUserResult {
	user: AppUser;
	caldav: CaldavHandover | null;
}

/** Ergebnis des Setups: angelegter Admin + (optional) CalDAV-Handover. */
export interface SetupResult {
	ok: true;
	user: AppUser;
	/** CalDAV-Zugangsdaten des Admins, falls im Setup eine System-CalDAV hinterlegt wurde. */
	caldav: CaldavHandover | null;
	/** Fehlermeldung, falls die CalDAV-Anlage während des Setups fehlschlug (Setup selbst erfolgreich). */
	caldavError: string | null;
}

// ── CalDAV-Verbindungen (Multi-Connection pro User) ──────────────────────

/** Eine einzelne CalDAV-Verbindung (Credentials + Ziel). */
export interface CalDavSettings {
	url: string;
	username: string;
	password: string;
}

export type ConnectionKind = 'assigned' | 'external';

/** Eine gespeicherte Verbindung eines Users. `assigned` = vom Admin zugewiesen (read-only). */
export interface CalDavConnection extends CalDavSettings {
	id: string;
	name: string;
	kind: ConnectionKind;
}

/** View einer Verbindung ohne Klartext-Passwort. */
export interface ConnectionView {
	id: string;
	name: string;
	kind: ConnectionKind;
	url: string;
	username: string;
	hasPassword: boolean;
}

export interface ConnectionsResponse {
	configured: boolean;
	connections: ConnectionView[];
}

/** System-CALDAV (Admin-Konfiguration für User-Anlage/-Löschung). */
export interface SystemCaldavConfig {
	/** Basis-URL des Radicale-Servers, z. B. http://RADICALE:5232 */
	baseUrl: string;
	/** Admin-API (caldav-admin-Sidecar), z. B. http://RADICALE:5233 */
	adminApiUrl: string;
	adminToken: string;
}

export interface SystemCaldavConfigView {
	configured: boolean;
	baseUrl: string;
	adminApiUrl: string;
	hasToken: boolean;
}

/** Ergebnis einer (rückwirkenden) CalDAV-Provisionierung für die bestehenden Users. */
export interface ProvisionSummary {
	/** User, für die ein CalDAV-Account neu angelegt wurde. */
	provisioned: string[];
	/** User, die übersprungen wurden (bereits zugewiesen / deaktiviert / keine Config). */
	skipped: string[];
	/** User, deren CalDAV-Anlage fehlschlug (inkl. Fehlerursache). */
	failed: { username: string; error: string }[];
}

/**
 * Antwort beim Speichern der System-CalDAV-Konfiguration: die Config-View plus
 * das Ergebnis der rückwirkenden Provisionierung für bestehende Users.
 */
export interface SystemCaldavSaveResult extends SystemCaldavConfigView {
	provisioning: ProvisionSummary;
}

export interface TestResult {
	ok: boolean;
	error?: string;
	calendars: CalDavCalendar[];
	eventCount: number;
}

export interface CalDavCalendar {
	id: string;
	name: string;
	color: string;
	url: string;
	/** Name der Verbindung, aus der dieser Kalender stammt (Multi-Connection). */
	connectionName?: string;
}

// ── Events ────────────────────────────────────────────────────────────────

export interface EventItem {
	id: string;
	uid: string;
	calendarId: string;
	calendarName: string;
	calendarColor: string;
	summary: string;
	location?: string;
	description?: string;
	startMs: number;
	endMs: number;
	allDay: boolean;
	/** 'task' = CalDAV-Aufgabe (VTODO), mitten in der Timeline angezeigt. */
	kind?: 'event' | 'task';
	/** Nur Tasks: erledigt? */
	completed?: boolean;
	/** Nur Tasks: Kategorie (CalDAV CATEGORIES) + Farbe. */
	category?: string;
	categoryColor?: string;
	/** Nur Tasks: Fälligkeit (für den Task-Editor). */
	dueKey?: string;
	dueMs?: number;
}

export interface DayGroup {
	dayKey: string; // YYYY-MM-DD
	label: string;
	isToday: boolean;
	events: EventItem[];
}

export type PanelId = 'past' | 'now' | 'future';

export interface TimePanel {
	id: PanelId;
	title: string;
	subtitle: string;
	days: DayGroup[];
	eventCount: number;
	defaultOpen: boolean;
}

export interface MainEventsResponse {
	todayKey: string;
	generatedAt: number;
	panels: TimePanel[];
	configured: boolean;
	error?: string;
}

export interface ArchiveMonth {
	/** Tatsächlich gezeigter Monat (YYYY-MM), nach Klemmung in den Archivbereich. */
	monthKey: string;
	/** Tage mit Einträgen, decken das Monats-Raster (inkl. angrenzender Tage) ab. */
	days: DayGroup[];
	/** Anzahl der Einträge innerhalb des Monats. */
	eventCount: number;
	/** Ältester Tag des Archivs (YYYY-MM-DD). */
	rangeStart: string;
	/** Neuester Tag des Archivs (YYYY-MM-DD, inklusiv). */
	rangeEnd: string;
	canPrev: boolean;
	canNext: boolean;
	configured: boolean;
	error?: string;
}

// ── Workflows ─────────────────────────────────────────────────────────────

export interface WorkflowStep {
	id: string;
	title: string;
	done: boolean;
	completedAt: number | null;
}

export interface Workflow {
	id: string;
	title: string;
	notes: string;
	createdAt: number;
	updatedAt: number;
	completedAt: number | null;
	activeStepId: string | null;
	steps: WorkflowStep[];
	progress: number; // 0..1
}

export interface CreateWorkflowInput {
	title: string;
	steps: string[];
}

export interface UpdateWorkflowInput {
	title?: string;
	notes?: string;
}

export interface UpdateStepInput {
	title?: string;
	done?: boolean;
}

// ── Tasks ─────────────────────────────────────────────────────────────────

/** Kategorie-Definition (Name + Farbe), verwaltet pro User. */
export interface TaskCategory {
	name: string; // eindeutig (case-insensitive), 1–40 Zeichen
	color: string; // #rrggbb
}

export interface TaskItem {
	id: string;
	uid: string;
	calendarId: string;
	calendarName: string;
	calendarColor: string;
	summary: string;
	description?: string;
	completed: boolean;
	dueKey?: string; // YYYY-MM-DD (date-only)
	dueMs?: number; // epoch ms (date-time)
	category?: string; // Kategoriename (CalDAV CATEGORIES)
	/** Alt: CalDAV-Priorität (1=hoch … 9=niedrig); nur lesend, durch Kategorien ersetzt. */
	priority?: number;
}

export interface TasksResponse {
	configured: boolean;
	tasks: TaskItem[];
	error?: string;
}

export type TaskDueInput =
	| { kind: 'none' }
	| { kind: 'date'; key: string }
	| { kind: 'time'; ms: number };

export interface TaskUpdateInput {
	summary?: string;
	description?: string;
	completed?: boolean;
	due?: TaskDueInput;
	/** Kategoriename; null = Kategorie entfernen. */
	category?: string | null;
}

export interface TaskCreateInput extends TaskUpdateInput {
	summary: string;
	calendarId: string;
}

// ── Notify (Tägliche Tasks-Benachrichtigung per Webhook) ──────────────────

/** Per-User-Webhook-Config (serverseitig; wird nicht an den Client gesendet). */
export interface NotifyConfig {
	enabled: boolean;
	time: string; // lokale Uhrzeit HH:MM, z. B. "15:00"
	url: string; // Webhook-URL bis zur Task-ID (ohne Token), z. B. http://…/api/hooks/scheduled-task%3A…
	token: string; // Webhook-Token (letztes Pfadsegment der vollständigen URL)
	prompt: string; // Nachrichten-Template: {{body}} = Task-Liste, {{stand}} = Datum/Uhrzeit + Anzahl
	/** Kategoriennamen, die gesendet werden. */
	categories: string[];
}

/** Letzter Lauf des Notify-Jobs. */
export interface NotifyLastRun {
	date: string; // YYYY-MM-DD (lokal)
	status: 'ok' | 'skipped' | 'error';
	error?: string;
	at?: number;
}

/** View für den Client (ohne den rohen Token). */
export interface NotifyConfigView {
	enabled: boolean;
	time: string;
	/** Gespeicherte Basis-URL (nicht sensibel, für das Formular zur Bearbeitung). */
	url: string | null;
	hasToken: boolean;
	prompt: string;
	categories: string[];
	lastRun: NotifyLastRun | null;
}

export interface NotifySaveInput {
	enabled: boolean;
	time: string;
	/** Leer/fehlend: gespeicherten Wert beibehalten. */
	url?: string;
	token?: string;
	prompt?: string;
	/** Kategoriennamen, die gesendet werden (fehlend: gespeicherte behalten). */
	categories?: string[];
}

export interface NotifyTestResult {
	ok: boolean;
	status?: number;
	/** optionales Ergebnis des Empfängers (Header x-t3-hook-outcome), z. B. "accepted". */
	outcome?: string;
	error?: string;
}

// ── API-Token (Maschinen-Auth für /api/*, z. B. externe Tools/MCP) ────────

export interface ApiTokenView {
	hasToken: boolean;
	createdAt: number | null;
	lastUsedAt: number | null;
}

/** Antwort auf POST /api/token — der Klartext-Token wird nur einmal geliefert. */
export interface ApiTokenGenerated {
	token: string;
	createdAt: number;
}

// ── Event-Write ───────────────────────────────────────────────────────────

export interface EventUpdateInput {
	summary: string;
	location?: string;
	description?: string;
	allDay: boolean;
	dayKey?: string;
	endDateKey?: string;
	startMs?: number;
	endMs?: number;
}

export interface EventCreateInput extends EventUpdateInput {
	calendarId: string;
}

// ── Calendars ─────────────────────────────────────────────────────────────

export interface CalendarsResponse {
	configured: boolean;
	calendars: CalDavCalendar[];
	error?: string;
}
