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
	/** Basis-URL des Radicale-Servers, z. B. http://192.168.1.135:5232 */
	baseUrl: string;
	/** Admin-API (caldav-admin-Sidecar), z. B. http://192.168.1.135:5233 */
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

export interface ArchivePage {
	page: number;
	hasMore: boolean;
	eventCount: number;
	days: DayGroup[];
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
	priority?: number; // 1=high, 5=normal, 9=low
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
	priority?: number | null;
}

export interface TaskCreateInput extends TaskUpdateInput {
	summary: string;
	calendarId: string;
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

// ── KI-Agent ──────────────────────────────────────────────────────────────

export type AgentProvider = 'openai' | 'ollama';

/** LLM-Endpoint-Konfiguration (Secrets niemals in Views). */
export interface AgentConfig {
	provider: AgentProvider;
	/** z. B. https://api.openai.com/v1 oder http://192.168.1.x:11434 */
	baseUrl: string;
	model: string;
	apiKey?: string;
}

/** View ohne API-Key. */
export interface AgentConfigView {
	configured: boolean;
	/** KI-Funktionen für diesen User komplett an/aus. */
	enabled: boolean;
	provider: AgentProvider;
	baseUrl: string;
	model: string;
	hasApiKey: boolean;
}

/** Sichtbarkeit/Quelle für den Chat-Widget (GET /api/agent). */
export interface AgentStatus {
	available: boolean;
	source: 'user' | 'global' | null;
	provider: AgentProvider | null;
	model: string | null;
	baseUrl: string | null;
}

/** Eigene User-Konfiguration + Global-Status (GET /api/agent/settings). */
export interface AgentSettingsView {
	own: AgentConfigView;
	global: {
		enabled: boolean;
		configured: boolean;
		provider: AgentProvider;
		baseUrl: string;
		model: string;
	};
}
