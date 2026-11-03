<script lang="ts">
	import { onMount } from 'svelte';
	import { api } from '$lib/api';
	import type {
		MainEventsResponse,
		EventItem,
		CalDavCalendar,
		EventUpdateInput,
		EventCreateInput,
		TaskUpdateInput,
		TaskCreateInput,
		TaskCategory
	} from '$lib/types';
	import TimePanel from '$lib/components/TimePanel.svelte';
	import WorkflowSection from '$lib/components/WorkflowSection.svelte';
	import StatusBanner from '$lib/components/StatusBanner.svelte';
	import EventEditor from '$lib/components/EventEditor.svelte';
	import TaskEditor from '$lib/components/TaskEditor.svelte';
	import Button from '$lib/components/ui/button/button.svelte';
	import Spinner from '$lib/components/ui/spinner/spinner.svelte';
	import { dayKey } from '$lib/dates';
	import { toast } from 'svelte-sonner';
	import RotateCwIcon from '@lucide/svelte/icons/rotate-cw';
	import PlusIcon from '@lucide/svelte/icons/plus';
	import CircleCheckIcon from '@lucide/svelte/icons/circle-check';


	let data = $state<MainEventsResponse | null>(null);
	let loading = $state(true);
	let loadError = $state<string | null>(null);
	let calendars = $state<CalDavCalendar[]>([]);
	let categories = $state<TaskCategory[]>([]);

	// Event-Editor State
	let editorOpen = $state(false);
	let editorMode = $state<'create' | 'edit'>('create');
	let editorInitial = $state<Partial<EventUpdateInput> & { calendarId?: string; uid?: string }>({});

	// Task-Editor State (Aufgaben leben mitten in der Timeline)
	let taskEditorOpen = $state(false);
	let taskEditorMode = $state<'create' | 'edit'>('create');
	let taskEditorInitial = $state<Partial<TaskUpdateInput> & { calendarId?: string; uid?: string }>({});

	function errMsg(e: unknown): string {
		return e instanceof Error ? e.message : String(e);
	}

	async function load(): Promise<void> {
		loading = true;
		loadError = null;
		try {
			const [eventsRes, calRes, catRes] = await Promise.all([
				api.mainEvents(),
				api.calendars(),
				api.categories()
			]);
			data = eventsRes;
			calendars = calRes.calendars;
			categories = catRes.categories;
		} catch (e) {
			loadError = errMsg(e);
		} finally {
			loading = false;
		}
	}

	async function refresh(): Promise<void> {
		await load();
		if (!loadError) toast.success('Aktualisiert.');
	}

	onMount(() => {
		load();
	});

	// ── Event CRUD Handler ─────────────────────────────────────────────────

	function openCreate(dayKey?: string) {
		editorMode = 'create';
		const dk = dayKey ?? (() => {
			const now = new Date();
			const p = (n: number) => String(n).padStart(2, '0');
			return `${now.getFullYear()}-${p(now.getMonth() + 1)}-${p(now.getDate())}`;
		})();
		editorInitial = {
			allDay: false,
			dayKey: dk,
			endDateKey: dk,
			calendarId: calendars[0]?.id ?? ''
		};
		editorOpen = true;
	}

	function openEdit(ev: EventItem) {
		if (ev.kind === 'task') {
			openTaskEdit(ev);
			return;
		}
		editorMode = 'edit';
		const startKey = dayKey(ev.startMs);
		const endKeyStr = dayKey(ev.endMs - 1);
		editorInitial = {
			uid: ev.uid,
			summary: ev.summary,
			location: ev.location,
			description: ev.description,
			allDay: ev.allDay,
			dayKey: ev.allDay ? startKey : undefined,
			endDateKey: ev.allDay && endKeyStr !== startKey ? endKeyStr : undefined,
			startMs: ev.allDay ? undefined : ev.startMs,
			endMs: ev.allDay ? undefined : ev.endMs,
			calendarId: ev.calendarId
		};
		editorOpen = true;
	}

	async function handleDeleteEvent(ev: EventItem) {
		if (ev.kind === 'task') {
			if (!confirm(`Aufgabe "${ev.summary}" wirklich löschen?`)) return;
			try {
				await api.deleteTask(ev.calendarId, ev.uid);
				removeTimelineItem(ev);
				toast.success('Aufgabe gelöscht.');
			} catch (e) {
				toast.error(errMsg(e));
			}
			return;
		}
		if (!confirm(`Event "${ev.summary}" wirklich löschen?`)) return;
		try {
			await api.deleteEvent(ev.calendarId, ev.uid);
			toast.success('Event gelöscht.');
			await load();
		} catch (e) {
			toast.error(errMsg(e));
		}
	}

	async function handleEditorSubmit(input: EventCreateInput | EventUpdateInput) {
		try {
			if (editorMode === 'create') {
				await api.createEvent(input as EventCreateInput);
				toast.success('Event erstellt.');
			} else {
				const evUid = editorInitial.uid;
				const evCalId = editorInitial.calendarId;
				if (evUid && evCalId) {
					await api.updateEvent(evCalId, evUid, input as EventUpdateInput);
					toast.success('Event aktualisiert.');
				}
			}
			await load();
		} catch (e) {
			toast.error(errMsg(e));
			throw e;
		}
	}

	// ── Task-Handler (optimistic wie bei Social-Media-Likes) ───────────────

	function findTimelineItem(uid: string): EventItem | undefined {
		for (const p of data?.panels ?? [])
			for (const g of p.days) {
				const it = g.events.find((e) => e.kind === 'task' && e.uid === uid);
				if (it) return it;
			}
		return undefined;
	}

	function removeTimelineItem(ev: EventItem): void {
		for (const p of data?.panels ?? [])
			for (const g of p.days) {
				const i = g.events.findIndex((e) => e.id === ev.id);
				if (i >= 0) g.events.splice(i, 1);
			}
	}

	function setTaskCompleted(uid: string, completed: boolean): void {
		const it = findTimelineItem(uid);
		if (it) it.completed = completed;
	}

	/**
	 * Abhaken ohne Umwege: Der Haken wird SOFORT gesetzt (wie ein Like),
	 * erst danach an CalDAV gespeichert. Schlägt die Speicherung fehl, wird
	 * der Haken zurückgenommen und eine Fehlermeldung gezeigt.
	 */
	async function toggleTask(ev: EventItem): Promise<void> {
		const was = !!ev.completed;
		const now = !was;
		setTaskCompleted(ev.uid, now);
		try {
			await api.updateTask(ev.calendarId, ev.uid, { completed: now });
		} catch (e) {
			setTaskCompleted(ev.uid, was);
			toast.error(`Abhaken fehlgeschlagen: ${errMsg(e)}`);
		}
	}

	function openCreateTask() {
		taskEditorMode = 'create';
		taskEditorInitial = { calendarId: calendars[0]?.id ?? '' };
		taskEditorOpen = true;
	}

	function openTaskEdit(ev: EventItem) {
		taskEditorMode = 'edit';
		taskEditorInitial = {
			uid: ev.uid,
			summary: ev.summary,
			description: ev.description,
			completed: !!ev.completed,
			due: ev.dueKey
				? { kind: 'date' as const, key: ev.dueKey }
				: ev.dueMs != null
					? { kind: 'time' as const, ms: ev.dueMs }
					: { kind: 'none' as const },
			category: ev.category ?? null,
			calendarId: ev.calendarId
		};
		taskEditorOpen = true;
	}

	async function handleTaskSubmit(input: TaskCreateInput | TaskUpdateInput) {
		try {
			if (taskEditorMode === 'create') {
				await api.createTask(input as TaskCreateInput);
				toast.success('Aufgabe erstellt.');
			} else {
				const uid = taskEditorInitial.uid;
				const calId = taskEditorInitial.calendarId;
				if (uid && calId) {
					await api.updateTask(calId, uid, input as TaskUpdateInput);
					toast.success('Aufgabe aktualisiert.');
				}
			}
			await load();
		} catch (e) {
			toast.error(errMsg(e));
			throw e;
		}
	}
