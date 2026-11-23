<script lang="ts">
	import { onMount } from 'svelte';
	import { cubicOut } from 'svelte/easing';
	import { prefersReducedMotion } from 'svelte/motion';
	import { fly, type TransitionConfig } from 'svelte/transition';
	import type { DayGroup, EventItem } from '$lib/types';
	import EventRow from './EventRow.svelte';
	import { cn } from '$lib/utils';
	import PlusIcon from '@lucide/svelte/icons/plus';

	let {
		day,
		onAddDay,
		onEdit,
		onDelete,
		onToggleTask
	}: {
		day: DayGroup;
		onAddDay?: (dayKey: string) => void;
		onEdit?: (ev: EventItem) => void;
		onDelete?: (ev: EventItem) => void;
		onToggleTask?: (ev: EventItem) => void;
	} = $props();

	// Zeilen animieren erst nach dem ersten Mount dieses Blocks — sonst fliegen
	// beim Seitenaufruf hunderte Zeilen gleichzeitig ein.
	let mounted = $state(false);
	onMount(() => {
		mounted = true;
	});

	/**
	 * Neue Zeilen sanft einfliegen und entfernte (z. B. abgehakte Tasks) sanft
	 * ausgleiten lassen — kurz und Ease-out. Läuft auf einem Wrapper-Element,
	 * da Übergänge nicht direkt auf Komponenten gesetzt werden können.
	 */
	function rowMotion(node: Element, _params?: object): TransitionConfig {
		if (prefersReducedMotion.current || !mounted) return { duration: 0 };
		return fly(node, { y: 4, duration: 120, easing: cubicOut });
	}
</script>

<section class="min-w-0">
	<div class="mb-2 flex items-center justify-between">
		<h3
			class={cn(
				'text-sm font-semibold',
				day.isToday ? 'text-foreground' : 'text-muted-foreground'
			)}
		>
			{day.label}
		</h3>
		{#if onAddDay}
			<button
				class="rounded p-1 text-muted-foreground hover:bg-muted hover:text-foreground transition-colors"
				onclick={() => onAddDay(day.dayKey)}
				title="Event für diesen Tag anlegen"
			>
				<PlusIcon class="size-4" />
			</button>
		{/if}
	</div>
	<div class="space-y-2">
		{#each day.events as ev (ev.id)}
			<div transition:rowMotion>
				<EventRow {ev} {onEdit} {onDelete} {onToggleTask} />
			</div>
		{:else}
			<p class="text-sm text-muted-foreground/70">Nichts geplant.</p>
		{/each}
	</div>
</section>
