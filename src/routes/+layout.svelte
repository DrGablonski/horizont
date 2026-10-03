<script lang="ts">
	import { page } from '$app/state';
	import { goto } from '$app/navigation';
	import { onMount } from 'svelte';
	import type { Snippet } from 'svelte';
	import '../app.css';
	import { applyTheme, getStoredTheme } from '$lib/theme';
	import ThemeToggle from '$lib/components/ThemeToggle.svelte';
	import { Toaster } from '$lib/components/ui/sonner';
	import Button from '$lib/components/ui/button/button.svelte';
	import { api } from '$lib/api';
	import type { AppUser } from '$lib/types';
	import CalendarIcon from '@lucide/svelte/icons/calendar';
	import LogOutIcon from '@lucide/svelte/icons/log-out';
	import Spinner from '$lib/components/ui/spinner/spinner.svelte';

	let { children }: { children: Snippet } = $props();

	// Der Server-Hook leitet unangemeldete Requests von App-Seiten bereits
	// zu /login bzw. /setup weiter. Auf /login und /setup bleibt `user` null.
	let user = $state<AppUser | null>(null);
	const loggedIn = $derived(user !== null);

	const nav = $derived([
		{ href: '/', label: 'Heute' },
		{ href: '/archiv', label: 'Archiv' },
		{ href: '/einstellungen', label: 'Einstellungen' },
		...(user?.role === 'admin' ? [{ href: '/admin', label: 'Admin' }] : [])
	]);

	function navClass(href: string): string {
		const active = page.url.pathname === href;
		return active
			? 'bg-muted text-foreground'
			: 'text-muted-foreground hover:bg-muted/60 hover:text-foreground';
	}

	let loggingOut = $state(false);
	async function logout(): Promise<void> {
		loggingOut = true;
		try {
			await api.logout();
		} catch {
			/* Session ist eh in-memory; Redirect trotzdem. */
		}
		user = null;
		await goto('/login', { invalidateAll: true });
	}

	onMount(() => {
		applyTheme(getStoredTheme());
		const mq = window.matchMedia('(prefers-color-scheme: dark)');
		const onChange = () => applyTheme(getStoredTheme());
		mq.addEventListener('change', onChange);

		const p = page.url.pathname;
		if (p !== '/login' && p !== '/setup') {
			api
				.me()
				.then((u) => (user = u))
				.catch(() => {});
		}
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

			{#if loggedIn}
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
					<div class="mx-2 hidden h-6 w-px bg-border sm:block"></div>
					<div class="hidden items-center gap-2 sm:flex">
						<span class="max-w-40 truncate text-sm text-muted-foreground">{user?.username}</span>
						{#if user?.role === 'admin'}
							<span class="rounded bg-muted px-1.5 py-0.5 text-[10px] font-medium uppercase tracking-wide text-muted-foreground">
								Admin
							</span>
						{/if}
					</div>
					<Button variant="ghost" size="icon" title="Abmelden" disabled={loggingOut} onclick={logout}>
						{#if loggingOut}
							<Spinner class="size-4" />
						{:else}
							<LogOutIcon class="size-4" />
						{/if}
					</Button>
				</nav>
			{:else}
				<div class="ml-auto">
					<ThemeToggle />
				</div>
			{/if}
		</div>
	</header>

	<main class="mx-auto w-full max-w-5xl flex-1 px-4 py-6">
		{@render children()}
	</main>

	{#if loggedIn}
		<footer class="mx-auto w-full max-w-5xl px-4 py-6">
			<p class="text-xs text-muted-foreground">
				Horizont · lokal gehosteter Kalender &amp; Workflow-Assistent
			</p>
		</footer>
	{/if}
</div>

<Toaster richColors position="top-right" />
