<script lang="ts">
	import type { EventItem } from '$lib/types';
	import { durationShort, timeShort } from '$lib/dates';
	import MapPinIcon from '@lucide/svelte/icons/map-pin';
	import PencilIcon from '@lucide/svelte/icons/pencil';
	import Trash2Icon from '@lucide/svelte/icons/trash-2';

	let {
		ev,
		onEdit,
		onDelete
	}: {
		ev: EventItem;
		onEdit?: (ev: EventItem) => void;
		onDelete?: (ev: EventItem) => void;
	} = $props();

	let showActions = $state(false);
</script>

<article
	class="group flex gap-3 rounded-lg border border-border bg-background/40 p-3 transition-colors hover:bg-muted/40"
	onmouseenter={() => (showActions = true)}
	onmouseleave={() => (showActions = false)}
>
	<div class="w-16 shrink-0 text-right">
		{#if ev.allDay}
			<span class="text-xs font-medium">Ganztägig</span>
		{:else}
			<span class="text-sm font-semibold tabular-nums">{timeShort(ev.startMs)}</span>
			<span class="block text-xs text-muted-foreground">
				{durationShort(ev.endMs - ev.startMs)}
			</span>
		{/if}
	</div>

	<div class="w-1 shrink-0 self-stretch rounded-full" style="background-color: {ev.calendarColor}"></div>

	<div class="min-w-0 flex-1">
		<div class="flex items-start gap-1">
			<p class="min-w-0 flex-1 truncate text-sm font-medium">{ev.summary}</p>
			{#if onEdit || onDelete}
				<div
					class="flex shrink-0 items-center gap-0.5 transition-opacity"
					class:opacity-0={!showActions}
					class:opacity-100={showActions}
				>
					{#if onEdit}
						<button
							class="rounded p-1 text-muted-foreground hover:bg-muted hover:text-foreground transition-colors"
							onclick={(e) => { e.stopPropagation(); onEdit(ev); }}
							title="Bearbeiten"
						>
							<PencilIcon class="size-3" />
						</button>
					{/if}
					{#if onDelete}
						<button
							class="rounded p-1 text-muted-foreground hover:bg-destructive/10 hover:text-destructive transition-colors"
							onclick={(e) => { e.stopPropagation(); onDelete(ev); }}
							title="Löschen"
						>
							<Trash2Icon class="size-3" />
						</button>
					{/if}
				</div>
			{/if}
		</div>
		<div class="mt-0.5 flex flex-wrap items-center gap-x-3 gap-y-0.5 text-xs text-muted-foreground">
			<span class="truncate">{ev.calendarName}</span>
			{#if ev.location}
				<span class="inline-flex min-w-0 items-center gap-1">
					<MapPinIcon class="size-3 shrink-0" />
					<span class="truncate">{ev.location}</span>
				</span>
			{/if}
		</div>
		{#if ev.description}
			<p class="mt-1 line-clamp-2 text-xs text-muted-foreground/80">{ev.description}</p>
		{/if}
	</div>
</article>
