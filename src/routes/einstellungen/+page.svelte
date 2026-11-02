<script lang="ts">
	import { onMount } from 'svelte';
	import { api } from '$lib/api';
	import type {
		ApiTokenView,
		ConnectionsResponse,
		NotifyConfigView,
		NotifyTestResult,
		TaskCategory,
		TestResult
	} from '$lib/types';
	import { DEFAULT_TASK_CATEGORIES, normalizeCategoryName } from '$lib/categories';
	import Button from '$lib/components/ui/button/button.svelte';
	import Checkbox from '$lib/components/ui/checkbox/checkbox.svelte';
	import Input from '$lib/components/ui/input/input.svelte';
	import Label from '$lib/components/ui/label/label.svelte';
	import Badge from '$lib/components/ui/badge/badge.svelte';
	import Spinner from '$lib/components/ui/spinner/spinner.svelte';
	import Separator from '$lib/components/ui/separator/separator.svelte';
	import Textarea from '$lib/components/ui/textarea/textarea.svelte';
	import { toast } from 'svelte-sonner';
	import BellIcon from '@lucide/svelte/icons/bell';
	import TagsIcon from '@lucide/svelte/icons/tags';
	import CheckCircleIcon from '@lucide/svelte/icons/circle-check';
	import KeyRoundIcon from '@lucide/svelte/icons/key-round';
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

	// ── Task-Kategorien (Name + Farbe) ───────────────────────────────────────
	let cats = $state<TaskCategory[]>([]);
	let catSaving = $state(false);
	let newCatName = $state('');
	let newCatColor = $state('#2563eb');

	async function loadCategories(): Promise<void> {
		try {
			const r = await api.categories();
			cats = r.categories;
		} catch (e) {
			toast.error(errMsg(e));
		}
	}

	async function saveCats(next: TaskCategory[]): Promise<boolean> {
		catSaving = true;
		try {
			const r = await api.saveCategories(next);
			cats = r.categories;
			return true;
		} catch (e) {
			toast.error(errMsg(e));
			return false;
		} finally {
			catSaving = false;
		}
	}

	async function addCategory(): Promise<void> {
		const name = normalizeCategoryName(newCatName);
		if (!name) {
			toast.error('Ungültiger Kategoriename (1–40 Zeichen, ohne Komma/Semikolon).');
			return;
		}
		if (cats.some((c) => c.name.toLowerCase() === name.toLowerCase())) {
			toast.error('Diese Kategorie gibt es schon.');
			return;
		}
		if (await saveCats([...cats, { name, color: newCatColor }])) {
			newCatName = '';
			toast.success('Kategorie angelegt.');
		}
	}

	async function renameCategory(oldName: string, newNameRaw: string): Promise<void> {
		const name = normalizeCategoryName(newNameRaw);
		if (!name || name === oldName) return;
		if (cats.some((c) => c.name.toLowerCase() === name.toLowerCase())) {
			toast.error('Diese Kategorie gibt es schon.');
			return;
		}
		if (await saveCats(cats.map((c) => (c.name === oldName ? { ...c, name } : c)))) {
			toast.success('Kategorie umbenannt.');
		}
	}

	async function setCatColor(name: string, color: string): Promise<void> {
		await saveCats(cats.map((c) => (c.name === name ? { ...c, color } : c)));
	}

	async function removeCategory(name: string): Promise<void> {
		if (!confirm(`Kategorie "${name}" wirklich löschen?\nBestehende Aufgaben behalten ihren Kategorienamen (ohne Farbe).`)) return;
		if (await saveCats(cats.filter((c) => c.name !== name))) {
			toast.success('Kategorie gelöscht.');
		}
	}

	async function resetCategories(): Promise<void> {
		if (await saveCats(DEFAULT_TASK_CATEGORIES.map((c) => ({ ...c })))) {
			toast.success('Standard-Kategorien wiederhergestellt.');
		}
	}

	// ── Benachrichtigung (Webhook, z. B. T3 Code) ────────────────────────────
	const PROMPT_HINT =
		'{{body}} = Liste der offenen Tasks (gewählte Kategorien) · {{stand}} = Datum, Uhrzeit und Anzahl.';

	let notify = $state<NotifyConfigView | null>(null);
	let nEnabled = $state(false);
	let nTime = $state('15:00');
	let nUrl = $state('');
	let nToken = $state('');
	let nPrompt = $state('');
	let nCategories = $state<string[]>([]);
	let nImportUrl = $state('');
	let nSaving = $state(false);
	let nTesting = $state(false);
	let nTestResult = $state<NotifyTestResult | null>(null);

	function toggleNotifyCategory(name: string): void {
		if (nCategories.includes(name)) nCategories = nCategories.filter((c) => c !== name);
		else nCategories = [...nCategories, name];
	}

	/** Kategorien für die Webhook-Auswahl: verwaltete + bereits gespeicherte. */
	function notifyCatOptions(): string[] {
		const names = [...cats.map((c) => c.name)];
		for (const n of nCategories) if (!names.includes(n)) names.push(n);
		return names;
	}

	function notifyCatColor(name: string): string {
		return cats.find((c) => c.name === name)?.color ?? '#64748b';
	}

	async function loadNotify(): Promise<void> {
		try {
			const v = await api.notify();
			notify = v;
			nEnabled = v.enabled;
			nTime = v.time;
			nUrl = v.url ?? '';
			nToken = '';
			nPrompt = v.prompt;
			nCategories = v.categories;
		} catch (e) {
			toast.error(errMsg(e));
		}
	}

	/** Komplette Webhook-URL aus der T3-UI einfügen → in URL + Token aufteilen. */
	function importWebhookUrl(): void {
		const t = nImportUrl.trim().replace(/\/+$/, '');
		const i = t.lastIndexOf('/');
		if (i <= 0) {
			toast.error('Bitte die vollständige Webhook-URL einfügen.');
			return;
		}
		nUrl = t.slice(0, i);
		nToken = t.slice(i + 1);
		nImportUrl = '';
		toast.success('URL und Token eingetragen — prüfen und speichern.');
	}

	async function saveNotifyCfg(): Promise<void> {
		if (!nTime.trim()) {
			toast.error('Bitte eine Uhrzeit angeben.');
			return;
		}
		if (nEnabled && nCategories.length === 0) {
			toast.error('Bitte mindestens eine Kategorie auswählen.');
			return;
		}
		nSaving = true;
		nTestResult = null;
		try {
			const v = await api.saveNotify({
				enabled: nEnabled,
				time: nTime,
				url: nUrl.trim(),
				token: nToken.trim(),
				prompt: nPrompt,
				categories: nCategories
			});
			notify = v;
			nToken = '';
			toast.success('Benachrichtigung gespeichert.');
		} catch (e) {
			toast.error(errMsg(e));
		} finally {
			nSaving = false;
		}
	}

	async function testNotify(): Promise<void> {
		if (!nUrl.trim() && !notify?.url) {
			toast.error('Bitte zuerst eine Webhook-URL angeben.');
			return;
		}
		if (!nToken.trim() && !notify?.hasToken) {
			toast.error('Bitte zuerst einen Token angeben.');
			return;
		}
		nTesting = true;
		nTestResult = null;
		try {
			const r = await api.testNotify({ url: nUrl.trim(), token: nToken.trim(), prompt: nPrompt });
			nTestResult = r;
			if (r.ok) toast.success(`Webhook angenommen${r.outcome ? ` (${r.outcome})` : ''}.`);
			else toast.error('Webhook-Test fehlgeschlagen.');
		} catch (e) {
			toast.error(errMsg(e));
		} finally {
			nTesting = false;
		}
	}

	// ── API-Token (Maschinen-Auth, z. B. für T3 Code) ────────────────────────
	let apiTokenView = $state<ApiTokenView | null>(null);
	let newToken = $state('');
	let tGenerating = $state(false);
	let tRevoking = $state(false);

	async function loadApiToken(): Promise<void> {
		try {
			apiTokenView = await api.apiToken();
		} catch (e) {
			toast.error(errMsg(e));
		}
	}

	async function createToken(): Promise<void> {
		if (apiTokenView?.hasToken && !confirm('Den aktuellen Token ersetzen? Er ist danach ungültig.')) return;
		tGenerating = true;
		try {
			const r = await api.generateApiToken();
			newToken = r.token;
			await loadApiToken();
		} catch (e) {
			toast.error(errMsg(e));
		} finally {
			tGenerating = false;
		}
	}

	async function revokeToken(): Promise<void> {
		if (!confirm('API-Token ablehnen? Externe Tools verlieren sofort den Zugriff.')) return;
		tRevoking = true;
		try {
			await api.revokeApiToken();
			newToken = '';
			await loadApiToken();
			toast.success('Token abgelehnt.');
		} catch (e) {
			toast.error(errMsg(e));
		} finally {
			tRevoking = false;
		}
	}

	function copyToken(): void {
		if (!newToken) return;
		navigator.clipboard.writeText(newToken).then(
			() => toast.success('Token kopiert.'),
			() => toast.error('Kopieren fehlgeschlagen.')
		);
	}

	// Die Admin-Funktionen (Users, System-CALDAV) leben seitlich unter /admin;
	// hier bleiben nur die normalen Einstellungen.

	onMount(() => {
		load();
		loadCategories();
		loadNotify();
		loadApiToken();
	});
