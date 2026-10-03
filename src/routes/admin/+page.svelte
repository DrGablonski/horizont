<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';

	// Server-seitig leitet +page.server.ts bereits weiter; dieser
	// onMount ist nur der Fallback, falls der Client doch hier landet.
	onMount(() => {
		void goto('/einstellungen', { invalidateAll: true });
	});
</script>

<p class="text-sm text-muted-foreground">Weiterleitung …</p>
