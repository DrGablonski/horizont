// Client-seitiger API-Zugriff auf die /api-Endpunkte.

import type {
	ArchivePage,
	CalDavSettings,
	CalDavSettingsView,
	CalendarsResponse,
	CreateWorkflowInput,
	EventCreateInput,
	EventItem,
	EventUpdateInput,
	MainEventsResponse,
	TasksResponse,
	TaskCreateInput,
	TaskItem,
	TaskUpdateInput,
	TestResult,
	UpdateStepInput,
	UpdateWorkflowInput,
	Workflow
} from './types';

async function req<T>(path: string, init?: RequestInit): Promise<T> {
	const res = await fetch(path, {
		headers: { 'Content-Type': 'application/json' },
		...init
	});
	if (!res.ok) {
		let msg = `HTTP ${res.status}`;
		try {
			const body = (await res.json()) as { error?: string };
			if (body && body.error) msg = body.error;
		} catch {
			/* body war kein JSON */
		}
		throw new Error(msg);
	}
	return (await res.json()) as T;
}

export const api = {
	// Events
	mainEvents: () => req<MainEventsResponse>('/api/events?scope=main'),
	archive: (page: number) =>
		req<ArchivePage>(`/api/events?scope=archive&page=${encodeURIComponent(page)}`),

	// Einstellungen
	getSettings: () => req<CalDavSettingsView>('/api/settings'),
	saveSettings: (s: CalDavSettings) =>
		req<CalDavSettingsView>('/api/settings', { method: 'POST', body: JSON.stringify(s) }),
	testSettings: (s?: CalDavSettings) =>
		req<TestResult>('/api/settings/test', { method: 'POST', body: JSON.stringify(s ?? {}) }),

	// Workflows
	workflows: () => req<Workflow[]>('/api/workflows'),
	workflow: (id: string) => req<Workflow>(`/api/workflows/${encodeURIComponent(id)}`),
	createWorkflow: (input: CreateWorkflowInput) =>
		req<Workflow>('/api/workflows', { method: 'POST', body: JSON.stringify(input) }),
	updateWorkflow: (id: string, input: UpdateWorkflowInput) =>
		req<Workflow>(`/api/workflows/${encodeURIComponent(id)}`, {
			method: 'PATCH',
			body: JSON.stringify(input)
		}),
	deleteWorkflow: (id: string) =>
		req<{ ok: true }>(`/api/workflows/${encodeURIComponent(id)}`, { method: 'DELETE' }),
	addStep: (id: string, title: string) =>
		req<Workflow>(`/api/workflows/${encodeURIComponent(id)}/steps`, {
			method: 'POST',
			body: JSON.stringify({ title })
		}),
	updateStep: (id: string, stepId: string, input: UpdateStepInput) =>
		req<Workflow>(
			`/api/workflows/${encodeURIComponent(id)}/steps/${encodeURIComponent(stepId)}`,
			{ method: 'PATCH', body: JSON.stringify(input) }
		),
	deleteStep: (id: string, stepId: string) =>
		req<Workflow>(
			`/api/workflows/${encodeURIComponent(id)}/steps/${encodeURIComponent(stepId)}`,
			{ method: 'DELETE' }
		),
	resetWorkflow: (id: string) =>
		req<Workflow>(`/api/workflows/${encodeURIComponent(id)}/reset`, { method: 'POST' }),

	// Kalendare
	calendars: () => req<CalendarsResponse>('/api/calendars'),

	// Event-CRUD
	createEvent: (input: EventCreateInput) =>
		req<EventItem>('/api/events', { method: 'POST', body: JSON.stringify(input) }),
	updateEvent: (calendarId: string, uid: string, input: EventUpdateInput) =>
		req<EventItem>(`/api/events/${encodeURIComponent(calendarId)}/${encodeURIComponent(uid)}`, {
			method: 'PATCH',
			body: JSON.stringify(input)
		}),
	deleteEvent: (calendarId: string, uid: string) =>
		req<{ ok: true }>(`/api/events/${encodeURIComponent(calendarId)}/${encodeURIComponent(uid)}`, {
			method: 'DELETE'
		}),

	// Tasks
	tasks: () => req<TasksResponse>('/api/tasks'),
	createTask: (input: TaskCreateInput) =>
		req<TaskItem>('/api/tasks', { method: 'POST', body: JSON.stringify(input) }),
	updateTask: (calendarId: string, uid: string, input: TaskUpdateInput) =>
		req<TaskItem>(`/api/tasks/${encodeURIComponent(calendarId)}/${encodeURIComponent(uid)}`, {
			method: 'PATCH',
			body: JSON.stringify(input)
		}),
	deleteTask: (calendarId: string, uid: string) =>
		req<{ ok: true }>(`/api/tasks/${encodeURIComponent(calendarId)}/${encodeURIComponent(uid)}`, {
			method: 'DELETE'
		})
};
