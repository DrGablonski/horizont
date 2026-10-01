<script lang="ts">
	import { page } from '$app/state';
	import { onMount } from 'svelte';
	import '../app.css';
	import { applyTheme, getStoredTheme } from '$lib/theme';
	import ThemeToggle from '$lib/components/ThemeToggle.svelte';
	import { Toaster } from '$lib/components/ui/sonner';
	import CalendarIcon from '@lucide/svelte/icons/calendar';

	let { children } = $props();

	const nav = [
		{ href: '/', label: 'Heute' },
		{ href: '/archiv', label: 'Archiv' },
		{ href: '/einstellungen', label: 'Einstellungen' }
	];

	function navClass(href: string): string {
		const active = page.url.pathname === href;
		return active
			? 'bg-muted text-foreground'
			: 'text-muted-foreground hover:bg-muted/60 hover:text-foreground';
	}

	onMount(() => {
		applyTheme(getStoredTheme());
		const mq = window.matchMedia('(prefers-color-scheme: dark)');
		const onChange = () => applyTheme(getStoredTheme());
		mq.addEventListener('change', onChange);
		return () => mq.removeEventListener('change', onChange);
	});
</script>

<div class="flex min-h-screen flex-col bg-background text-foreground">
	<header class="sticky top-0 z-40 border-b border-border bg-background/80 backdrop-blur">
		<div class="mx-auto flex h-14 w-full max-w-5xl items-center gap-4 px-4">
			<a href="/" class="flex items-center gap-2 font-semibold tracking-tight">
				<CalendarIcon class="size-5" />
				<span class="text-base">Horizont</span>
			</a>
			<nav class="ml-auto flex items-center gap-1">
				{#each nav as item (item.href)}
					<a
						href={item.href}
						class="rounded-md px-3 py-1.5 text-sm transition-colors {navClass(item.href)}"
					>
						{item.label}
					</a>
				{/each}
				<ThemeToggle />
			</nav>
		</div>
	</header>

	<main class="mx-auto w-full max-w-5xl flex-1 px-4 py-6">
		{@render children()}
	</main>

	<footer class="mx-auto w-full max-w-5xl px-4 py-6">
		<p class="text-xs text-muted-foreground">
			Horizont · lokal gehosteter Kalender &amp; Workflow-Assistent
		</p>
	</footer>
</div>

<Toaster richColors position="top-right" />
