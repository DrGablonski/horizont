// Client-seitiger API-Zugriff auf die /api-Endpunkte.

import type {
	AdminUserView,
	ApiTokenGenerated,
	ApiTokenView,
	ArchiveMonth,
	CalendarsResponse,
	ConnectionsResponse,
	CreateUserResult,
	CreateWorkflowInput,
	AppUser,
	CalDavSettings,
	EventCreateInput,
	EventItem,
	EventUpdateInput,
	MainEventsResponse,
	SetupResult,
	SystemCaldavConfigView,
	SystemCaldavSaveResult,
	NotifyConfigView,
	NotifySaveInput,
	NotifyTestResult,
	TasksResponse,
	TaskCategory,
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

export interface LoginInput {
	username: string;
	password: string;
}

export interface SetupInput {
	username: string;
	password: string;
	/** Optional: System-CalDAV-Konfiguration (Basis-URL + Admin-API-URL). */
	caldav?: { baseUrl: string; adminApiUrl: string; adminToken?: string };
}

export interface AdminUserPatch {
	role?: 'admin' | 'user';
	disabled?: boolean;
	password?: string;
	caldav?: CalDavSettings | null;
}

export interface AdminSystemCaldavInput {
	baseUrl: string;
	adminApiUrl: string;
	adminToken?: string;
}

export interface ExternalConnectionInput {
	id?: string;
	name?: string;
	url: string;
	username: string;
	password?: string;
}

export const api = {
	// Auth
	login: (input: LoginInput) =>
		req<{ ok: true; user: AppUser }>('/api/auth/login', {
			method: 'POST',
			body: JSON.stringify(input)
		}),
	logout: () => req<{ ok: true }>('/api/auth/logout', { method: 'POST' }),
	// Der Endpunkt liefert `{ user }` — hier wird der User entpackt.
	me: async () => {
		const data = await req<{ user: AppUser }>('/api/auth/me');
		return data.user;
	},
	setup: (input: SetupInput) => req<SetupResult>('/api/auth/setup', { method: 'POST', body: JSON.stringify(input) }),

	// Admin: Users
	adminUsers: () => req<{ users: AdminUserView[]; systemCaldav: SystemCaldavConfigView }>('/api/admin/users'),
	adminCreateUser: (input: { username: string; password: string }) =>
		req<CreateUserResult>('/api/admin/users', { method: 'POST', body: JSON.stringify(input) }),
	adminPatchUser: (id: string, patch: AdminUserPatch) =>
		req<AppUser>(`/api/admin/users/${encodeURIComponent(id)}`, { method: 'PATCH', body: JSON.stringify(patch) }),
	adminDeleteUser: (id: string) =>
		req<{ ok: true }>(`/api/admin/users/${encodeURIComponent(id)}`, { method: 'DELETE' }),

	// Admin: System-CALDAV
	adminCaldav: () => req<SystemCaldavConfigView>('/api/admin/caldav'),
	adminSaveCaldav: (input: AdminSystemCaldavInput) =>
		req<SystemCaldavSaveResult>('/api/admin/caldav', { method: 'POST', body: JSON.stringify(input) }),
	adminTestCaldav: (input?: { baseUrl?: string; adminApiUrl?: string; adminToken?: string }) =>
		req<{ ok: boolean; error?: string }>('/api/admin/caldav/test', {
			method: 'POST',
			body: JSON.stringify(input ?? {})
		}),

	// Verbindungen (pro User)
	connections: () => req<ConnectionsResponse>('/api/settings'),
	createConnection: (input: Omit<ExternalConnectionInput, 'id'>) =>
		req<ConnectionsResponse>('/api/settings', { method: 'POST', body: JSON.stringify(input) }),
	updateConnection: (id: string, input: { name?: string; url?: string; username?: string; password?: string }) =>
		req<ConnectionsResponse>('/api/settings', {
			method: 'PATCH',
			body: JSON.stringify({ id, ...input })
		}),
	deleteConnection: (id: string) =>
		req<ConnectionsResponse>('/api/settings', { method: 'DELETE', body: JSON.stringify({ id }) }),
	testConnection: (input?: { id?: string; url?: string; username?: string; password?: string }) =>
		req<TestResult>('/api/settings/test', { method: 'POST', body: JSON.stringify(input ?? {}) }),

	// Events
	mainEvents: () => req<MainEventsResponse>('/api/events?scope=main'),
	// Monat = YYYY-MM; null → neuester Archiv-Monat
	archiveMonth: (monthKey: string | null) =>
		req<ArchiveMonth>(
			`/api/events?scope=archive${monthKey ? `&monat=${encodeURIComponent(monthKey)}` : ''}`
		),

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
		}),

	// Task-Kategorien (Name + Farbe)
	categories: () => req<{ categories: TaskCategory[] }>('/api/categories'),
	saveCategories: (categories: TaskCategory[]) =>
		req<{ categories: TaskCategory[] }>('/api/categories', {
			method: 'POST',
			body: JSON.stringify({ categories })
		}),

	// API-Token (Maschinen-Auth für /api/*, z. B. externe Tools)
	apiToken: () => req<ApiTokenView>('/api/token'),
	generateApiToken: () => req<ApiTokenGenerated>('/api/token', { method: 'POST' }),
	revokeApiToken: () => req<{ ok: true }>('/api/token', { method: 'DELETE' }),

	// Benachrichtigung (täglicher Webhook)
	notify: () => req<NotifyConfigView>('/api/notify'),
	saveNotify: (input: NotifySaveInput) =>
		req<NotifyConfigView>('/api/notify', { method: 'POST', body: JSON.stringify(input) }),
	testNotify: (input?: { url?: string; token?: string; prompt?: string }) =>
		req<NotifyTestResult>('/api/notify/test', { method: 'POST', body: JSON.stringify(input ?? {}) })
};
