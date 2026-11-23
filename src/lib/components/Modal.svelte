<script lang="ts">
	import { onMount } from 'svelte';
	import { cubicOut } from 'svelte/easing';
	import { prefersReducedMotion } from 'svelte/motion';
	import { fade, fly, type TransitionConfig } from 'svelte/transition';

	export let title = '';
	export let open = true;
	export let onClose = () => {};

	// Übergänge kurz halten und ausbremsen (Ease-out); beim Schließen etwas
	// schneller. Bei aktivierter Reduzierung von Bewegung entfallen sie ganz.
	function overlayIn(node: Element, _params?: object): TransitionConfig {
		return prefersReducedMotion.current
			? { duration: 0 }
			: fade(node, { duration: 150, easing: cubicOut });
	}

	function overlayOut(node: Element, _params?: object): TransitionConfig {
		return prefersReducedMotion.current
			? { duration: 0 }
			: fade(node, { duration: 100, easing: cubicOut });
	}

	function panelIn(node: Element, _params?: object): TransitionConfig {
		return prefersReducedMotion.current
			? { duration: 0 }
			: fly(node, { y: 8, duration: 160, easing: cubicOut });
	}

	function panelOut(node: Element, _params?: object): TransitionConfig {
		return prefersReducedMotion.current
			? { duration: 0 }
			: fly(node, { y: 8, duration: 100, easing: cubicOut });
	}

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
		<div
			class="fixed inset-0 bg-black/50"
			role="presentation"
			onclick={onClose}
			in:overlayIn
			out:overlayOut
		></div>
		<div
			class="relative z-10 w-full max-w-lg rounded-lg border bg-background p-6 shadow-lg max-h-[90vh] overflow-y-auto"
			in:panelIn
			out:panelOut
		>
			<h2 class="mb-4 text-lg font-semibold text-foreground">{title}</h2>
			<slot />
		</div>
	</div>
{/if}
