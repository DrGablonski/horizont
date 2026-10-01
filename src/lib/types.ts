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
