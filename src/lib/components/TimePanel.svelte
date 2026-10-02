<script lang="ts">
	import type { TimePanel as TimePanelData, EventItem } from '$lib/types';
	import { Collapsible, CollapsibleContent, CollapsibleTrigger } from '$lib/components/ui/collapsible';
	import DayBlock from './DayBlock.svelte';
	import ChevronDownIcon from '@lucide/svelte/icons/chevron-down';
	import { cn } from '$lib/utils';

	let {
		panel,
		onAddDay,
		onEdit,
		onDelete
	}: {
		panel: TimePanelData;
		onAddDay?: (dayKey: string) => void;
		onEdit?: (ev: EventItem) => void;
		onDelete?: (ev: EventItem) => void;
	} = $props();
	let open = $state(panel.defaultOpen);
</script>

<Collapsible bind:open class="group/panel overflow-hidden rounded-xl border border-border bg-card">
	<CollapsibleTrigger
		class="flex w-full items-center gap-3 px-4 py-3 text-left outline-none focus-visible:ring-2 focus-visible:ring-ring/40"
	>
		<span class="min-w-0 flex-1">
			<span class="block text-sm font-semibold">{panel.title}</span>
			<span class="block truncate text-xs text-muted-foreground">{panel.subtitle}</span>
		</span>
		{#if panel.eventCount > 0}
			<span class="shrink-0 rounded-full bg-muted px-2 py-0.5 text-xs font-medium tabular-nums text-muted-foreground">
				{panel.eventCount}
			</span>
		{/if}
		<ChevronDownIcon
			class={cn('size-4 shrink-0 text-muted-foreground transition-transform', open && 'rotate-180')}
		/>
	</CollapsibleTrigger>
	<CollapsibleContent>
		<div class="space-y-5 border-t border-border px-4 py-4">
			{#each panel.days as day (day.dayKey)}
				<DayBlock {day} {onAddDay} {onEdit} {onDelete} />
			{:else}
				<p class="text-sm text-muted-foreground">Keine Einträge in diesem Zeitraum.</p>
			{/each}
		</div>
	</CollapsibleContent>
</Collapsible>
