// Gemeinsame Typen (Client + Server)

// ── CalDAV ────────────────────────────────────────────────────────────────

export interface CalDavSettings {
	url: string;
	username: string;
	password: string;
}

export interface CalDavSettingsView {
	configured: boolean;
	url: string;
	username: string;
	hasPassword: boolean;
}

export interface CalDavCalendar {
	id: string;
	name: string;
	color: string;
	url: string;
}

export interface TestResult {
	ok: boolean;
	error?: string;
	calendars: CalDavCalendar[];
	eventCount: number;
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
