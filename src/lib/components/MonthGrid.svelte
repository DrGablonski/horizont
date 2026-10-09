<script lang="ts">
	import type { DayGroup, EventItem } from '$lib/types';
	import { monthGridDays, timeShort } from '$lib/dates';
	import { cn } from '$lib/utils';

	let {
		monthKey,
		days,
		rangeStart,
		rangeEnd,
		selectedDay,
		onSelectDay
	}: {
		monthKey: string;
		days: DayGroup[];
		rangeStart: string;
		rangeEnd: string;
		selectedDay: string | null;
		onSelectDay?: (dayKey: string) => void;
	} = $props();

	const WEEKDAYS = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
	const MAX_CHIPS = 3;

	let byDay = $derived(new Map(days.map((d) => [d.dayKey, d])));

	let cells = $derived.by(() =>
		monthGridDays(monthKey).map((key) => {
			const inMonth = key.startsWith(monthKey);
			const inRange = key >= rangeStart && key <= rangeEnd;
			const events: EventItem[] = inRange ? (byDay.get(key)?.events ?? []) : [];
			return { key, inMonth, inRange, events, active: key === selectedDay };
		})
	);

	let weeks = $derived(
		Array.from({ length: Math.ceil(cells.length / 7) }, (_, w) => cells.slice(w * 7, w * 7 + 7))
	);
</script>

<div class="overflow-hidden rounded-xl border border-border bg-card">
	<div class="grid grid-cols-7 border-b border-border bg-muted/30">
		{#each WEEKDAYS as wd (wd)}
			<div class="px-1 py-2 text-center text-xs font-medium text-muted-foreground">{wd}</div>
		{/each}
	</div>

	<div class="grid grid-cols-7">
		{#each weeks as week, wi (week[0].key)}
			{#each week as cell, ci (cell.key)}
				<button
					type="button"
					disabled={!cell.inMonth || !cell.inRange}
					title={cell.inMonth && !cell.inRange ? 'Außerhalb des Archivbereichs' : undefined}
					class={cn(
						'min-h-24 border-b border-r border-border p-1 text-left align-top transition-colors sm:min-h-28',
						ci === 6 && 'border-r-0',
						wi === weeks.length - 1 && 'border-b-0',
						!cell.inMonth && 'bg-muted/10',
						cell.active && 'bg-muted/60',
						cell.inMonth && cell.inRange && !cell.active && 'hover:bg-muted/40'
					)}
					onclick={() => cell.inMonth && cell.inRange && onSelectDay?.(cell.key)}
				>
					<div class="flex items-center justify-between px-0.5">
						<span
							class={cn(
								'flex size-6 items-center justify-center rounded-full text-xs tabular-nums',
								cell.inMonth ? 'font-medium text-foreground' : 'text-muted-foreground/40',
								cell.inMonth && !cell.inRange && 'font-normal text-muted-foreground/50',
								cell.active && 'bg-primary text-primary-foreground'
							)}
						>
							{Number(cell.key.slice(8))}
						</span>
					</div>

					<div class="mt-0.5 space-y-0.5">
						{#each cell.events.slice(0, MAX_CHIPS) as ev (ev.id)}
							<span
								class="hidden items-center gap-1 rounded bg-muted/80 px-1 py-0.5 text-[11px] leading-tight sm:flex"
							>
								<span
									class="h-1.5 w-1.5 shrink-0 rounded-full"
									style="background-color: {ev.calendarColor}"
								></span>
								{#if !ev.allDay}
									<span class="shrink-0 font-medium tabular-nums text-foreground/80">
										{timeShort(ev.startMs)}
									</span>
								{/if}
								<span class="min-w-0 truncate text-foreground/90">{ev.summary}</span>
							</span>
						{/each}
						{#if cell.events.length > MAX_CHIPS}
							<span class="hidden px-1 text-[11px] text-muted-foreground sm:block">
								+{cell.events.length - MAX_CHIPS} weitere
							</span>
						{/if}
					</div>
				</button>
			{/each}
		{/each}
	</div>
</div>
