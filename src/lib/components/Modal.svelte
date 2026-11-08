<script lang="ts">
	import { onMount } from 'svelte';

	export let title = '';
	export let open = true;
	export let onClose = () => {};

	function handleKeydown(e: KeyboardEvent) {
		if (e.key === 'Escape') onClose();
	}

	onMount(() => {
		document.addEventListener('keydown', handleKeydown);
		return () => document.removeEventListener('keydown', handleKeydown);
	});
</script>

{#if open}
	<div class="fixed inset-0 z-50 flex items-center justify-center p-4">
		<div class="fixed inset-0 bg-black/50" onclick={onClose}></div>
		<div
			class="relative z-10 w-full max-w-lg rounded-lg border bg-background p-6 shadow-lg max-h-[90vh] overflow-y-auto"
		>
			<h2 class="mb-4 text-lg font-semibold text-foreground">{title}</h2>
			<slot />
		</div>
	</div>
{/if}
