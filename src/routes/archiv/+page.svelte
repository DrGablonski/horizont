<script lang="ts">
	import { page } from '$app/state';
	import { goto } from '$app/navigation';
	import { api } from '$lib/api';
	import type { ArchiveMonth, EventItem } from '$lib/types';
	import MonthGrid from '$lib/components/MonthGrid.svelte';
	import EventRow from '$lib/components/EventRow.svelte';
	import StatusBanner from '$lib/components/StatusBanner.svelte';
	import Button from '$lib/components/ui/button/button.svelte';
	import Spinner from '$lib/components/ui/spinner/spinner.svelte';
	import { cn } from '$lib/utils';
	import {
		dayLabel,
		isValidMonthKey,
		monthKeyFromMs,
		monthLabel,
		msFromKey,
		shiftMonthKey
	} from '$lib/dates';
	import ArchiveIcon from '@lucide/svelte/icons/archive';
	import { toast } from 'svelte-sonner';
	import ChevronLeftIcon from '@lucide/svelte/icons/chevron-left';
	import ChevronRightIcon from '@lucide/svelte/icons/chevron-right';
	import XIcon from '@lucide/svelte/icons/x';

	let data = $state<ArchiveMonth | null>(null);
	let loading = $state(true);
	let loadError = $state<string | null>(null);
	let selectedDay = $state<string | null>(null);
	let detailSection: HTMLElement | undefined = $state();
	let seq = 0;

	$effect(() => {
		if (selectedDay && detailSection) {
			detailSection.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
		}
	});

	// Aufgaben im Archiv: optimistisches Abhaken (sofort sichtbar,
	// Rücknahme + Fehlermeldung, wenn CalDAV-Speichern fehlschlägt).
	function setTaskCompleted(uid: string, completed: boolean): void {
		for (const g of data?.days ?? []) {
			const it = g.events.find((e) => e.kind === 'task' && e.uid === uid);
			if (it) it.completed = completed;
		}
	}

	async function toggleTask(ev: EventItem): Promise<void> {
		const was = !!ev.completed;
		const now = !was;
		setTaskCompleted(ev.uid, now);
		try {
			await api.updateTask(ev.calendarId, ev.uid, { completed: now });
		} catch (e) {
			setTaskCompleted(ev.uid, was);
			toast.error(`Abhaken fehlgeschlagen: ${e instanceof Error ? e.message : String(e)}`);
		}
	}

	function monthFromUrl(): string | null {
		const m = page.url.searchParams.get('monat');
		return isValidMonthKey(m) ? m : null;
	}

	async function goToMonth(monthKey: string): Promise<void> {
		await goto(`/archiv?monat=${encodeURIComponent(monthKey)}`);
	}

	function latestMonthKey(): string | null {
		return data ? monthKeyFromMs(msFromKey(data.rangeEnd)) : null;
	}

	async function load(monthKey: string | null): Promise<void> {
		const my = ++seq;
		loading = true;
		loadError = null;
		try {
			const res = await api.archiveMonth(monthKey);
			if (my !== seq) return; // veraltet
			data = res;
			selectedDay = null;
		} catch (e) {
			if (my !== seq) return;
			loadError = e instanceof Error ? e.message : String(e);
		} finally {
			if (my === seq) loading = false;
		}
	}

	$effect(() => {
		load(monthFromUrl());
	});

	let monthTitle = $derived(data ? monthLabel(data.monthKey) : '');
	let selectedGroup = $derived(
		data && selectedDay ? (data.days.find((d) => d.dayKey === selectedDay) ?? null) : null
	);
</script>

<div class="space-y-6">
	<div class="flex items-center gap-3">
		<ArchiveIcon class="size-5 text-muted-foreground" />
		<div>
			<h1 class="text-xl font-semibold tracking-tight">Archiv</h1>
			<p class="text-sm text-muted-foreground">
				Einträge aus der Vergangenheit, Monat für Monat zurückblättern.
			</p>
		</div>
	</div>

	{#if data}
		{@const d = data}
		<div
			class={cn(
				'flex items-center justify-between gap-2 rounded-xl border border-border bg-card px-2 py-2 transition-opacity',
				loading && 'opacity-60'
			)}
		>
			<Button
				variant="ghost"
				size="icon"
				title="Monat zurück"
				aria-label="Monat zurück"
				disabled={!d.canPrev || loading}
				onclick={() => goToMonth(shiftMonthKey(d.monthKey, -1))}
			>
				<ChevronLeftIcon class="size-4" />
			</Button>
			<h2 class="min-w-0 flex-1 truncate text-center text-base font-semibold tracking-tight sm:min-w-44 sm:flex-none">
				{monthTitle}
			</h2>
			<div class="flex shrink-0 items-center gap-1">
				{#if latestMonthKey() && d.monthKey !== latestMonthKey()}
					<Button
						variant="outline"
						size="sm"
						title="Zum neuesten Archiv-Monat springen"
						disabled={loading}
						onclick={() => goToMonth(latestMonthKey()!)}
					>
						Aktuell
					</Button>
				{/if}
				<Button
					variant="ghost"
					size="icon"
					title="Monat weiter"
					aria-label="Monat weiter"
					disabled={!d.canNext || loading}
					onclick={() => goToMonth(shiftMonthKey(d.monthKey, 1))}
				>
					<ChevronRightIcon class="size-4" />
				</Button>
			</div>
		</div>
	{/if}

	{#if loading && !data}
		<div
			class="flex items-center justify-center gap-2 rounded-xl border border-dashed border-border p-10 text-sm text-muted-foreground"
		>
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
			<StatusBanner
				variant="error"
				message={data.error}
				actionHref="/einstellungen"
				actionLabel="Einstellungen prüfen"
			/>
		{:else}
			<div class={cn('space-y-5', loading && 'pointer-events-none opacity-60')}>
				<MonthGrid
					monthKey={data.monthKey}
					days={data.days}
					rangeStart={data.rangeStart}
					rangeEnd={data.rangeEnd}
					{selectedDay}
					onSelectDay={(k) => (selectedDay = selectedDay === k ? null : k)}
				/>

				{#if selectedDay}
					<section bind:this={detailSection} class="rounded-xl border border-border bg-card p-4">
						<div class="mb-3 flex items-center justify-between gap-2">
							<h2 class="text-sm font-semibold">{dayLabel(selectedDay)}</h2>
							<Button
								variant="ghost"
								size="icon-xs"
								aria-label="Tag-Auswahl schließen"
								title="Schließen"
								onclick={() => (selectedDay = null)}
							>
								<XIcon class="size-3" />
							</Button>
						</div>
						<div class="space-y-2">
							{#if selectedGroup && selectedGroup.events.length > 0}
								{#each selectedGroup.events as ev (ev.id)}
									<EventRow {ev} onToggleTask={toggleTask} />
								{/each}
							{:else}
								<p class="text-sm text-muted-foreground">Nichts geplant.</p>
							{/if}
						</div>
					</section>
				{/if}
			</div>
		{/if}
	{/if}
</div>
