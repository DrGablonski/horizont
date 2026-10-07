<!-- KI-Agent: eigene (pro-User) Konfiguration – überschreibt die globale Config. -->

<script lang="ts">
	import { onMount } from 'svelte';
	import type { AgentProvider, AgentSettingsView } from '$lib/types';
	import Button from '$lib/components/ui/button/button.svelte';
	import Input from '$lib/components/ui/input/input.svelte';
	import Label from '$lib/components/ui/label/label.svelte';
	import Badge from '$lib/components/ui/badge/badge.svelte';
	import Spinner from '$lib/components/ui/spinner/spinner.svelte';
	import { toast } from 'svelte-sonner';
	import BotIcon from '@lucide/svelte/icons/bot';
	import CheckCircleIcon from '@lucide/svelte/icons/circle-check';
	import CircleXIcon from '@lucide/svelte/icons/circle-x';
	import PlugZapIcon from '@lucide/svelte/icons/plug-zap';
	import RotateIcon from '@lucide/svelte/icons/rotate-ccw';

	function errMsg(e: unknown): string {
		return e instanceof Error ? e.message : String(e);
	}

	let view = $state<AgentSettingsView | null>(null);
	let loading = $state(true);

	let fProvider = $state<AgentProvider>('openai');
	let fBaseUrl = $state('');
	let fModel = $state('');
	let fApiKey = $state('');

	let saving = $state(false);
	let resetting = $state(false);
	let testing = $state(false);
	let testResult = $state<{ ok: boolean; error?: string; reply?: string } | null>(null);

	function resetForm(): void {
		if (!view) return;
		const src = view.own.configured ? view.own : view.global.configured ? view.global : null;
		fProvider = src?.provider ?? 'openai';
		fBaseUrl = src?.baseUrl ?? '';
		fModel = src?.model ?? '';
		fApiKey = '';
	}

	async function load(): Promise<void> {
		try {
			const res = await fetch('/api/agent/settings');
			if (!res.ok) throw new Error(`HTTP ${res.status}`);
			view = (await res.json()) as AgentSettingsView;
			resetForm();
		} catch (e) {
			toast.error(errMsg(e));
		} finally {
			loading = false;
		}
	}

	async function save(): Promise<void> {
		if (!fBaseUrl.trim() || !fModel.trim()) {
			toast.error('Basis-URL und Modell sind erforderlich.');
			return;
		}
		saving = true;
		try {
			const res = await fetch('/api/agent/settings', {
				method: 'PUT',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify({
					provider: fProvider,
					baseUrl: fBaseUrl,
					model: fModel,
					apiKey: fApiKey || undefined
				})
			});
			const body = (await res.json().catch(() => null)) as { own?: AgentSettingsView['own']; error?: string } | null;
			if (!res.ok) throw new Error(body?.error ?? `HTTP ${res.status}`);
			if (body?.own) {
				view = view ? { ...view, own: body.own } : view;
				fApiKey = '';
			}
			toast.success('KI-Agent-Konfiguration gespeichert.');
		} catch (e) {
			toast.error(errMsg(e));
		} finally {
			saving = false;
		}
	}

	async function resetToGlobal(): Promise<void> {
		if (!confirm('Eigene Konfiguration entfernen und die globale Config nutzen?')) return;
		resetting = true;
		try {
			const res = await fetch('/api/agent/settings', {
				method: 'PUT',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify({ reset: true })
			});
			const body = (await res.json().catch(() => null)) as { own?: AgentSettingsView['own']; error?: string } | null;
			if (!res.ok) throw new Error(body?.error ?? `HTTP ${res.status}`);
			if (body?.own) {
				view = view ? { ...view, own: body.own } : view;
				resetForm();
			}
			toast.success('Auf globale Konfiguration zurückgesetzt.');
		} catch (e) {
			toast.error(errMsg(e));
		} finally {
			resetting = false;
		}
	}

	async function test(): Promise<void> {
		if (!fBaseUrl.trim() || !fModel.trim()) {
			toast.error('Basis-URL und Modell sind erforderlich.');
			return;
		}
		testing = true;
		testResult = null;
		try {
			const res = await fetch('/api/agent/settings/test', {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify({
					provider: fProvider,
					baseUrl: fBaseUrl,
					model: fModel,
					apiKey: fApiKey || undefined
				})
			});
			testResult = (await res.json()) as { ok: boolean; error?: string; reply?: string };
			if (!testResult.ok) throw new Error(testResult.error ?? 'Test fehlgeschlagen.');
			toast.success('Verbindung erfolgreich.');
		} catch (e) {
			testResult = { ok: false, error: errMsg(e) };
			toast.error('VerbindungsTest fehlgeschlagen.');
		} finally {
			testing = false;
		}
	}

	onMount(() => {
		load();
	});

	const effective = $derived(
		view == null
			? null
			: view.own.configured
				? 'eigene Config'
				: view.global.enabled && view.global.configured
					? 'globale Config'
					: null
	);