</script>

<svelte:head>
	<title>Einstellungen · Horizont</title>
</svelte:head>

<div class="max-w-3xl space-y-6">
	<div>
		<h1 class="text-xl font-semibold tracking-tight">Einstellungen</h1>
		<p class="text-sm text-muted-foreground">
			Deine persönlichen Einstellungen: Kalenderverbindungen (CalDAV) und die
			tägliche Webhook-Benachrichtigung. Die dir zugewiesene Verbindung wird vom
			Administrator vorgehalten; externe Quellen wie iCloud kannst du selbst anlegen.
		</p>
	</div>

	<div class="max-w-2xl space-y-6">
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

		<Separator />

		<!-- Task-Kategorien (Name + Farbe) -->
		<div class="rounded-xl border border-border bg-card p-5">
			<div class="flex items-center justify-between gap-3">
				<div>
					<div class="flex items-center gap-2">
						<TagsIcon class="size-4" />
						<span class="text-sm font-medium">Aufgaben-Kategorien</span>
					</div>
					<p class="mt-1 text-xs text-muted-foreground">
						Kategorien für Aufgaben (Name + Farbe). Aufgaben speichern die Kategorie im
						CalDAV-Feld „CATEGORIES" — sichtbar auch in anderen Kalender-Apps.
					</p>
				</div>
				<Button size="sm" variant="ghost" disabled={catSaving} onclick={resetCategories}>
					Standard herstellen
				</Button>
			</div>

			<div class="mt-4 space-y-2">
				{#each cats as c (c.name)}
					<div class="flex items-center gap-2">
						<input
							type="color"
							value={c.color}
							onchange={(e) => setCatColor(c.name, (e.target as HTMLInputElement).value)}
							class="h-8 w-10 cursor-pointer rounded border border-input bg-background p-0.5"
							aria-label={`Farbe für ${c.name}`}
							title="Farbe ändern"
						/>
						<Input
							value={c.name}
							onchange={(e) => renameCategory(c.name, (e.target as HTMLInputElement).value)}
							class="h-8 max-w-56 text-sm"
							maxlength={40}
							aria-label={`Name von ${c.name}`}
						/>
						<Button
							size="sm"
							variant="ghost"
							class="text-muted-foreground hover:text-destructive"
							disabled={catSaving}
							onclick={() => removeCategory(c.name)}
							title="Kategorie löschen"
						>
							<TrashIcon class="size-3.5" />
						</Button>
					</div>
				{:else}
					<p class="text-sm text-muted-foreground">Keine Kategorien —lege unten eine an.</p>
				{/each}
			</div>

			<div class="mt-4 flex flex-wrap items-center gap-2">
				<input
					type="color"
					bind:value={newCatColor}
					class="h-9 w-11 cursor-pointer rounded border border-input bg-background p-0.5"
					aria-label="Farbe der neuen Kategorie"
				/>
				<Input
					bind:value={newCatName}
					placeholder="Neue Kategorie (z. B. Garten)"
					class="h-9 max-w-56 text-sm"
					maxlength={40}
					onkeydown={(e) => e.key === 'Enter' && addCategory()}
				/>
				<Button size="sm" disabled={catSaving || !newCatName.trim()} onclick={addCategory}>
					{#if catSaving}<Spinner class="size-3.5" />{:else}<PlusIcon class="size-3.5" />{/if}
					<span>Hinzufügen</span>
				</Button>
			</div>
		</div>

		<Separator />

		<!-- Benachrichtigung: offene Tasks per Webhook -->
		<div class="rounded-xl border border-border bg-card p-5">
			<div class="flex items-start justify-between gap-3">
				<div>
					<div class="flex items-center gap-2">
						<BellIcon class="size-4" />
						<span class="text-sm font-medium">Benachrichtigung (Webhook)</span>
					</div>
					<p class="mt-1 text-xs text-muted-foreground">
						Jeden Tag um die angegebene Uhrzeit werden alle offenen Aufgaben mit den
						unten gewählten Kategorien per POST an die Webhook-Adresse gesendet — z. B. an T3 Code.
					</p>
				</div>
				<Checkbox
					bind:checked={nEnabled}
					id="notify-enabled"
					aria-label="Benachrichtigung aktivieren"
				/>
			</div>

			<div class="mt-4 grid gap-4 sm:grid-cols-2">
				<div class="space-y-1.5 sm:col-span-2">
					<Label for="notify-import">Komplette Webhook-URL importieren</Label>
					<div class="flex gap-2">
						<Input
							id="notify-import"
							bind:value={nImportUrl}
							placeholder="Aus T3 Code kopieren und hier einfügen"
							autocomplete="off"
							spellcheck={false}
						/>
						<Button size="sm" variant="outline" onclick={importWebhookUrl}>
							Aufteilen
						</Button>
					</div>
				</div>

				<div class="space-y-1.5">
					<Label for="notify-time">Uhrzeit</Label>
					<Input id="notify-time" bind:value={nTime} type="time" />
				</div>

				<div class="space-y-1.5">
					<Label>Kategorien</Label>
					<div class="flex flex-wrap gap-x-4 gap-y-2 pt-1">
						{#each notifyCatOptions() as name (name)}
							<div class="flex items-center gap-2">
								<Checkbox
									id={`notify-cat-${name}`}
									checked={nCategories.includes(name)}
									onCheckedChange={() => toggleNotifyCategory(name)}
									aria-label={`Kategorie ${name}`}
								/>
								<Label for={`notify-cat-${name}`} class="flex cursor-pointer items-center gap-1.5">
									<span class="size-2 rounded-full" style="background:{notifyCatColor(name)}"></span>
									{name}
								</Label>
							</div>
						{/each}
					</div>
					<p class="text-xs text-muted-foreground">
						Nur offene Aufgaben mit diesen Kategorien werden gesendet. Kategorien verwaltest du oben.
					</p>
				</div>

				<div class="space-y-1.5 sm:col-span-2">
					<Label for="notify-url">Webhook-URL (ohne Token)</Label>
					<Input
						id="notify-url"
						bind:value={nUrl}
						placeholder="http://T3-CODE-HOST:PORT/api/hooks/scheduled-task%3A…"
						autocomplete="off"
						spellcheck={false}
						class="font-mono text-xs"
					/>
					<p class="text-xs text-muted-foreground">
						Alles bis direkt vor dem Token — am einfachsten per „Aufteilen" oben.
					</p>
				</div>

				<div class="space-y-1.5 sm:col-span-2">
					<Label for="notify-token">Token</Label>
					<Input
						id="notify-token"
						bind:value={nToken}
						placeholder={
							notify?.hasToken
								? 'Gespeichert — leer lassen, um ihn zu behalten'
								: 'Letztes Segment der Webhook-URL'
						}
						autocomplete="off"
						spellcheck={false}
						class="font-mono text-xs"
					/>
					<p class="text-xs text-muted-foreground">
						{#if notify?.hasToken}
							Ein Token ist gespeichert. Neues Eingeben ersetzt ihn.
						{:else}
							Noch kein Token gespeichert.
						{/if}
					</p>
				</div>

				<div class="space-y-1.5 sm:col-span-2">
					<Label for="notify-prompt">Nachricht (Template)</Label>
					<Textarea
						id="notify-prompt"
						bind:value={nPrompt}
						rows={3}
						spellcheck={false}
						class="font-mono text-xs"
					/>
					<p class="text-xs text-muted-foreground">{PROMPT_HINT}</p>
				</div>
			</div>

			<div class="mt-4 flex flex-wrap items-center gap-2">
				<Button size="sm" disabled={nSaving || !nTime.trim()} onclick={saveNotifyCfg}>
					{#if nSaving}<Spinner class="size-3.5" />{/if}
					<span>Speichern</span>
				</Button>
				<Button size="sm" variant="outline" disabled={nTesting} onclick={testNotify}>
					{#if nTesting}<Spinner class="size-3.5" />{:else}<PlugZapIcon class="size-3.5" />{/if}
					<span>Testnachricht senden</span>
				</Button>
			</div>

			{#if notify?.lastRun}
				<p class="mt-3 text-xs text-muted-foreground">
					Letzter Lauf: {notify.lastRun.date}
					{#if notify.lastRun.status === 'ok'}
						· gesendet
					{:else if notify.lastRun.status === 'skipped'}
						· übersprungen{notify.lastRun.error ? ` (${notify.lastRun.error})` : ''}
					{:else if notify.lastRun.error}
						· Fehler: {notify.lastRun.error}
					{/if}
				</p>
			{/if}
		</div>

		<!-- Webhook-Testergebnis -->
		{#if nTestResult}
			<div
				class={
					'space-y-2 rounded-xl border p-5 ' +
					(nTestResult.ok
						? 'border-emerald-500/30 bg-emerald-500/5'
						: 'border-destructive/40 bg-destructive/5')
				}
			>
				<div class="flex items-center gap-2">
					{#if nTestResult.ok}
						<CheckCircleIcon class="size-4 text-emerald-600 dark:text-emerald-400" />
						<span class="text-sm font-medium text-emerald-700 dark:text-emerald-400">
							Webhook angenommen
						</span>
					{:else}
						<CircleXIcon class="size-4 text-destructive" />
						<span class="text-sm font-medium text-destructive">Webhook-Test fehlgeschlagen</span>
					{/if}
				</div>
				{#if nTestResult.ok}
					<p class="text-sm text-muted-foreground">
						HTTP {nTestResult.status ?? '—'}
						{#if nTestResult.outcome}
							· Ergebnis: {nTestResult.outcome}
						{/if}
						— die Nachricht sollte jetzt in T3 Code angekommen sein.
					</p>
				{:else if nTestResult.error}
					<p class="text-sm text-destructive">{nTestResult.error}</p>
				{/if}
			</div>
		{/if}

		<Separator />

		<!-- API-Token: externe Tools (z. B. T3 Code) lesen & bearbeiten -->
		<div class="rounded-xl border border-border bg-card p-5">
			<div class="flex items-center gap-2">
				<KeyRoundIcon class="size-4" />
				<span class="text-sm font-medium">API-Token (für T3 Code & Co.)</span>
			</div>
			<p class="mt-1 text-xs text-muted-foreground">
				Mit dem Token greift der MCP-Server (z. B. in T3 Code / OpenCode) auf
				deine Termine und Tasks zu (Header <code class="font-mono">Authorization: Bearer &lt;token&gt;</code>).
			</p>

			{#if apiTokenView}
				{#if apiTokenView.hasToken}
					<p class="mt-3 text-xs text-muted-foreground">
						Token erstellt am {new Date(apiTokenView.createdAt as number).toLocaleDateString('de-DE')}
						{#if apiTokenView.lastUsedAt}
							· zuletzt genutzt {new Date(apiTokenView.lastUsedAt).toLocaleDateString('de-DE')}
						{/if}
					</p>
				{:else}
					<p class="mt-3 text-xs text-muted-foreground">Noch kein Token erstellt.</p>
				{/if}
			{/if}

			{#if newToken}
				<div class="mt-3 space-y-2 rounded-lg border border-emerald-500/30 bg-emerald-500/5 p-3">
					<p class="text-xs text-muted-foreground">
						Neuer Token — <strong>wird nur einmal angezeigt</strong>, jetzt kopieren:
					</p>
					<div class="flex gap-2">
						<code class="min-w-0 flex-1 break-all rounded bg-background p-2 font-mono text-xs">{newToken}</code>
						<Button size="sm" variant="outline" onclick={copyToken}>Kopieren</Button>
					</div>
				</div>
			{/if}

			<div class="mt-4 flex flex-wrap items-center gap-2">
				<Button size="sm" disabled={tGenerating} onclick={createToken}>
					{#if tGenerating}<Spinner class="size-3.5" />{:else}<KeyRoundIcon class="size-3.5" />{/if}
					<span>{apiTokenView?.hasToken ? 'Neuen Token erzeugen' : 'Token erzeugen'}</span>
				</Button>
				{#if apiTokenView?.hasToken}
					<Button size="sm" variant="outline" disabled={tRevoking} onclick={revokeToken}>
						{#if tRevoking}<Spinner class="size-3.5" />{:else}<TrashIcon class="size-3.5" />{/if}
						<span>Token ablehnen</span>
					</Button>
				{/if}
			</div>

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
</div>
