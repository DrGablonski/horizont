<script lang="ts">
	import { onMount } from 'svelte';
	import { api } from '$lib/api';
	import type { ConnectionsResponse, TestResult } from '$lib/types';
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
	import PlusIcon from '@lucide/svelte/icons/plus';
	import PencilIcon from '@lucide/svelte/icons/pencil';
	import TrashIcon from '@lucide/svelte/icons/trash-2';
	import XIcon from '@lucide/svelte/icons/x';

	function errMsg(e: unknown): string {
		return e instanceof Error ? e.message : String(e);
	}

	// ── List ────────────────────────────────────────────────────────────────
	let data = $state<ConnectionsResponse | null>(null);
	let loading = $state(true);

	async function load(): Promise<void> {
		loading = true;
		try {
			data = await api.connections();
		} catch (e) {
			toast.error(errMsg(e));
		} finally {
			loading = false;
		}
	}

	// ── Neue externe Verbindung ─────────────────────────────────────────────
	let showNew = $state(false);
	let newName = $state('');
	let newUrl = $state('');
	let newUser = $state('');
	let newPass = $state('');
	let adding = $state(false);

	async function addConnection(): Promise<void> {
		if (!newUrl.trim()) {
			toast.error('Bitte eine CalDAV-URL angeben.');
			return;
		}
		adding = true;
		try {
			await api.createConnection({
				name: newName.trim(),
				url: newUrl,
				username: newUser,
				password: newPass
			});
			newName = '';
			newUrl = '';
			newUser = '';
			newPass = '';
			showNew = false;
			await load();
			toast.success('Verbindung gespeichert.');
		} catch (e) {
			toast.error(errMsg(e));
		} finally {
			adding = false;
		}
	}

	// ── Externe Verbindung bearbeiten ───────────────────────────────────────
	let editingId = $state<string | null>(null);
	let eName = $state('');
	let eUrl = $state('');
	let eUser = $state('');
	let ePass = $state('');
	let savingEdit = $state(false);

	function startEdit(id: string, name: string, url: string, username: string): void {
		editingId = id;
		eName = name;
		eUrl = url;
		eUser = username;
		ePass = '';
	}

	async function saveEdit(): Promise<void> {
		if (!editingId) return;
		savingEdit = true;
		try {
			await api.updateConnection(editingId, {
				name: eName,
				url: eUrl,
				username: eUser,
				password: ePass || undefined
			});
			editingId = null;
			await load();
			toast.success('Verbindung aktualisiert.');
		} catch (e) {
			toast.error(errMsg(e));
		} finally {
			savingEdit = false;
		}
	}

	// ── Externe Verbindung löschen ──────────────────────────────────────────
	async function remove(id: string, name: string): Promise<void> {
		if (!confirm(`Verbindung „${name}“ wirklich löschen?`)) return;
		try {
			await api.deleteConnection(id);
			await load();
			toast.success('Verbindung entfernt.');
		} catch (e) {
			toast.error(errMsg(e));
		}
	}

	// ── Testen ──────────────────────────────────────────────────────────────
	let testing = $state(false);
	let testResult = $state<TestResult | null>(null);

	async function testConnection(input: { id?: string; url?: string; username?: string; password?: string }): Promise<void> {
		testing = true;
		testResult = null;
		try {
			const r = await api.testConnection(input);
			testResult = r;
			if (r.ok) toast.success(`Verbindung erfolgreich – ${r.calendars.length} Kalender gefunden.`);
			else toast.error('Verbindung fehlgeschlagen.');
		} catch (e) {
			toast.error(errMsg(e));
		} finally {
			testing = false;
		}
	}

	async function testForm(): Promise<void> {
		if (!newUrl.trim()) {
			toast.error('Bitte eine CalDAV-URL angeben.');
			return;
		}
		await testConnection({ url: newUrl, username: newUser, password: newPass });
	}

	onMount(load);
</script>

