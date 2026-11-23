<script lang="ts">
	import { onMount } from 'svelte';
	import { fade } from 'svelte/transition';
	import { api } from '$lib/api';
	import { isTimelineTask } from '$lib/types';
	import type {
		MainEventsResponse,
		EventItem,
		EventRecord,
		CalDavCalendar,
		EventUpdateInput,
		EventCreateInput,
		TimelineTask,
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
	import Skeleton from '$lib/components/ui/skeleton/skeleton.svelte';
	import { dayKey } from '$lib/dates';
	import { errMsg } from '$lib/errors';
	import { cn } from '$lib/utils';
	import { toast } from 'svelte-sonner';
	import RotateCwIcon from '@lucide/svelte/icons/rotate-cw';
	import PlusIcon from '@lucide/svelte/icons/plus';
	import CircleCheckIcon from '@lucide/svelte/icons/circle-check';


	let data = $state<MainEventsResponse | null>(null);
	let loading = $state(true);
	/** Lade-Skelett erst nach kurzer Verzögerung zeigen – bei schnellen Loads sonst flackert es nur. */
	let slowLoad = $state(false);
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

	async function load(): Promise<void> {
		loading = true;
		loadError = null;
		// Skelett erst nach 250 ms einblenden: schnelle Laden bleiben unsichtbar.
		const slow = setTimeout(() => (slowLoad = true), 250);
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
			clearTimeout(slow);
			slowLoad = false;
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

	/** Gelöschte Einträge zurückholen: als Neuanlage anlegen, dann neu laden. */
	function eventToCreateInput(ev: EventRecord): EventCreateInput {
		const startKey = dayKey(ev.startMs);
		const endKey = dayKey(ev.endMs - 1);
		return {
			summary: ev.summary,
			location: ev.location,
			description: ev.description,
			allDay: ev.allDay,
			...(ev.allDay
				? { dayKey: startKey, endDateKey: endKey !== startKey ? endKey : undefined }
				: { startMs: ev.startMs, endMs: ev.endMs }),
			calendarId: ev.calendarId
		};
	}

	function taskToCreateInput(ev: TimelineTask): TaskCreateInput {
		return {
			summary: ev.summary,
			description: ev.description,
			completed: !!ev.completed,
			due: ev.dueKey
				? { kind: 'date', key: ev.dueKey }
				: ev.dueMs != null
					? { kind: 'time', ms: ev.dueMs }
					: { kind: 'none' },
			category: ev.category ?? null,
			calendarId: ev.calendarId
		};
	}

	/**
	 * Löschen ohne Rückfrage: Eintrag verschwindet sofort, dazu ein
	 * „Rückgängig“-Toast mit kurzem Zeitfenster. Schlägt das Löschen fehl,
	 * wandert der Eintrag sofort zurück an seine alte Position.
	 */
	async function handleDeleteEvent(ev: EventItem) {
		const undo = removeTimelineItemWithUndo(ev);
		let restore: () => Promise<void>;
		try {
			if (isTimelineTask(ev)) {
				await api.deleteTask(ev.calendarId, ev.uid);
				const input = taskToCreateInput(ev);
				restore = async () => {
					await api.createTask(input);
					await load();
				};
			} else {
				await api.deleteEvent(ev.calendarId, ev.uid);
				const input = eventToCreateInput(ev);
				restore = async () => {
					await api.createEvent(input);
					await load();
				};
			}
		} catch (e) {
			undo();
			toast.error(errMsg(e));
			return;
		}
		toast.success(isTimelineTask(ev) ? 'Aufgabe gelöscht.' : 'Event gelöscht.', {
			duration: 6000,
			action: {
				label: 'Rückgängig',
				onClick: () => {
					void restore().catch((e: unknown) => toast.error(errMsg(e)));
				}
			}
		});
	}

	async function handleEditorSubmit(input: EventCreateInput) {
		try {
			if (editorMode === 'create') {
				await api.createEvent(input);
				toast.success('Event erstellt.');
			} else {
				const evUid = editorInitial.uid;
				const evCalId = editorInitial.calendarId;
				if (evUid && evCalId) {
					await api.updateEvent(evCalId, evUid, input);
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

	function findTimelineItem(uid: string): TimelineTask | undefined {
		for (const p of data?.panels ?? [])
			for (const g of p.days) {
				const it = g.events.find((e): e is TimelineTask => isTimelineTask(e) && e.uid === uid);
				if (it) return it;
			}
		return undefined;
	}

	/** Entfernt einen Eintrag und liefert eine Funktion, die ihn zurückholt. */
	function removeTimelineItemWithUndo(ev: EventItem): () => void {
		for (const p of data?.panels ?? [])
			for (const g of p.days) {
				const i = g.events.findIndex((e) => e.id === ev.id);
				if (i >= 0) {
					g.events.splice(i, 1);
					return () => g.events.splice(i, 0, ev);
				}
			}
		return () => {};
	}

	function setTaskCompleted(uid: string, completed: boolean): void {
		const it = findTimelineItem(uid);
		if (it) it.completed = completed;
	}

	/**
	 * Abhaken ohne Umwege: Erledigte Tasks verschwinden SOFORT aus der
	 * Startseite – sie landen im Archiv. Erst danach wird an CalDAV
	 * gespeichert. Schlägt die Speicherung fehl, wandert der Task zurück
	 * an seine alte Position. Abgehakte zurückzunehmen lässt sie wieder
	 * in der Timeline erscheinen.
	 */
	async function toggleTask(ev: EventItem): Promise<void> {
		if (!isTimelineTask(ev)) return;
		const was = !!ev.completed;
		const now = !was;
		let undo: () => void = () => {};
		if (now) {
			undo = removeTimelineItemWithUndo(ev);
		} else {
			setTaskCompleted(ev.uid, now);
		}
		try {
			await api.updateTask(ev.calendarId, ev.uid, { completed: now });
		} catch (e) {
			undo();
			toast.error(`Abhaken fehlgeschlagen: ${errMsg(e)}`);
		}
	}

	function openCreateTask() {
		taskEditorMode = 'create';
		taskEditorInitial = { calendarId: calendars[0]?.id ?? '' };
		taskEditorOpen = true;
	}

	function openTaskEdit(ev: TimelineTask) {
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

	async function handleTaskSubmit(input: TaskCreateInput) {
		try {
			if (taskEditorMode === 'create') {
				await api.createTask(input);
				toast.success('Aufgabe erstellt.');
			} else {
				const uid = taskEditorInitial.uid;
				const calId = taskEditorInitial.calendarId;
				if (uid && calId) {
					await api.updateTask(calId, uid, input);
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
				<Button size="default" onclick={() => openCreate()}>
					<PlusIcon class="size-4" />
					<span>Event</span>
				</Button>
				<Button variant="outline" size="default" onclick={openCreateTask}>
					<CircleCheckIcon class="size-4" />
					<span>Aufgabe</span>
				</Button>
			{/if}
			<Button variant="ghost" size="sm" disabled={loading} onclick={refresh} class="shrink-0">
				<RotateCwIcon class="size-4" />
				<span>Aktualisieren</span>
			</Button>
		</div>
	</div>

	{#if loading && !data && slowLoad}
		<!-- Skelett-Rahmen in Panel-Form: zeigt grob die spätere Struktur statt eines Spinners. -->
		<div class="space-y-4" transition:fade={{ duration: 150 }} aria-hidden="true">
			{#each [0, 1] as i (i)}
				<div class="rounded-xl border border-border bg-card p-4">
					<Skeleton class="h-4 w-32" />
					<div class="mt-4 space-y-3">
						{#each [0, 1, 2] as j (j)}
							<div class="flex items-center gap-3">
								<Skeleton class="h-9 w-1 shrink-0 rounded-full" />
								<Skeleton class="h-4 w-full max-w-md" />
								<Skeleton class="h-4 w-14 shrink-0" />
							</div>
						{/each}
					</div>
				</div>
			{/each}
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
