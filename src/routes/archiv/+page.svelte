<script lang="ts">
	import { page } from '$app/state';
	import { goto } from '$app/navigation';
	import { api } from '$lib/api';
	import type { ArchivePage } from '$lib/types';
	import DayBlock from '$lib/components/DayBlock.svelte';
	import Pagination from '$lib/components/Pagination.svelte';
	import StatusBanner from '$lib/components/StatusBanner.svelte';
	import Spinner from '$lib/components/ui/spinner/spinner.svelte';
	import ArchiveIcon from '@lucide/svelte/icons/archive';

	let data = $state<ArchivePage | null>(null);
	let loading = $state(true);
	let loadError = $state<string | null>(null);
	let seq = 0;

	function errMsg(e: unknown): string {
		return e instanceof Error ? e.message : String(e);
	}

	function currentPage(): number {
		const p = page.url.searchParams.get('page');
		const n = p ? parseInt(p, 10) : NaN;
		return Number.isFinite(n) && n >= 1 ? n : 1;
	}

	async function goTo(n: number): Promise<void> {
		const params = new URLSearchParams();
		if (n > 1) params.set('page', String(n));
		const qs = params.toString();
		await goto(qs ? `/archiv?${qs}` : '/archiv');
	}

	async function load(p: number): Promise<void> {
		const my = ++seq;
		loading = true;
		loadError = null;
		try {
			const res = await api.archive(p);
			if (my !== seq) return; // veraltet
			data = res;
		} catch (e) {
			if (my !== seq) return;
			loadError = errMsg(e);
		} finally {
			if (my === seq) loading = false;
		}
	}

	$effect(() => {
		load(currentPage());
	});
</script>

<div class="space-y-6">
	<div class="flex items-center gap-3">
		<ArchiveIcon class="size-5 text-muted-foreground" />
		<div>
			<h1 class="text-xl font-semibold tracking-tight">Archiv</h1>
			<p class="text-sm text-muted-foreground">Vergangene Einträge, älter als zwei Wochen, chronologisch.</p>
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
			message="Archiv konnte nicht geladen werden: {loadError}"
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
			<StatusBanner variant="error" message={data.error} actionHref="/einstellungen" actionLabel="Einstellungen prüfen" />
		{:else}
			{#if data.days.length === 0}
				<div class="rounded-xl border border-dashed border-border p-10 text-center text-sm text-muted-foreground">
					Keine Einträge in diesem Zeitraum.
				</div>
			{:else}
				<div class="space-y-5">
					{#each data.days as day (day.dayKey)}
						<DayBlock {day} />
					{/each}
				</div>
			{/if}

			{#if data.page > 1 || data.hasMore}
				{@const pg = data.page}
				<div class="pt-2">
					<Pagination
						page={pg}
						hasMore={data.hasMore}
						onPrev={() => goTo(pg - 1)}
						onNext={() => goTo(pg + 1)}
					/>
				</div>
			{/if}
		{/if}
	{/if}
</div>
