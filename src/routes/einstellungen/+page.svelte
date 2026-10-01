<script lang="ts">
	import { onMount } from 'svelte';
	import { api } from '$lib/api';
	import type { CalDavSettingsView, TestResult } from '$lib/types';
	import Button from '$lib/components/ui/button/button.svelte';
	import Input from '$lib/components/ui/input/input.svelte';
	import Label from '$lib/components/ui/label/label.svelte';
	import Badge from '$lib/components/ui/badge/badge.svelte';
	import Spinner from '$lib/components/ui/spinner/spinner.svelte';
	import Separator from '$lib/components/ui/separator/separator.svelte';
	import { toast } from 'svelte-sonner';
	import CheckCircleIcon from '@lucide/svelte/icons/circle-check';
	import CircleXIcon from '@lucide/svelte/icons/circle-x';
	import PlugZapIcon from '@lucide/svelte/icons/plug-zap';
	import SaveIcon from '@lucide/svelte/icons/save';

	let view = $state<CalDavSettingsView | null>(null);
	let loading = $state(true);

	let url = $state('');
	let username = $state('');
	let password = $state('');
	let showPassword = $state(false);

	let saving = $state(false);
	let testing = $state(false);
	let testResult = $state<TestResult | null>(null);

	function errMsg(e: unknown): string {
		return e instanceof Error ? e.message : String(e);
	}

	async function load(): Promise<void> {
		loading = true;
		try {
			const v = await api.getSettings();
			view = v;
			url = v.url;
			username = v.username;
		} catch (e) {
			toast.error(errMsg(e));
		} finally {
			loading = false;
		}
	}

	async function save(): Promise<void> {
		if (!url.trim()) {
			toast.error('Bitte eine CalDAV-URL angeben.');
			return;
		}
		saving = true;
		try {
			const v = await api.saveSettings({ url, username, password });
			view = v;
			password = '';
			testResult = null;
			toast.success('Einstellungen gespeichert.');
		} catch (e) {
			toast.error(errMsg(e));
		} finally {
			saving = false;
		}
	}

	async function test(): Promise<void> {
		if (!url.trim()) {
			toast.error('Bitte eine CalDAV-URL angeben.');
			return;
		}
		testing = true;
		testResult = null;
		try {
			const r = await api.testSettings({ url, username, password });
			testResult = r;
			if (r.ok) toast.success(`Verbindung erfolgreich – ${r.calendars.length} Kalender gefunden.`);
			else toast.error('Verbindung fehlgeschlagen.');
		} catch (e) {
			toast.error(errMsg(e));
		} finally {
			testing = false;
		}
	}

	onMount(load);
</script>

<div class="max-w-2xl space-y-6">
	<div>
		<h1 class="text-xl font-semibold tracking-tight">Einstellungen</h1>
		<p class="text-sm text-muted-foreground">Verbinde deinen CalDAV-Kalender (z. B. Radicale, Baïkal, iCal.</p>
	</div>

	{#if loading && !view}
		<div class="flex items-center gap-2 rounded-xl border border-dashed border-border p-8 text-sm text-muted-foreground">
			<Spinner class="size-4" />
			<span>Wird geladen …</span>
		</div>
	{:else}
		<form
			class="space-y-4 rounded-xl border border-border bg-card p-5"
			onsubmit={(e) => {
				e.preventDefault();
				save();
			}}
		>
			<div class="flex items-center gap-2">
				{#if view?.configured}
					<Badge variant="secondary" class="text-emerald-700 dark:text-emerald-400">
						<CheckCircleIcon class="size-3" />
						verbunden
					</Badge>
				{:else}
					<Badge variant="outline">nicht konfiguriert</Badge>
				{/if}
			</div>

			<div class="space-y-1.5">
				<Label for="dav-url">CalDAV-URL</Label>
				<Input
					id="dav-url"
					bind:value={url}
					type="url"
					placeholder="https://caldav.beispiel.de/dav/benutzer/"
					required
					autocomplete="url"
				/>
				<p class="text-xs text-muted-foreground">
					Endpoint, der PROPFIND/REPORT unterstützt. Das trailing <code>/</code> ist optional.
				</p>
			</div>

			<div class="grid gap-4 sm:grid-cols-2">
				<div class="space-y-1.5">
					<Label for="dav-user">Benutzername</Label>
					<Input id="dav-user" bind:value={username} placeholder="benutzer" autocomplete="username" />
				</div>
				<div class="space-y-1.5">
					<Label for="dav-pass">Passwort</Label>
					<Input
						id="dav-pass"
						bind:value={password}
						type={showPassword ? 'text' : 'password'}
						placeholder={view?.hasPassword ? '●●●● (beibehalten, wenn leer)' : 'passwort'}
						autocomplete="current-password"
					/>
					<button
						type="button"
						class="text-xs text-muted-foreground underline-offset-2 hover:text-foreground hover:underline"
						onclick={() => (showPassword = !showPassword)}
					>
						{showPassword ? 'Passwort verbergen' : 'Passwort anzeigen'}
					</button>
				</div>
			</div>

			<div class="flex flex-wrap items-center gap-2 pt-1">
				<Button type="submit" disabled={saving || !url.trim()}>
					{#if saving}
						<Spinner class="size-4" />
					{:else}
						<SaveIcon class="size-4" />
					{/if}
					<span>{saving ? 'Wird gespeichert …' : 'Speichern'}</span>
				</Button>
				<Button type="button" variant="outline" disabled={testing || !url.trim()} onclick={test}>
					{#if testing}
						<Spinner class="size-4" />
					{:else}
						<PlugZapIcon class="size-4" />
					{/if}
					<span>{testing ? 'Wird getestet …' : 'Verbindung testen'}</span>
				</Button>
			</div>
		</form>

		{#if testResult}
			<div
				class={
					'space-y-3 rounded-xl border p-5 ' +
					(testResult.ok ? 'border-emerald-500/30 bg-emerald-500/5' : 'border-destructive/40 bg-destructive/5')
				}
			>
				<div class="flex items-center gap-2">
					{#if testResult.ok}
						<CheckCircleIcon class="size-4 text-emerald-600 dark:text-emerald-400" />
						<span class="text-sm font-medium text-emerald-700 dark:text-emerald-400">
							Verbindung erfolgreich
						</span>
					{:else}
						<CircleXIcon class="size-4 text-destructive" />
						<span class="text-sm font-medium text-destructive">Verbindung fehlgeschlagen</span>
					{/if}
				</div>

				{#if testResult.ok}
					<p class="text-sm text-muted-foreground">
						{testResult.calendars.length} Kalender abgerufen.
					</p>
					{#if testResult.calendars.length > 0}
						<Separator />
						<ul class="space-y-2">
							{#each testResult.calendars as cal (cal.id)}
								<li class="flex items-center gap-2 text-sm">
									<span class="h-3 w-3 shrink-0 rounded-full" style="background-color: {cal.color}"></span>
									<span class="truncate">{cal.name}</span>
								</li>
							{/each}
						</ul>
					{/if}
				{:else if testResult.error}
					<p class="text-sm text-destructive">{testResult.error}</p>
				{/if}
			</div>
		{/if}
	{/if}
</div>
