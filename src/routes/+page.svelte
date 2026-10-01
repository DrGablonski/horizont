<script lang="ts">
	import { onMount } from 'svelte';
	import { api } from '$lib/api';
	import type { MainEventsResponse } from '$lib/types';
	import TimePanel from '$lib/components/TimePanel.svelte';
	import WorkflowSection from '$lib/components/WorkflowSection.svelte';
	import StatusBanner from '$lib/components/StatusBanner.svelte';
	import Button from '$lib/components/ui/button/button.svelte';
	import Spinner from '$lib/components/ui/spinner/spinner.svelte';
	import { toast } from 'svelte-sonner';
	import RotateCwIcon from '@lucide/svelte/icons/rotate-cw';

	let data = $state<MainEventsResponse | null>(null);
	let loading = $state(true);
	let loadError = $state<string | null>(null);

	function errMsg(e: unknown): string {
		return e instanceof Error ? e.message : String(e);
	}

	async function load(): Promise<void> {
		loading = true;
		loadError = null;
		try {
			data = await api.mainEvents();
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
</script>

<div class="space-y-6">
	<div class="flex items-center justify-between gap-3">
		<div>
			<h1 class="text-xl font-semibold tracking-tight">Heute</h1>
			<p class="text-sm text-muted-foreground">Dein Zeitrahmen in Vergangenheit, Jetzt und Zukunft.</p>
		</div>
		<Button variant="outline" size="sm" disabled={loading} onclick={refresh} class="shrink-0">
			<RotateCwIcon class="size-4" />
			<span>Aktualisieren</span>
		</Button>
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
					<TimePanel {panel} />
				{/each}
			</div>
		{/if}
	{/if}

	<WorkflowSection />
</div>
