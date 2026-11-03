<script lang="ts">
	import type { EventItem } from '$lib/types';
	import { durationShort, timeShort } from '$lib/dates';
	import CheckIcon from '@lucide/svelte/icons/check';
	import MapPinIcon from '@lucide/svelte/icons/map-pin';
	import PencilIcon from '@lucide/svelte/icons/pencil';
	import Trash2Icon from '@lucide/svelte/icons/trash-2';

	let {
		ev,
		onEdit,
		onDelete,
		onToggleTask
	}: {
		ev: EventItem;
		onEdit?: (ev: EventItem) => void;
		onDelete?: (ev: EventItem) => void;
		/** Optimistisches Abhaken einer Aufgabe (sofort + bei Fehler Rücknahme). */
		onToggleTask?: (ev: EventItem) => void;
	} = $props();

	let showActions = $state(false);
	const isTask = $derived(ev.kind === 'task');
</script>

<article
	class="group flex gap-3 rounded-lg border border-border bg-background/40 p-3 transition-colors hover:bg-muted/40"
	class:opacity-60={isTask && ev.completed}
	onmouseenter={() => (showActions = true)}
	onmouseleave={() => (showActions = false)}
>
	<div class="w-16 shrink-0 text-right">
		{#if isTask}
			<div class="flex items-center justify-end gap-1">
				{#if ev.dueMs != null}
					<span class="text-sm font-semibold tabular-nums">{timeShort(ev.dueMs)}</span>
				{/if}
				<button
					type="button"
					role="checkbox"
					aria-checked={!!ev.completed}
					aria-label={ev.completed ? 'Aufgabe wieder öffnen' : 'Aufgabe abhaken'}
					title={ev.completed ? 'Aufgabe wieder öffnen' : 'Aufgabe abhaken'}
					onclick={() => onToggleTask?.(ev)}
					class="flex size-4.5 shrink-0 items-center justify-center rounded-[4px] border transition-colors {ev.completed
						? 'border-primary bg-primary text-primary-foreground'
						: 'border-input bg-input/30 hover:border-primary/60'}"
				>
					{#if ev.completed}<CheckIcon class="size-3.5" />{/if}
				</button>
			</div>
			{#if ev.dueKey && ev.dueMs == null}
				<span class="block text-xs text-muted-foreground">fällig</span>
			{/if}
		{:else if ev.allDay}
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
			<button
				class="min-w-0 flex-1 truncate text-left text-sm font-medium hover:underline"
				class:line-through={isTask && ev.completed}
				class:text-muted-foreground={isTask && ev.completed}
				onclick={() => onEdit?.(ev)}
				title={isTask ? 'Aufgabe bearbeiten' : 'Bearbeiten'}
			>
				{ev.summary}
			</button>
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
							title={isTask ? 'Aufgabe bearbeiten' : 'Bearbeiten'}
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
			{#if isTask}
				<span class="shrink-0 inline-flex items-center gap-1.5">
					{#if ev.category}
						<span class="inline-flex items-center gap-1.5 rounded-full border border-border px-2 py-0.5 text-foreground">
							<span class="size-2 rounded-full" style="background:{ev.categoryColor ?? '#64748b'}"></span>
							{ev.category}
						</span>
					{:else}
						<span>Aufgabe</span>
					{/if}
				</span>
			{:else}
				<span class="truncate">{ev.calendarName}</span>
			{/if}
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
