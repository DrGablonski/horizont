<script lang="ts">
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
			<EventRow {ev} {onEdit} {onDelete} {onToggleTask} />
		{:else}
			<p class="text-sm text-muted-foreground/70">Nichts geplant.</p>
		{/each}
	</div>
</section>
