<script lang="ts">
	import { onMount, tick, type Snippet } from 'svelte';
	import { api } from '$lib/api';
	import { errMsg } from '$lib/errors';
	import type { ConnectionsResponse, TestResult } from '$lib/types';
	import { toast } from 'svelte-sonner';
	import Button from '$lib/components/ui/button/button.svelte';
	import Input from '$lib/components/ui/input/input.svelte';
	import Label from '$lib/components/ui/label/label.svelte';
	import Spinner from '$lib/components/ui/spinner/spinner.svelte';
	import Separator from '$lib/components/ui/separator/separator.svelte';
	import ConfirmDialog from '$lib/components/ConfirmDialog.svelte';
	import CheckCircleIcon from '@lucide/svelte/icons/circle-check';
	import CircleXIcon from '@lucide/svelte/icons/circle-x';
	import PlugZapIcon from '@lucide/svelte/icons/plug-zap';
	import PlusIcon from '@lucide/svelte/icons/plus';
	import PencilIcon from '@lucide/svelte/icons/pencil';
	import TrashIcon from '@lucide/svelte/icons/trash-2';
	import XIcon from '@lucide/svelte/icons/x';

	/** Die übrigen Einstellungen-Abschnitte (werden wie bisher erst nach dem Laden der Verbindungen eingeblendet). */
	let { children }: { children?: Snippet } = $props();

	// ── Liste ───────────────────────────────────────────────────────────────
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
	const form = $state({
		showNew: false,
		name: '',
		url: '',
		user: '',
		pass: '',
		adding: false
	});

	/** Sprungmarken, damit der Empty-State-Button das Eingabeformular fokussiert. */
	let newFormCard = $state<HTMLDivElement | null>(null);
	let newFormNameInput = $state<HTMLInputElement | null>(null);

	async function focusNewForm(): Promise<void> {
		form.showNew = true;
		newFormCard?.scrollIntoView({ behavior: 'smooth', block: 'start' });
		await tick();
		// preventScroll: sonst bricht der fokussierte Input den sanften Scroll sofort ab.
		newFormNameInput?.focus({ preventScroll: true });
	}

	async function addConnection(): Promise<void> {
		if (!form.url.trim()) {
			toast.error('Bitte eine CalDAV-URL angeben.');
			return;
		}
		form.adding = true;
		try {
			await api.createConnection({
				name: form.name.trim(),
				url: form.url,
				username: form.user,
				password: form.pass
			});
			form.name = '';
			form.url = '';
			form.user = '';
			form.pass = '';
			form.showNew = false;
			await load();
			toast.success('Verbindung gespeichert.');
		} catch (e) {
			toast.error(errMsg(e));
		} finally {
			form.adding = false;
		}
	}

	// ── Externe Verbindung bearbeiten ───────────────────────────────────────
	const edit = $state({
		id: null as string | null,
		name: '',
		url: '',
		user: '',
		pass: '',
		saving: false
	});

	function startEdit(id: string, name: string, url: string, username: string): void {
		edit.id = id;
		edit.name = name;
		edit.url = url;
		edit.user = username;
		edit.pass = '';
	}

	async function saveEdit(): Promise<void> {
		if (!edit.id) return;
		edit.saving = true;
		try {
			await api.updateConnection(edit.id, {
				name: edit.name,
				url: edit.url,
				username: edit.user,
				password: edit.pass || undefined
			});
			edit.id = null;
			await load();
			toast.success('Verbindung aktualisiert.');
		} catch (e) {
			toast.error(errMsg(e));
		} finally {
			edit.saving = false;
		}
	}

	// ── Externe Verbindung löschen ──────────────────────────────────────────
	/** Ausstehender Lösch-Beschluss für den Bestätigungsdialog. */
	let pendingDelete = $state<{ id: string; name: string } | null>(null);

	function remove(id: string, name: string): void {
		pendingDelete = { id, name };
	}

	async function confirmRemove(): Promise<void> {
		if (!pendingDelete) return;
		const { id } = pendingDelete;
		try {
			await api.deleteConnection(id);
			await load();
			toast.success('Verbindung entfernt.');
		} catch (e) {
			toast.error(errMsg(e));
		}
	}

	// ── Testen ──────────────────────────────────────────────────────────────
	const test = $state({ running: false, result: null as TestResult | null });

	async function testConnection(input: { id?: string; url?: string; username?: string; password?: string }): Promise<void> {
		test.running = true;
		test.result = null;
		try {
			const r = await api.testConnection(input);
			test.result = r;
			if (r.ok) toast.success(`Verbindung erfolgreich – ${r.calendars.length} Kalender gefunden.`);
			else toast.error('Verbindung fehlgeschlagen.');
		} catch (e) {
			toast.error(errMsg(e));
		} finally {
			test.running = false;
		}
	}

	async function testForm(): Promise<void> {
		if (!form.url.trim()) {
			toast.error('Bitte eine CalDAV-URL angeben.');
			return;
		}
		await testConnection({ url: form.url, username: form.user, password: form.pass });
	}

	onMount(() => {
		load();
	});
