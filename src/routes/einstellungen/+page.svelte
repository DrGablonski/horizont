<script lang="ts">
	import type { TaskCategory } from '$lib/types';
	import Separator from '$lib/components/ui/separator/separator.svelte';
	import ApiTokenSection from '$lib/components/settings/ApiTokenSection.svelte';
	import CategoriesSection from '$lib/components/settings/CategoriesSection.svelte';
	import ConnectionsSection from '$lib/components/settings/ConnectionsSection.svelte';
	import NotifySection from '$lib/components/settings/NotifySection.svelte';

	// Bindeglied: der Benachrichtigungs-Abschnitt nutzt die verwalteten Kategorien mit
	// (wie bisher eine gemeinsame Liste, damit sie nicht doppelt geladen wird).
	let cats = $state<TaskCategory[]>([]);
</script>

<svelte:head>
	<title>Einstellungen · Horizont</title>
</svelte:head>

<div class="max-w-3xl space-y-6">
	<div>
		<h1 class="text-xl font-semibold tracking-tight">Einstellungen</h1>
		<p class="text-sm text-muted-foreground">
			Horizont richtet sich nach deinem Kalender: Verbinde unten ein Kalender-Konto
			(über CalDAV — das funktioniert z. B. mit iCloud, Nextcloud, Radicale oder anderen
			CalDAV-Anbietern), verwalte Kategorien für deine Aufgaben und stelle optional eine
			tägliche Benachrichtigung per Webhook ein.
		</p>
	</div>

	<div class="max-w-2xl space-y-6">
		<!-- Der Verbindungs-Abschnitt blendet die übrigen Abschnitte wie bisher erst nach dem Laden der Verbindungen ein. -->
		<ConnectionsSection>
			<CategoriesSection bind:cats />
			<Separator />
			<NotifySection {cats} />
			<Separator />
			<ApiTokenSection />
		</ConnectionsSection>
	</div>
</div>
