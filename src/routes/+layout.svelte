<script lang="ts">
	import { page } from '$app/state';
	import { goto } from '$app/navigation';
	import { onMount, untrack } from 'svelte';
	import type { Snippet } from 'svelte';
	import '../app.css';
	import { applyTheme, getStoredTheme } from '$lib/theme';
	import ThemeToggle from '$lib/components/ThemeToggle.svelte';
	import AgentWidget from '$lib/components/AgentWidget.svelte';
	import { Toaster } from '$lib/components/ui/sonner';
	import Button from '$lib/components/ui/button/button.svelte';
	import { api } from '$lib/api';
	import type { AppUser } from '$lib/types';
	import HorizontMark from '$lib/components/HorizontMark.svelte';
	import LogOutIcon from '@lucide/svelte/icons/log-out';
	import MenuIcon from '@lucide/svelte/icons/menu';
	import XIcon from '@lucide/svelte/icons/x';
	import Spinner from '$lib/components/ui/spinner/spinner.svelte';

	let { children }: { children: Snippet } = $props();

	// Der Server-Hook leitet unangemeldete Requests von App-Seiten bereits
	// zu /login bzw. /setup weiter. Auf /login und /setup bleibt `user` null.
	let user = $state<AppUser | null>(null);

	// Session-Status holen – reaktiv auf Navigation, damit auch nach einer
	// Client-Side-Auth (Login/Setup, wo onMount nicht erneut läuft) Header
	// und Nav korrekt gerendert werden.
	let meRequest = 0;
	$effect(() => {
		const p = page.url.pathname;
		if (p === '/login' || p === '/setup') return;
		if (user) return;
		const id = ++meRequest;
		api
			.me()
			.then((u) => {
				if (id === meRequest) user = u;
			})
			.catch(() => {});
	});
	const loggedIn = $derived(user !== null);

	const nav = $derived([
		{ href: '/', label: 'Heute' },
		{ href: '/archiv', label: 'Archiv' },
		{ href: '/einstellungen', label: 'Einstellungen' }
	]);

	function navClass(href: string): string {
		const active = page.url.pathname === href;
		return active
			? 'bg-muted text-foreground'
			: 'text-muted-foreground hover:bg-muted/60 hover:text-foreground';
	}

	// Mobiles Burger-Menü: Auf schmalen Screens ersetzen die einzelnen Nav-
	// Buttons (die sonst zur Seite rausscrollen) ein Dropdown unter dem
	// Burger-Button.
	let mobileOpen = $state(false);
	let mobileAnchor: HTMLDivElement | null = $state(null);

	// Bei jeder Navigation schließen – nur auf den Pfad reagieren.
	$effect(() => {
		const path = page.url.pathname;
		untrack(() => {
			if (mobileOpen) mobileOpen = false;
		});
		void path;
	});

	// Auf Klick außerhalb bzw. Escape schließen.
	$effect(() => {
		if (!mobileOpen) return;
		function onKeyDown(e: KeyboardEvent) {
			if (e.key === 'Escape') mobileOpen = false;
		}
		function onPointerDown(e: MouseEvent) {
			if (mobileAnchor && !mobileAnchor.contains(e.target as Node)) mobileOpen = false;
		}
		document.addEventListener('keydown', onKeyDown);
		document.addEventListener('pointerdown', onPointerDown, true);
		return () => {
			document.removeEventListener('keydown', onKeyDown);
			document.removeEventListener('pointerdown', onPointerDown, true);
		};
	});

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
		return () => mq.removeEventListener('change', onChange);
	});
</script>

<div class="flex min-h-screen flex-col bg-background text-foreground">
	<header class="sticky top-0 z-40 border-b border-border bg-background/80 backdrop-blur">
		<div class="mx-auto flex h-14 w-full max-w-5xl items-center gap-4 px-4">
			<a href="/" class="flex items-center gap-2.5">
				<HorizontMark size={36} class="shrink-0" />
				<span class="text-lg font-semibold tracking-tight">Horizont</span>
			</a>

			{#if loggedIn}
				<nav class="ml-auto flex items-center gap-1">
					<!-- Desktop-Navigation -->
					<div class="hidden items-center gap-1 sm:flex">
						{#each nav as item (item.href)}
							<a
								href={item.href}
								class="rounded-md px-3 py-1.5 text-sm transition-colors {navClass(item.href)}"
							>
								{item.label}
							</a>
						{/each}
						<ThemeToggle />
						<div class="mx-2 h-6 w-px bg-border"></div>
						<div class="flex items-center gap-2">
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
					</div>

					<!-- Mobile: Burger-Menü -->
					<div class="relative sm:hidden" bind:this={mobileAnchor}>
						<Button
							variant="ghost"
							size="icon"
							title="Menü"
							aria-label="Menü öffnen oder schließen"
							aria-expanded={mobileOpen}
							onclick={() => (mobileOpen = !mobileOpen)}
						>
							{#if mobileOpen}
								<XIcon class="size-5" />
							{:else}
								<MenuIcon class="size-5" />
							{/if}
						</Button>

						{#if mobileOpen}
							<div
								class="absolute right-0 top-full z-50 mt-2 w-56 animate-in overflow-hidden rounded-lg border border-border bg-popover text-popover-foreground shadow-lg duration-150 fade-in-0 zoom-in-95"
							>
								<div class="p-1.5">
									{#each nav as item (item.href)}
										<a
											href={item.href}
											class="block rounded-md px-3 py-2 text-sm transition-colors {navClass(item.href)}"
										>
											{item.label}
										</a>
									{/each}
								</div>
								<div class="h-px bg-border"></div>
								<div class="flex items-center gap-2 px-3 py-2">
									<span class="min-w-0 flex-1 truncate text-sm text-muted-foreground">
										{user?.username}
									</span>
									{#if user?.role === 'admin'}
										<span class="rounded bg-muted px-1.5 py-0.5 text-[10px] font-medium uppercase tracking-wide text-muted-foreground">
											Admin
										</span>
									{/if}
									<ThemeToggle />
								</div>
								<div class="h-px bg-border"></div>
								<Button
									variant="ghost"
									size="sm"
									class="w-full justify-start px-3"
									disabled={loggingOut}
									onclick={logout}
								>
									{#if loggingOut}
										<Spinner class="size-4" />
									{:else}
										<LogOutIcon class="size-4" />
									{/if}
									Abmelden
								</Button>
							</div>
						{/if}
					</div>
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
		<AgentWidget />
		<footer class="mx-auto w-full max-w-5xl px-4 py-6">
			<p class="text-xs text-muted-foreground">
				Horizont · lokal gehosteter Kalender &amp; Workflow-Assistent
			</p>
		</footer>
	{/if}
</div>

<Toaster richColors position="top-right" />
