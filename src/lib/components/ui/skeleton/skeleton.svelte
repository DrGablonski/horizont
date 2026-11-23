<script lang="ts">
	import { cn } from '$lib/utils';
	import type { HTMLAttributes } from 'svelte/elements';

	let { class: className, ...restProps }: HTMLAttributes<HTMLDivElement> = $props();
</script>

<!-- Platzhalter-Fläche für Ladezustände: formt die spätere Inhalte vor,
     damit nichts „aus dem Nichts erscheint“ und Layout-Sprünge ausbleiben. -->
<div {...restProps} class={cn('animate-pulse rounded-md bg-muted', className)}></div>
