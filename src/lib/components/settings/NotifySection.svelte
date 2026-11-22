<script lang="ts">
	import { onMount } from 'svelte';
	import { api } from '$lib/api';
	import { errMsg } from '$lib/errors';
	import type { NotifyConfigView, NotifyFrequency, NotifyTestResult, TaskCategory } from '$lib/types';
	import { toast } from 'svelte-sonner';
	import Button from '$lib/components/ui/button/button.svelte';
	import Checkbox from '$lib/components/ui/checkbox/checkbox.svelte';
	import Input from '$lib/components/ui/input/input.svelte';
	import Label from '$lib/components/ui/label/label.svelte';
	import Spinner from '$lib/components/ui/spinner/spinner.svelte';
	import Textarea from '$lib/components/ui/textarea/textarea.svelte';
	import BellIcon from '@lucide/svelte/icons/bell';
	import CheckCircleIcon from '@lucide/svelte/icons/circle-check';
	import CircleXIcon from '@lucide/svelte/icons/circle-x';
	import PlugZapIcon from '@lucide/svelte/icons/plug-zap';
	import SendIcon from '@lucide/svelte/icons/send';

	/** Die verwalteten Kategorien — Auswahl und Farben werden hier mitbenutzt. */
	let { cats }: { cats: TaskCategory[] } = $props();

	const PROMPT_HINT =
		'Platzhalter in der Vorlage: {{body}} = Liste deiner offenen Aufgaben · {{stand}} = Datum, Uhrzeit und Anzahl. Den Rest kannst du frei formulieren.';
	const WEEKDAY_NAMES = ['Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag', 'Sonntag'];

	let notify = $state<NotifyConfigView | null>(null);
	let testResult = $state<NotifyTestResult | null>(null);

	const form = $state({
		frequency: 'manual' as NotifyFrequency,
		time: '15:00',
		weekday: 0,
		intervalHours: 6,
		url: '',
		token: '',
		prompt: '',
		categories: [] as string[],
		importUrl: ''
	});
	const busy = $state({ saving: false, testing: false, sending: false });

	function toggleNotifyCategory(name: string): void {
		if (form.categories.includes(name)) form.categories = form.categories.filter((c) => c !== name);
		else form.categories = [...form.categories, name];
	}

	/** Kategorien für die Webhook-Auswahl: verwaltete + bereits gespeicherte. */
	function notifyCatOptions(): string[] {
		const names = [...cats.map((c) => c.name)];
		for (const n of form.categories) if (!names.includes(n)) names.push(n);
		return names;
	}

	function notifyCatColor(name: string): string {
		return cats.find((c) => c.name === name)?.color ?? '#64748b';
	}

	async function loadNotify(): Promise<void> {
		try {
			const v = await api.notify();
			notify = v;
			form.frequency = v.frequency;
			form.time = v.time;
			form.weekday = v.weekday;
			form.intervalHours = v.intervalHours;
			form.url = v.url ?? '';
			form.token = '';
			form.prompt = v.prompt;
			form.categories = v.categories;
		} catch (e) {
			toast.error(errMsg(e));
		}
	}

	/** Komplette Webhook-URL einfügen → automatisch in URL + Token aufteilen. */	function importWebhookUrl(): void {
		const t = form.importUrl.trim().replace(/\/+$/, '');
		const i = t.lastIndexOf('/');
		if (i <= 0) {
			toast.error('Bitte die vollständige Webhook-URL einfügen.');
			return;
		}
		form.url = t.slice(0, i);
		form.token = t.slice(i + 1);
		form.importUrl = '';
		toast.success('URL und Token eingetragen — prüfen und speichern.');
	}

	async function saveNotifyCfg(): Promise<void> {
		if (!form.time.trim()) {
			toast.error('Bitte eine Uhrzeit angeben.');
			return;
		}
		if (form.categories.length === 0) {
			toast.error('Bitte mindestens eine Kategorie auswählen.');
			return;
		}
		busy.saving = true;
		testResult = null;
		try {
			const v = await api.saveNotify({
				frequency: form.frequency,
				time: form.time,
				weekday: form.weekday,
				intervalHours: form.intervalHours,
				url: form.url.trim(),
				token: form.token.trim(),
				prompt: form.prompt,
				categories: form.categories
			});
			notify = v;
			form.token = '';
			toast.success('Benachrichtigung gespeichert.');
		} catch (e) {
			toast.error(errMsg(e));
		} finally {
			busy.saving = false;
		}
	}

	async function testNotify(): Promise<void> {
		if (!form.url.trim() && !notify?.url) {
			toast.error('Bitte zuerst eine Webhook-URL angeben.');
			return;
		}
		if (!form.token.trim() && !notify?.hasToken) {
			toast.error('Bitte zuerst einen Token angeben.');
			return;
		}
		busy.testing = true;
		testResult = null;
		try {
			const r = await api.testNotify({ url: form.url.trim(), token: form.token.trim(), prompt: form.prompt });
			testResult = r;
			if (r.ok) toast.success(`Webhook angenommen${r.outcome ? ` (${r.outcome})` : ''}.`);
			else toast.error('Webhook-Test fehlgeschlagen.');
		} catch (e) {
			toast.error(errMsg(e));
		} finally {
			busy.testing = false;
		}
	}

	/** Jetzt senden: verschickt die echten offenen Tasks (unabhängig von der Automatik). */
	async function sendNow(): Promise<void> {
		busy.sending = true;
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
			busy.sending = false;
		}
	}

	onMount(() => {
		loadNotify();
	});
