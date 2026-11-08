<script lang="ts">
	import { onMount } from 'svelte';
	import { api } from '$lib/api';
	import type {
		ApiTokenView,
		ConnectionsResponse,
		NotifyConfigView,
		NotifyFrequency,
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
	import SendIcon from '@lucide/svelte/icons/send';
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

	// ── Benachrichtigung (Webhook) ───────────────────────────────────────────
	const PROMPT_HINT =
		'Platzhalter in der Vorlage: {{body}} = Liste deiner offenen Aufgaben · {{stand}} = Datum, Uhrzeit und Anzahl. Den Rest kannst du frei formulieren.';
	const WEEKDAY_NAMES = ['Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag', 'Sonntag'];

	let notify = $state<NotifyConfigView | null>(null);
	let nFrequency = $state<NotifyFrequency>('manual');
	let nTime = $state('15:00');
	let nWeekday = $state(0);
	let nIntervalHours = $state(6);
	let nUrl = $state('');
	let nToken = $state('');
	let nPrompt = $state('');
	let nCategories = $state<string[]>([]);
	let nImportUrl = $state('');
	let nSaving = $state(false);
	let nTesting = $state(false);
	let nSending = $state(false);
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
			nFrequency = v.frequency;
			nTime = v.time;
			nWeekday = v.weekday;
			nIntervalHours = v.intervalHours;
			nUrl = v.url ?? '';
			nToken = '';
			nPrompt = v.prompt;
			nCategories = v.categories;
		} catch (e) {
			toast.error(errMsg(e));
		}
	}

	/** Komplette Webhook-URL einfügen → automatisch in URL + Token aufteilen. */	function importWebhookUrl(): void {
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
		if (nCategories.length === 0) {
			toast.error('Bitte mindestens eine Kategorie auswählen.');
			return;
		}
		nSaving = true;
		nTestResult = null;
		try {
			const v = await api.saveNotify({
				frequency: nFrequency,
				time: nTime,
				weekday: nWeekday,
				intervalHours: nIntervalHours,
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

	/** Jetzt senden: verschickt die echten offenen Tasks (unabhängig von der Automatik). */
	async function sendNow(): Promise<void> {
		nSending = true;
		try {
			const r = await api.sendNotify();
			if (r.ok) {
				toast.success(`Nachricht gesendet${r.outcome ? ` (${r.outcome})` : ''}.`);
			} else if (r.skipped) {
				toast.info(`${r.error ?? 'Nichts gesendet.'}`);
			} else {
				toast.error(r.error ?? 'Senden fehlgeschlagen.');
			}
			loadNotify(); // Lauf-Status aktualisieren
		} catch (e) {
			toast.error(errMsg(e));
		} finally {
			nSending = false;
		}
	}

	// ── API-Token (Maschinen-Auth für externe Zugriffe) ──────────────────────
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
			Horizont richtet sich nach deinem Kalender: Verbinde unten ein Kalender-Konto
			(über CalDAV — das funktioniert z. B. mit iCloud, Nextcloud, Radicale oder anderen
			CalDAV-Anbietern), verwalte Kategorien für deine Aufgaben und stelle optional eine
			tägliche Benachrichtigung per Webhook ein.
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
						<!-- Bearbeitungsformular -->
						<div class="space-y-4 rounded-xl border border-border bg-card p-5">
							<h2 class="text-sm font-medium">Verbindung bearbeiten</h2>
							<div class="grid gap-4 sm:grid-cols-2">
								<div class="space-y-1.5">
									<Label for="edit-name">Name</Label>
									<Input id="edit-name" bind:value={eName} placeholder="Beispiel: iCloud" />
								</div>
								<div class="space-y-1.5 sm:col-span-2">
									<Label for="edit-url">CalDAV-URL</Label>
									<Input id="edit-url" bind:value={eUrl} type="text" required />
									<p class="text-xs text-muted-foreground">
										Empfohlen: nur die Adresse des Servers, z. B. „kalender.example.com" oder
										„192.168.1.100:5232" — Horizont findet den CalDAV-Zugang automatisch.
									</p>
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
									disabled={testing}
									onclick={() => testConnection({ id: conn.id })}
								>
									{#if testing && editingId === conn.id}<Spinner class="size-3.5" />{:else}<PlugZapIcon class="size-3.5" />{/if}
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
			<div class="flex items-center gap-2 rounded-xl border border-dashed border-border p-8 text-sm text-muted-foreground">
				<PlugZapIcon class="size-4" />
				<span>Noch kein Kalender verbunden. Trage unten eine CalDAV-Quelle ein, damit Horizont deine Termine und Aufgaben zeigen kann.</span>
			</div>
		{/if}

		<Separator />

		<!-- Neue Verbindung anlegen -->
		<div class="rounded-xl border border-border bg-card p-5">
			<button
				type="button"
				class="flex w-full items-center justify-between text-left"
				onclick={() => (showNew = !showNew)}
			>
				<div class="flex items-center gap-2">
					<PlusIcon class="size-4" />
					<span class="text-sm font-medium">CalDAV-Quelle anlegen</span>
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
						Hier benennst und einfärbst du die Kategorien, die du deinen Aufgaben geben
						kannst — z. B. „Schule", „Privat" oder „Garten". Die Kategorie wird direkt
						in der Aufgabe gespeichert und ist deshalb auch in anderen Kalender-Apps sichtbar.
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
			<div>
				<div class="flex items-center gap-2">
					<BellIcon class="size-4" />
					<span class="text-sm font-medium">Benachrichtigung (Webhook)</span>
				</div>
				<p class="mt-1 text-xs text-muted-foreground">
					Horizont schickt deine offenen Aufgaben an eine Webhook-Adresse — automatisch
					(täglich, wöchentlich oder alle N Stunden) oder nur manuell über „Jetzt senden".
					Ein Webhook ist einfach eine Internet-Adresse, die Nachrichten entgegennimmt und
					weiterverarbeitet — z. B. ein Chat-Bot, ein Benachrichtigungsdienst oder ein
					Assistenzprogramm. Welche Aufgaben gesendet werden, bestimmst du über die Kategorien.
				</p>
				<p class="mt-1 text-xs text-muted-foreground">
					Du hast keinen Webhook? Kein Problem — lass diesen Abschnitt einfach aus.
				</p>
			</div>

			<div class="mt-4 grid gap-4 sm:grid-cols-2">
				<div class="space-y-1.5 sm:col-span-2">
					<Label for="notify-import">Komplette Webhook-URL einfügen</Label>
					<div class="flex gap-2">
						<Input
							id="notify-import"
							bind:value={nImportUrl}
							placeholder="Hier einfügen, z. B. https://…/webhook/a1b2c3d4"
							autocomplete="off"
							spellcheck={false}
						/>
						<Button size="sm" variant="outline" onclick={importWebhookUrl}>
							Aufteilen
						</Button>
					</div>
					<p class="text-xs text-muted-foreground">
						Am einfachsten: die ganze URL von deinem Dienst hier einfügen und
						„Aufteilen" klicken — Horizont trennt sie automatisch in Adresse und Token.
					</p>
				</div>

				<div class="space-y-1.5">
					<Label for="notify-frequency">Automatisierung</Label>
					<select
						id="notify-frequency"
						class="h-9 w-full rounded-md border border-input bg-background px-3 py-1 text-sm"
						bind:value={nFrequency}
					>
						<option value="manual">Nur manuell (keine Automatik)</option>
						<option value="daily">Täglich</option>
						<option value="weekly">Wöchentlich</option>
						<option value="interval">Alle N Stunden</option>
					</select>
					<p class="text-xs text-muted-foreground">
						Wie oft Horizont automatisch sendet. „Jetzt senden" geht immer — auch ohne Automatik.
					</p>
				</div>

				{#if nFrequency === 'weekly'}
					<div class="space-y-1.5">
						<Label for="notify-weekday">Wochentag</Label>
						<select
							id="notify-weekday"
							class="h-9 w-full rounded-md border border-input bg-background px-3 py-1 text-sm"
							bind:value={nWeekday}
						>
							{#each WEEKDAY_NAMES as name, i}
								<option value={i}>{name}</option>
							{/each}
						</select>
					</div>
				{:else if nFrequency === 'interval'}
					<div class="space-y-1.5">
						<Label for="notify-interval">Alle N Stunden</Label>
						<select
							id="notify-interval"
							class="h-9 w-full rounded-md border border-input bg-background px-3 py-1 text-sm"
							bind:value={nIntervalHours}
						>
							{#each Array(23) as _, i}
								<option value={i + 1}>alle {i + 1} Stunde{i + 1 === 1 ? '' : 'n'}</option>
							{/each}
						</select>
					</div>
				{/if}

				{#if nFrequency === 'daily' || nFrequency === 'weekly'}
					<div class="space-y-1.5">
						<Label for="notify-time">Uhrzeit</Label>
						<Input id="notify-time" bind:value={nTime} type="time" />
					</div>
				{/if}

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
					<Label for="notify-url">Webhook-URL</Label>
					<Input
						id="notify-url"
						bind:value={nUrl}
						placeholder="https://example.com/webhook/…"
						autocomplete="off"
						spellcheck={false}
						class="font-mono text-xs"
					/>
					<p class="text-xs text-muted-foreground">
						Die Adresse des Dienstes, der die Nachrichten empfangen soll — alles bis
						direkt vor dem Zugriffsschlüssel. Am einfachsten trägst du sie oben über
						„Einfügen + Aufteilen" ein.
					</p>
				</div>

				<div class="space-y-1.5 sm:col-span-2">
					<Label for="notify-token">Zugriffsschlüssel (Token)</Label>
					<Input
						id="notify-token"
						bind:value={nToken}
						placeholder={
							notify?.hasToken
								? 'Gespeichert — leer lassen, um ihn zu behalten'
								: 'Der geheime Teil am Ende der Webhook-URL'
						}
						autocomplete="off"
						spellcheck={false}
						class="font-mono text-xs"
					/>
					<p class="text-xs text-muted-foreground">
						{#if notify?.hasToken}
							Ein Zugriffsschlüssel ist gespeichert — wie ein Passwort für den Versand.
							Einfach neu ausfüllen, um ihn zu ersetzen.
						{:else}
							Noch kein Zugriffsschlüssel gespeichert. Du bekommst ihn zusammen mit
							der Webhook-URL von dem Dienst, der die Nachrichten empfangen soll.
						{/if}
					</p>
				</div>

				<div class="space-y-1.5 sm:col-span-2">
					<Label for="notify-prompt">Wie soll die Nachricht aussehen? (Vorlage)</Label>
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
				<Button size="sm" disabled={nSending || !notify?.url || !notify?.hasToken} onclick={sendNow}>
					{#if nSending}<Spinner class="size-3.5" />{:else}<SendIcon class="size-3.5" />{/if}
					<span>Jetzt senden</span>
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
						— die Nachricht sollte jetzt bei deinem Empfänger angekommen sein.
					</p>
				{:else if nTestResult.error}
					<p class="text-sm text-destructive">{nTestResult.error}</p>
				{/if}
			</div>
		{/if}

		<Separator />

		<!-- API-Token: Zugriff für externe Tools (MCP) -->
		<div class="rounded-xl border border-border bg-card p-5">
			<div class="flex items-center gap-2">
				<KeyRoundIcon class="size-4" />
				<span class="text-sm font-medium">API-Token (für externe Zugriffe)</span>
			</div>
			<p class="mt-1 text-xs text-muted-foreground">
				Mit diesem Token können externe Programme — z. B. ein Assistenz-/Automatisierungs-
				Tool über den mitgelieferten MCP-Server — auf deine Termine und Aufgaben zugreifen.
				Der Token funktioniert wie ein Passwort (Header <code class="font-mono">Authorization: Bearer &lt;token&gt;</code>).
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