<svelte:head>
	<title>Einstellungen · Horizont</title>
</svelte:head>

<div class="max-w-2xl space-y-6">
	<div>
		<h1 class="text-xl font-semibold tracking-tight">Einstellungen</h1>
		<p class="text-sm text-muted-foreground">
			Kalenderverbindungen (CalDAV). Deine zugewiesene Verbindung wird vom
			Administrator vorgehalten; externe Quellen wie iCloud kannst du selbst anlegen.
		</p>
	</div>

	{#if loading && !data}
		<div class="flex items-center gap-2 rounded-xl border border-dashed border-border p-8 text-sm text-muted-foreground">
			<Spinner class="size-4" />
			<span>Wird geladen …</span>
		</div>
	{:else if data}
		<!-- Bestehende Verbindungen -->
		{#if data.connections.length > 0}
			<div class="space-y-3">
				{#each data.connections as conn (conn.id)}
					{#if editingId === conn.id}
						<!-- Bearbeitungsformular für externe Verbindung -->
						<div class="space-y-4 rounded-xl border border-border bg-card p-5">
							<h2 class="text-sm font-medium">Verbindung bearbeiten</h2>
							<div class="grid gap-4 sm:grid-cols-2">
								<div class="space-y-1.5">
									<Label for="edit-name">Name</Label>
									<Input id="edit-name" bind:value={eName} placeholder="Beispiel: iCloud" />
								</div>
								<div class="space-y-1.5 sm:col-span-2">
									<Label for="edit-url">CalDAV-URL</Label>
									<Input id="edit-url" bind:value={eUrl} type="url" required />
								</div>
								<div class="space-y-1.5">
									<Label for="edit-user">Benutzername</Label>
									<Input id="edit-user" bind:value={eUser} />
								</div>
								<div class="space-y-1.5">
									<Label for="edit-pass">Passwort</Label>
									<Input
										id="edit-pass"
										bind:value={ePass}
										type="password"
										placeholder="●●●● (beibehalten, wenn leer)"
										autocomplete="new-password"
									/>
								</div>
							</div>
							<div class="flex gap-2">
								<Button size="sm" disabled={savingEdit || !eUrl.trim()} onclick={saveEdit}>
									{#if savingEdit}<Spinner class="size-3.5" />{/if}
									<span>Speichern</span>
								</Button>
								<Button size="sm" variant="ghost" onclick={() => (editingId = null)}>
									<XIcon class="size-3.5" />
									<span>Abbrechen</span>
								</Button>
							</div>
						</div>
					{:else}
						<div class="flex items-center gap-3 rounded-xl border border-border bg-card p-4">
							<span
								class="h-2.5 w-2.5 shrink-0 rounded-full"
								class:list={conn.kind === 'assigned' ? ['bg-emerald-500'] : ['bg-blue-500']}
							></span>
							<div class="min-w-0 flex-1">
								<div class="flex flex-wrap items-center gap-2">
									<span class="text-sm font-medium">{conn.name}</span>
									{#if conn.kind === 'assigned'}
										<Badge variant="secondary" class="text-[10px]">zugewiesen</Badge>
									{:else}
										<Badge variant="outline" class="text-[10px]">extern</Badge>
									{/if}
								</div>
								<p class="truncate text-xs text-muted-foreground">
									{conn.url} · {conn.username || 'ohne Benutzername'}
								</p>
							</div>
							<div class="flex shrink-0 items-center gap-1">
								<Button
									variant="ghost"
									size="icon"
									title="Verbindung testen"
									disabled={testing}
									onclick={() => testConnection({ id: conn.id })}
								>
									{#if testing && editingId === conn.id}<Spinner class="size-3.5" />{:else}<PlugZapIcon class="size-3.5" />{/if}
								</Button>
								{#if conn.kind === 'external'}
									<Button
										variant="ghost"
										size="icon"
										title="Bearbeiten"
										onclick={() => startEdit(conn.id, conn.name, conn.url, conn.username)}
									>
										<PencilIcon class="size-3.5" />
									</Button>
									<Button
										variant="ghost"
										size="icon"
										title="Löschen"
										onclick={() => remove(conn.id, conn.name)}
									>
										<TrashIcon class="size-3.5" />
									</Button>
								{/if}
							</div>
						</div>
					{/if}
				{/each}
			</div>
		{:else}
			<div class="flex items-center gap-2 rounded-xl border border-dashed border-border p-8 text-sm text-muted-foreground">
				<PlugZapIcon class="size-4" />
				<span>Noch keine Verbindungen. Lege unten eine externe CalDAV-Quelle an.</span>
			</div>
		{/if}

		<Separator />

		<!-- Neue externe Verbindung anlegen -->
		<div class="rounded-xl border border-border bg-card p-5">
			<button
				type="button"
				class="flex w-full items-center justify-between text-left"
				onclick={() => (showNew = !showNew)}
			>
				<div class="flex items-center gap-2">
					<PlusIcon class="size-4" />
					<span class="text-sm font-medium">Externe CalDAV-Quelle anlegen</span>
				</div>
				<span class="text-xs text-muted-foreground">{showNew ? 'ausblenden' : 'aufklappen'}</span>
			</button>

			{#if showNew}
				<div class="mt-4 space-y-4 border-t border-border pt-4">
					<div class="grid gap-4 sm:grid-cols-2">
						<div class="space-y-1.5">
							<Label for="new-name">Name (optional)</Label>
							<Input id="new-name" bind:value={newName} placeholder="Beispiel: iCloud" />
						</div>
						<div class="space-y-1.5 sm:col-span-2">
							<Label for="new-url">CalDAV-URL</Label>
							<Input
								id="new-url"
								bind:value={newUrl}
								type="url"
								placeholder="https://p17-caldav.icloud.com:443/dav/12345/"
								required
							/>
						</div>
						<div class="space-y-1.5">
							<Label for="new-user">Benutzername</Label>
							<Input id="new-user" bind:value={newUser} placeholder="benutzer" />
						</div>
						<div class="space-y-1.5">
							<Label for="new-pass">Passwort</Label>
							<Input
								id="new-pass"
								bind:value={newPass}
								type="password"
								placeholder="app-spezifisches Passwort"
								autocomplete="new-password"
							/>
						</div>
					</div>
					<div class="flex flex-wrap items-center gap-2">
						<Button size="sm" disabled={adding || !newUrl.trim()} onclick={addConnection}>
							{#if adding}<Spinner class="size-3.5" />{:else}<PlusIcon class="size-3.5" />{/if}
							<span>Speichern</span>
						</Button>
						<Button size="sm" variant="outline" disabled={testing || !newUrl.trim()} onclick={testForm}>
							{#if testing}<Spinner class="size-3.5" />{:else}<PlugZapIcon class="size-3.5" />{/if}
							<span>Erst testen</span>
						</Button>
					</div>
				</div>
			{/if}
		</div>

		<!-- Testergebnis -->
		{#if testResult}
			<div
				class={
					'space-y-3 rounded-xl border p-5 ' +
					(testResult.ok
						? 'border-emerald-500/30 bg-emerald-500/5'
						: 'border-destructive/40 bg-destructive/5')
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
					<p class="text-sm text-muted-foreground">{testResult.calendars.length} Kalender abgerufen.</p>
					{#if testResult.calendars.length > 0}
						<Separator />
						<ul class="space-y-2">
							{#each testResult.calendars as cal (cal.id)}
								<li class="flex items-center gap-2 text-sm">
									<span class="h-3 w-3 shrink-0 rounded-full" style="background-color: {cal.color}"></span>
									<span class="truncate">{cal.name}</span>
									{#if cal.connectionName}
										<span class="truncate text-xs text-muted-foreground">({cal.connectionName})</span>
									{/if}
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
