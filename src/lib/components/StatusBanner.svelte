<script lang="ts">
	import Button from '$lib/components/ui/button/button.svelte';
	import SettingsIcon from '@lucide/svelte/icons/settings';
	import TriangleAlertIcon from '@lucide/svelte/icons/triangle-alert';
	import { cn } from '$lib/utils';

	let {
		variant = 'error',
		message,
		actionHref,
		actionLabel
	}: {
		variant?: 'error' | 'not-configured' | 'info';
		message: string;
		actionHref?: string;
		actionLabel?: string;
	} = $props();
</script>

<div
	class={cn(
		'flex flex-col gap-3 rounded-xl border p-4 sm:flex-row sm:items-center sm:justify-between',
		variant === 'error' && 'border-destructive/40 bg-destructive/5 text-destructive',
		variant === 'not-configured' && 'border-border bg-muted/50 text-muted-foreground',
		variant === 'info' && 'border-border bg-muted/50 text-muted-foreground'
	)}
>
	<div class="flex items-start gap-3">
		{#if variant === 'error'}
			<TriangleAlertIcon class="mt-0.5 size-4 shrink-0" />
		{:else}
			<SettingsIcon class="mt-0.5 size-4 shrink-0" />
		{/if}
		<p class="text-sm leading-relaxed">{message}</p>
	</div>
	{#if actionHref && actionLabel}
		<Button variant="outline" size="sm" href={actionHref} class="shrink-0">
			{actionLabel}
		</Button>
	{/if}
</div>
