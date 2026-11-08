<script lang="ts">
	import { onMount } from 'svelte';
	import { getStoredTheme, isDarkFor, toggleTheme } from '$lib/theme';
	import MoonIcon from '@lucide/svelte/icons/moon';
	import SunIcon from '@lucide/svelte/icons/sun';

	let dark = $state(false);
	let mq: MediaQueryList | undefined;

	onMount(() => {
		const update = () => {
			dark = isDarkFor(getStoredTheme());
		};
		update();
		mq = window.matchMedia('(prefers-color-scheme: dark)');
		mq.addEventListener('change', update);
		return () => mq?.removeEventListener('change', update);
	});

	function onClick(): void {
		toggleTheme();
		dark = isDarkFor(getStoredTheme());
	}
</script>

<button
	type="button"
	role="switch"
	aria-label="Design wechseln"
	aria-checked={dark}
	class="inline-flex size-8 items-center justify-center rounded-md text-muted-foreground transition-colors hover:bg-muted hover:text-foreground"
	title="Design wechseln"
	onclick={onClick}
>
	{#if dark}
		<SunIcon class="size-4" />
	{:else}
		<MoonIcon class="size-4" />
	{/if}
</button>
