<script lang="ts">
	// Admin-Einstellungen: User-Verwaltung und System-CALDAV. Zugriff nur für
	// die Admin-Rolle – serverseitig wird das in +page.server.ts abgefangen,
	// die API-Endpunkte prüfen die Rolle zusätzlich.
	import UserManagement from '$lib/components/admin/UserManagement.svelte';
	import SystemCaldavSettings from '$lib/components/admin/SystemCaldavSettings.svelte';

	let tab = $state<'users' | 'caldav'>('users');

	function tabClass(t: 'users' | 'caldav'): string {
		return tab === t
			? 'bg-background text-foreground shadow-sm'
			: 'text-muted-foreground hover:text-foreground';
	}
</script>

<svelte:head>
	<title>Administration · Horizont</title>
</svelte:head>

<div class="max-w-3xl space-y-6">
	<div>
		<h1 class="text-xl font-semibold tracking-tight">Administration</h1>
		<p class="text-sm text-muted-foreground">
			Verwaltung für Administratoren: Users und das System-CALDAV.
		</p>
	</div>

	<!-- Auf schmalen Screens Tabs horizontal scrollbar, statt die Seite zu verbreitern -->
	<div class="flex max-w-full items-center gap-1 overflow-x-auto rounded-lg bg-muted p-1">
		<button
			type="button"
			class="rounded-md px-3 py-1.5 text-sm transition-colors {tabClass('users')}"
			onclick={() => (tab = 'users')}
		>
			Users
		</button>
		<button
			type="button"
			class="rounded-md px-3 py-1.5 text-sm transition-colors {tabClass('caldav')}"
			onclick={() => (tab = 'caldav')}
		>
			System-CALDAV
		</button>
	</div>

	{#if tab === 'users'}
		<UserManagement />
	{:else if tab === 'caldav'}
		<div class="max-w-2xl">
			<SystemCaldavSettings />
		</div>
	{/if}
</div>