</script>

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
					bind:value={form.importUrl}
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
				bind:value={form.frequency}
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

		{#if form.frequency === 'weekly'}
			<div class="space-y-1.5">
				<Label for="notify-weekday">Wochentag</Label>
				<select
					id="notify-weekday"
					class="h-9 w-full rounded-md border border-input bg-background px-3 py-1 text-sm"
					bind:value={form.weekday}
				>
					{#each WEEKDAY_NAMES as name, i}
						<option value={i}>{name}</option>
					{/each}
				</select>
			</div>
		{:else if form.frequency === 'interval'}
			<div class="space-y-1.5">
				<Label for="notify-interval">Alle N Stunden</Label>
				<select
					id="notify-interval"
					class="h-9 w-full rounded-md border border-input bg-background px-3 py-1 text-sm"
					bind:value={form.intervalHours}
				>
					{#each Array(23) as _, i}
						<option value={i + 1}>alle {i + 1} Stunde{i + 1 === 1 ? '' : 'n'}</option>
					{/each}
				</select>
			</div>
		{/if}

		{#if form.frequency === 'daily' || form.frequency === 'weekly'}
			<div class="space-y-1.5">
				<Label for="notify-time">Uhrzeit</Label>
				<Input id="notify-time" bind:value={form.time} type="time" />
			</div>
		{/if}

		<div class="space-y-1.5">
			<Label>Kategorien</Label>
			<div class="flex flex-wrap gap-x-4 gap-y-2 pt-1">
				{#each notifyCatOptions() as name (name)}
					<div class="flex items-center gap-2">
						<Checkbox
							id={`notify-cat-${name}`}
							checked={form.categories.includes(name)}
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
				bind:value={form.url}
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
				bind:value={form.token}
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
				bind:value={form.prompt}
				rows={3}
				spellcheck={false}
				class="font-mono text-xs"
			/>
			<p class="text-xs text-muted-foreground">{PROMPT_HINT}</p>
		</div>
	</div>

	<div class="mt-4 flex flex-wrap items-center gap-2">
		<Button size="sm" disabled={busy.saving || !form.time.trim()} onclick={saveNotifyCfg}>
			{#if busy.saving}<Spinner class="size-3.5" />{/if}
			<span>Speichern</span>
		</Button>
		<Button size="sm" disabled={busy.sending || !notify?.url || !notify?.hasToken} onclick={sendNow}>
			{#if busy.sending}<Spinner class="size-3.5" />{:else}<SendIcon class="size-3.5" />{/if}
			<span>Jetzt senden</span>
		</Button>
		<Button size="sm" variant="outline" disabled={busy.testing} onclick={testNotify}>
			{#if busy.testing}<Spinner class="size-3.5" />{:else}<PlugZapIcon class="size-3.5" />{/if}
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
{#if testResult}
	<div
		class={
			'space-y-2 rounded-xl border p-5 ' +
			(testResult.ok
				? 'border-emerald-500/30 bg-emerald-500/5'
				: 'border-destructive/40 bg-destructive/5')
		}
	>
		<div class="flex items-center gap-2">
			{#if testResult.ok}
				<CheckCircleIcon class="size-4 text-emerald-600 dark:text-emerald-400" />
				<span class="text-sm font-medium text-emerald-700 dark:text-emerald-400">
					Webhook angenommen
				</span>
			{:else}
				<CircleXIcon class="size-4 text-destructive" />
				<span class="text-sm font-medium text-destructive">Webhook-Test fehlgeschlagen</span>
			{/if}
		</div>
		{#if testResult.ok}
			<p class="text-sm text-muted-foreground">
				HTTP {testResult.status ?? '—'}
				{#if testResult.outcome}
					· Ergebnis: {testResult.outcome}
				{/if}
				— die Nachricht sollte jetzt bei deinem Empfänger angekommen sein.
			</p>
		{:else if testResult.error}
			<p class="text-sm text-destructive">{testResult.error}</p>
		{/if}
	</div>
{/if}