</script>

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
				{#if edit.id === conn.id}
					<!-- Bearbeitungsformular -->
					<div class="space-y-4 rounded-xl border border-border bg-card p-5">
						<h2 class="text-sm font-medium">Verbindung bearbeiten</h2>
						<div class="grid gap-4 sm:grid-cols-2">
							<div class="space-y-1.5">
								<Label for="edit-name">Name</Label>
								<Input id="edit-name" bind:value={edit.name} placeholder="Beispiel: iCloud" />
							</div>
							<div class="space-y-1.5 sm:col-span-2">
								<Label for="edit-url">CalDAV-URL</Label>
								<Input id="edit-url" bind:value={edit.url} type="text" required />
								<p class="text-xs text-muted-foreground">
									Empfohlen: nur die Adresse des Servers, z. B. „kalender.example.com" oder
									„192.168.1.100:5232" — Horizont findet den CalDAV-Zugang automatisch.
								</p>
							</div>
							<div class="space-y-1.5">
								<Label for="edit-user">Benutzername</Label>
								<Input id="edit-user" bind:value={edit.user} />
							</div>
							<div class="space-y-1.5">
								<Label for="edit-pass">Passwort</Label>
								<Input
									id="edit-pass"
									bind:value={edit.pass}
									type="password"
									placeholder="●●●● (beibehalten, wenn leer)"
									autocomplete="new-password"
								/>
							</div>
						</div>
						<div class="flex gap-2">
							<Button size="sm" disabled={edit.saving || !edit.url.trim()} onclick={saveEdit}>
								{#if edit.saving}<Spinner class="size-3.5" />{/if}
								<span>Speichern</span>
							</Button>
							<Button size="sm" variant="ghost" onclick={() => (edit.id = null)}>
								<XIcon class="size-3.5" />
								<span>Abbrechen</span>
							</Button>
						</div>
					</div>
				{:else}
					<div class="flex items-center gap-3 rounded-xl border border-border bg-card p-4">
						<span class="h-2.5 w-2.5 shrink-0 rounded-full bg-blue-500"></span>
						<div class="min-w-0 flex-1">
							<div class="flex flex-wrap items-center gap-2">
								<span class="text-sm font-medium">{conn.name}</span>
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
								disabled={test.running}
								onclick={() => testConnection({ id: conn.id })}
							>
								{#if test.running && edit.id === conn.id}<Spinner class="size-3.5" />{:else}<PlugZapIcon class="size-3.5" />{/if}
							</Button>
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
						</div>
					</div>
				{/if}
			{/each}
		</div>
	{:else}
		<div
			class="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-dashed border-border p-8 text-sm text-muted-foreground"
		>
			<div class="flex items-center gap-2">
				<PlugZapIcon class="size-4" />
				<span>Noch kein Kalender verbunden.</span>
			</div>
			<Button size="sm" variant="outline" onclick={focusNewForm}>
				<PlusIcon class="size-3.5" />
				<span>Kalender verbinden</span>
			</Button>
		</div>
	{/if}

	<Separator />

	<!-- Neue Verbindung anlegen -->
	<div class="rounded-xl border border-border bg-card p-5" bind:this={newFormCard}>
		<button
			type="button"
			class="flex w-full items-center justify-between text-left"
			onclick={() => (form.showNew = !form.showNew)}
		>
			<div class="flex items-center gap-2">
				<PlusIcon class="size-4" />
				<span class="text-sm font-medium">CalDAV-Quelle anlegen</span>
			</div>
			<span class="text-xs text-muted-foreground">{form.showNew ? 'ausblenden' : 'aufklappen'}</span>
		</button>

		{#if form.showNew}
			<div class="mt-4 space-y-4 border-t border-border pt-4">
				<div class="grid gap-4 sm:grid-cols-2">
					<div class="space-y-1.5">
						<Label for="new-name">Name (optional)</Label>
						<Input id="new-name" bind:value={form.name} bind:ref={newFormNameInput} placeholder="Beispiel: iCloud" />
					</div>
					<div class="space-y-1.5 sm:col-span-2">
						<Label for="new-url">CalDAV-URL</Label>
						<Input
							id="new-url"
							bind:value={form.url}
							type="text"
							placeholder="einfach die Server-Adresse, z. B. kalender.example.com"
							required
						/>
						<p class="text-xs text-muted-foreground">
							Einfach nur die Adresse deines Kalender-Servers eintragen — auch ohne
							„https://" und ohne Pfad. Horizont erkennt automatisch, wo der Server
							seine CalDAV-Daten anbietet (z. B. iCloud, Nextcloud, Radicale, Baïkal).
							Nur bei sehr alten Servern musst du den vollen CalDAV-Pfad angeben.
						</p>
					</div>
					<div class="space-y-1.5">
						<Label for="new-user">Benutzername</Label>
						<Input id="new-user" bind:value={form.user} placeholder="benutzer" />
					</div>
					<div class="space-y-1.5">
						<Label for="new-pass">Passwort</Label>
						<Input
							id="new-pass"
							bind:value={form.pass}
							type="password"
							placeholder="app-spezifisches Passwort"
							autocomplete="new-password"
						/>
					</div>
				</div>
				<div class="flex flex-wrap items-center gap-2">
					<Button size="sm" disabled={form.adding || !form.url.trim()} onclick={addConnection}>
						{#if form.adding}<Spinner class="size-3.5" />{:else}<PlusIcon class="size-3.5" />{/if}
						<span>Speichern</span>
					</Button>
					<Button size="sm" variant="outline" disabled={test.running || !form.url.trim()} onclick={testForm}>
						{#if test.running}<Spinner class="size-3.5" />{:else}<PlugZapIcon class="size-3.5" />{/if}
						<span>Erst testen</span>
					</Button>
				</div>
			</div>
		{/if}
	</div>

	<Separator />

	{@render children?.()}

	<!-- Testergebnis -->
	{#if test.result}
		<div
			class={
				'space-y-3 rounded-xl border p-5 ' +
				(test.result.ok
					? 'border-emerald-500/30 bg-emerald-500/5'
					: 'border-destructive/40 bg-destructive/5')
			}
		>
			<div class="flex items-center gap-2">
				{#if test.result.ok}
					<CheckCircleIcon class="size-4 text-emerald-600 dark:text-emerald-400" />
					<span class="text-sm font-medium text-emerald-700 dark:text-emerald-400">
						Verbindung erfolgreich
					</span>
				{:else}
					<CircleXIcon class="size-4 text-destructive" />
					<span class="text-sm font-medium text-destructive">Verbindung fehlgeschlagen</span>
				{/if}
			</div>

			{#if test.result.ok}
				<p class="text-sm text-muted-foreground">{test.result.calendars.length} Kalender abgerufen.</p>
				{#if test.result.calendars.length > 0}
					<Separator />
					<ul class="space-y-2">
						{#each test.result.calendars as cal (cal.id)}
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
			{:else if test.result.error}
			<p class="text-sm text-destructive">{test.result.error}</p>
		{/if}
		</div>
	{/if}

	{#if pendingDelete}
		<ConfirmDialog
			title="Verbindung löschen"
			message={`Verbindung „${pendingDelete.name}“ wirklich löschen?`}
			confirmLabel="Löschen"
			onConfirm={confirmRemove}
			onClose={() => (pendingDelete = null)}
		/>
	{/if}
{/if}
