<script lang="ts">
	import { onMount } from 'svelte';
	import { api } from '$lib/api';
	import type { MainEventsResponse, EventItem, CalDavCalendar, EventUpdateInput, EventCreateInput } from '$lib/types';
	import TimePanel from '$lib/components/TimePanel.svelte';
	import WorkflowSection from '$lib/components/WorkflowSection.svelte';
	import StatusBanner from '$lib/components/StatusBanner.svelte';
	import EventEditor from '$lib/components/EventEditor.svelte';
	import TaskSection from '$lib/components/TaskSection.svelte';
	import Button from '$lib/components/ui/button/button.svelte';
	import Spinner from '$lib/components/ui/spinner/spinner.svelte';
	import { dayKey } from '$lib/dates';
	import { toast } from 'svelte-sonner';
	import RotateCwIcon from '@lucide/svelte/icons/rotate-cw';
	import PlusIcon from '@lucide/svelte/icons/plus';


	let data = $state<MainEventsResponse | null>(null);
	let loading = $state(true);
	let loadError = $state<string | null>(null);
	let calendars = $state<CalDavCalendar[]>([]);

	// Event-Editor State
	let editorOpen = $state(false);
	let editorMode = $state<'create' | 'edit'>('create');
	let editorInitial = $state<Partial<EventUpdateInput> & { calendarId?: string; uid?: string }>({});

	function errMsg(e: unknown): string {
		return e instanceof Error ? e.message : String(e);
	}

	async function load(): Promise<void> {
		loading = true;
		loadError = null;
		try {
			const [eventsRes, calRes] = await Promise.all([api.mainEvents(), api.calendars()]);
			data = eventsRes;
			calendars = calRes.calendars;
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

	onMount(load);

	// ── Event CRUD Handler ─────────────────────────────────────────────────

	function openCreate(dayKey?: string) {
		editorMode = 'create';
		const dk = dayKey ?? (() => {
			const now = new Date();
			const p = (n: number) => String(n).padStart(2, '0');
			return `${now.getFullYear()}-${p(now.getMonth() + 1)}-${p(now.getDate())}`;
		})();
		editorInitial = {
			allDay: true,
			dayKey: dk,
			endDateKey: dk,
			calendarId: calendars[0]?.id ?? ''
		};
		editorOpen = true;
	}

	function openEdit(ev: EventItem) {
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
					/>
				{/each}
			</div>
		{/if}
	{/if}

	{#if data?.configured}
		<TaskSection />
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