</script>

<div class="space-y-6">
	<div class="flex items-center justify-between gap-3">
		<div>
			<h1 class="text-xl font-semibold tracking-tight">Heute</h1>
			<p class="text-sm text-muted-foreground">Dein Zeitrahmen in Vergangenheit, Jetzt und Zukunft.</p>
		</div>
		<div class="flex items-center gap-2">
			{#if data?.configured}
				<Button variant="outline" size="sm" onclick={() => openCreate()}>
					<PlusIcon class="size-4" />
					<span>Event</span>
				</Button>
				<Button variant="outline" size="sm" onclick={openCreateTask}>
					<CircleCheckIcon class="size-4" />
					<span>Aufgabe</span>
				</Button>
			{/if}
			<Button variant="outline" size="sm" disabled={loading} onclick={refresh} class="shrink-0">
				<RotateCwIcon class="size-4" />
				<span>Aktualisieren</span>
			</Button>
		</div>
	</div>

	{#if loading && !data}
		<div class="flex items-center justify-center gap-2 rounded-xl border border-dashed border-border p-10 text-sm text-muted-foreground">
			<Spinner class="size-4" />
			<span>Wird geladen …</span>
		</div>
	{:else if loadError}
		<StatusBanner
			variant="error"
			message="Kalender konnte nicht geladen werden: {loadError}"
			actionHref="/einstellungen"
			actionLabel="Einstellungen prüfen"
		/>
	{:else if data}
		{#if !data.configured}
			<StatusBanner
				variant="not-configured"
				message="Noch keine CalDAV-Verbindung hinterlegt. Lege deine Kontodaten an, um Einträge anzuzeigen."
				actionHref="/einstellungen"
				actionLabel="Zu den Einstellungen"
			/>
		{:else if data.error}
			<StatusBanner
				variant="error"
				message={data.error}
				actionHref="/einstellungen"
				actionLabel="Einstellungen prüfen"
			/>
		{/if}

		{#if data.configured}
			<div class="space-y-4">
				{#each data.panels as panel (panel.id)}
					<TimePanel
						{panel}
						onAddDay={openCreate}
						onEdit={openEdit}
						onDelete={handleDeleteEvent}
						onToggleTask={toggleTask}
					/>
				{/each}
			</div>
		{/if}
	{/if}

	<WorkflowSection />
</div>

{#if editorOpen}
	<EventEditor
		mode={editorMode}
		open={editorOpen}
		calendars={calendars}
		initial={editorInitial}
		onSubmit={handleEditorSubmit}
		onClose={() => (editorOpen = false)}
	/>
{/if}

{#if taskEditorOpen}
	<TaskEditor
		mode={taskEditorMode}
		open={taskEditorOpen}
		calendars={calendars}
		categories={categories}
		initial={taskEditorInitial}
		onSubmit={handleTaskSubmit}
		onClose={() => (taskEditorOpen = false)}
	/>
{/if}
