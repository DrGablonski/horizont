<script lang="ts">
	import Button from '$lib/components/ui/button/button.svelte';
	import ChevronLeftIcon from '@lucide/svelte/icons/chevron-left';
	import ChevronRightIcon from '@lucide/svelte/icons/chevron-right';

	let {
		page,
		hasMore,
		onPrev,
		onNext
	}: {
		page: number;
		hasMore: boolean;
		onPrev: () => void;
		onNext: () => void;
	} = $props();
</script>

<div class="flex items-center justify-between gap-3">
	<Button variant="outline" size="sm" disabled={page <= 1} onclick={onPrev} aria-label="Vorherige Seite">
		<ChevronLeftIcon class="size-4" />
		<span>zurück</span>
	</Button>

	<span class="text-sm tabular-nums text-muted-foreground">Seite {page}</span>

	<Button variant="outline" size="sm" disabled={!hasMore} onclick={onNext} aria-label="Nächste Seite">
		<span>weiter</span>
		<ChevronRightIcon class="size-4" />
	</Button>
</div>
