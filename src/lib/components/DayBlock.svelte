<script lang="ts">
	import type { DayGroup } from '$lib/types';
	import EventRow from './EventRow.svelte';
	import { cn } from '$lib/utils';

	let { day }: { day: DayGroup } = $props();
</script>

<section class="min-w-0">
	<h3
		class={cn(
			'mb-2 text-sm font-semibold',
			day.isToday ? 'text-foreground' : 'text-muted-foreground'
		)}
	>
		{day.label}
	</h3>
	<div class="space-y-2">
		{#each day.events as ev (ev.id)}
			<EventRow {ev} />
		{:else}
			<p class="text-sm text-muted-foreground/70">Nichts geplant.</p>
		{/each}
	</div>
</section>