</script>

<section class="space-y-3">
	<div class="flex items-center gap-2">
		<BotIcon class="size-4" />
		<h2 class="text-sm font-semibold">KI-Agent</h2>
		{#if effective}
			<Badge variant="secondary" class="text-[10px] text-emerald-700 dark:text-emerald-400">
				<CheckCircleIcon class="size-3" />
				{effective}
			</Badge>
		{:else}
			<Badge variant="outline" class="text-[10px]">
				<CircleXIcon class="size-3" />
				nicht aktiv
			</Badge>
		{/if}
	</div>
	<p class="text-xs text-muted-foreground">
		Frage über das Chat-Widget (unten rechts) nach Terminen, Aufgaben oder Workflows.
		Schreibaktionen bestätigt du vorab. Nutze deine eigene Konfiguration oder die
		global vom Administrator.
	</p>

	{#if loading && !view}
		<div class="flex items-center gap-2 rounded-xl border border-dashed border-border p-8 text-sm text-muted-foreground">
			<Spinner class="size-4" />
			<span>Wird geladen …</span>
		</div>
	{:else if view}
		<div class="space-y-4 rounded-xl border border-border bg-card p-5">
			<div class="grid gap-4 sm:grid-cols-2">
				<div class="space-y-1.5">
					<Label for="agent-provider">Provider</Label>
					<select
						id="agent-provider"
						class="flex h-9 w-full rounded-md border border-input bg-background px-3 py-1 text-sm"
						bind:value={fProvider}
					>
						<option value="openai">OpenAI-kompatibel</option>
						<option value="ollama">Ollama (lokal)</option>
					</select>
				</div>
				<div class="space-y-1.5">
					<Label for="agent-base">Basis-URL</Label>
					<Input
						id="agent-base"
						bind:value={fBaseUrl}
						type="url"
						placeholder={fProvider === 'ollama' ? 'http://192.168.1.10:11434' : 'https://api.openai.com/v1'}
					/>
				</div>
				<div class="space-y-1.5">
					<Label for="agent-model">Modell</Label>
					<Input id="agent-model" bind:value={fModel} placeholder={fProvider === 'ollama' ? 'llama3.1' : 'gpt-4o-mini'} />
				</div>
				<div class="space-y-1.5">
					<Label for="agent-key">
						API-Key {view.own.hasApiKey ? '(gesetzt – leer lassen zum Beibehalten)' : fProvider === 'openai' ? '(bei OpenAI erforderlich)' : ''}
					</Label>
					<Input
						id="agent-key"
						bind:value={fApiKey}
						type="password"
						placeholder={view.own.hasApiKey ? '●●●● (beibehalten)' : fProvider === 'ollama' ? 'nicht benötigt' : 'sk-…'}
						autocomplete="off"
					/>
				</div>
			</div>

			{#if !view.own.configured && view.global.configured}
				<p class="text-xs text-muted-foreground">
					Ausgangsform: globale Config ({view.global.baseUrl} · {view.global.model}) – speichern,
					damit du sie für dich anpassen kannst.
				</p>
			{/if}

			<div class="flex flex-wrap items-center gap-2">
				<Button size="sm" disabled={saving || !fBaseUrl.trim() || !fModel.trim()} onclick={save}>
					{#if saving}<Spinner class="size-3.5" />{/if}
					<span>Speichern</span>
				</Button>
				<Button size="sm" variant="outline" disabled={testing || !fBaseUrl.trim() || !fModel.trim()} onclick={test}>
					{#if testing}<Spinner class="size-3.5" />{:else}<PlugZapIcon class="size-3.5" />{/if}
					<span>Erst testen</span>
				</Button>
				{#if view.own.configured}
					<Button size="sm" variant="ghost" disabled={resetting} onclick={resetToGlobal}>
						{#if resetting}<Spinner class="size-3.5" />{:else}<RotateIcon class="size-3.5" />{/if}
						<span>Zurück auf Global</span>
					</Button>
				{/if}
			</div>

			{#if testResult}
				<div
					class={
						'flex items-start gap-2 rounded-md px-3 py-2 text-sm ' +
						(testResult.ok
							? 'bg-emerald-500/10 text-emerald-700 dark:text-emerald-400'
							: 'bg-destructive/10 text-destructive')
					}
				>
					{#if testResult.ok}
						<CheckCircleIcon class="mt-0.5 size-4 shrink-0" />
						<span>Verbindung erfolgreich.{testResult.reply ? ` Antwort: „{testResult.reply}“` : ''}</span>
					{:else}
						<CircleXIcon class="mt-0.5 size-4 shrink-0" />
						<span>{testResult.error ?? 'Test fehlgeschlagen.'}</span>
					{/if}
				</div>
			{/if}
		</div>
	{/if}
</section>
