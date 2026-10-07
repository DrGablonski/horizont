<!-- Admin: globale KI-Agent-Konfiguration (Fallback für alle ohne eigene Config). -->

<script lang="ts">
	import { onMount } from 'svelte';
	import type { AgentProvider } from '$lib/types';
	import Button from '$lib/components/ui/button/button.svelte';
	import Input from '$lib/components/ui/input/input.svelte';
	import Label from '$lib/components/ui/label/label.svelte';
	import Badge from '$lib/components/ui/badge/badge.svelte';
	import Spinner from '$lib/components/ui/spinner/spinner.svelte';
	import Checkbox from '$lib/components/ui/checkbox/checkbox.svelte';
	import { toast } from 'svelte-sonner';
	import BotIcon from '@lucide/svelte/icons/bot';
	import CheckCircleIcon from '@lucide/svelte/icons/circle-check';
	import CircleXIcon from '@lucide/svelte/icons/circle-x';
	import PlugZapIcon from '@lucide/svelte/icons/plug-zap';
	import ShieldIcon from '@lucide/svelte/icons/shield-check';

	function errMsg(e: unknown): string {
		return e instanceof Error ? e.message : String(e);
	}

	interface GlobalView {
		enabled: boolean;
		configured: boolean;
		provider: AgentProvider;
		baseUrl: string;
		model: string;
		hasApiKey: boolean;
	}

	let view = $state<GlobalView | null>(null);
	let loading = $state(true);

	let fEnabled = $state(false);
	let fProvider = $state<AgentProvider>('openai');
	let fBaseUrl = $state('');
	let fModel = $state('');
	let fApiKey = $state('');

	let saving = $state(false);
	let testing = $state(false);
	let testResult = $state<{ ok: boolean; error?: string; reply?: string } | null>(null);

	function resetForm(): void {
		if (!view) return;
		fEnabled = view.enabled;
		fProvider = view.provider;
		fBaseUrl = view.baseUrl;
		fModel = view.model;
		fApiKey = '';
	}

	async function load(): Promise<void> {
		try {
			const res = await fetch('/api/admin/agent');
			if (!res.ok) throw new Error(`HTTP ${res.status}`);
			view = (await res.json()) as GlobalView;
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
			const res = await fetch('/api/admin/agent', {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify({
					enabled: fEnabled,
					provider: fProvider,
					baseUrl: fBaseUrl,
					model: fModel,
					apiKey: fApiKey || undefined
				})
			});
			const body = (await res.json().catch(() => null)) as GlobalView | { error?: string } | null;
			if (!res.ok || !body || body === null || 'configured' in body === false) {
				throw new Error((body as { error?: string } | null)?.error ?? `HTTP ${res.status}`);
			}
			view = body as GlobalView;
			fApiKey = '';
			toast.success('Globale KI-Agent-Konfiguration gespeichert.');
		} catch (e) {
			toast.error(errMsg(e));
		} finally {
			saving = false;
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
			const res = await fetch('/api/admin/agent/test', {
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
			toast.error('Verbindungstest fehlgeschlagen.');
		} finally {
			testing = false;
		}
	}

	onMount(() => {
		load();
	});
</script>

<section class="space-y-3">
	<div class="flex items-center gap-2">
		<BotIcon class="size-4" />
		<h2 class="text-sm font-semibold">KI-Agent (global)</h2>
		{#if view?.enabled && view?.configured}
			<Badge variant="secondary" class="text-[10px] text-emerald-700 dark:text-emerald-400">
				<CheckCircleIcon class="size-3" />
				aktiv
			</Badge>
		{:else}
			<Badge variant="outline" class="text-[10px]">
				<CircleXIcon class="size-3" />
				inaktiv
			</Badge>
		{/if}
	</div>
	<p class="text-xs text-muted-foreground">
		Gilt für alle Users ohne eigene KI-Agent-Config (siehe Tab „KI-Agent“ bei den
		Einstellungen). Deaktiviert = Chat-Widget für niemanden sichtbar.
	</p>

	{#if loading && !view}
		<div class="flex items-center gap-2 rounded-xl border border-dashed border-border p-8 text-sm text-muted-foreground">
			<Spinner class="size-4" />
			<span>Wird geladen …</span>
		</div>
	{:else if view}
		<div class="space-y-4 rounded-xl border border-border bg-card p-5">
			<div class="flex items-center gap-2">
				<Checkbox bind:checked={fEnabled} id="agent-enabled" />
				<Label for="agent-enabled" class="text-sm">Globale KI-Agent-Config für alle Users aktivieren</Label>
			</div>

			<div class="grid gap-4 sm:grid-cols-2">
				<div class="space-y-1.5">
					<Label for="g-provider">Provider</Label>
					<select
						id="g-provider"
						class="flex h-9 w-full rounded-md border border-input bg-background px-3 py-1 text-sm"
						bind:value={fProvider}
					>
						<option value="openai">OpenAI-kompatibel</option>
						<option value="ollama">Ollama (lokal)</option>
					</select>
				</div>
				<div class="space-y-1.5">
					<Label for="g-base">Basis-URL</Label>
					<Input
						id="g-base"
						bind:value={fBaseUrl}
						type="url"
						placeholder={fProvider === 'ollama' ? 'http://192.168.1.10:11434' : 'https://api.openai.com/v1'}
					/>
				</div>
				<div class="space-y-1.5">
					<Label for="g-model">Modell</Label>
					<Input id="g-model" bind:value={fModel} placeholder={fProvider === 'ollama' ? 'llama3.1' : 'gpt-4o-mini'} />
				</div>
				<div class="space-y-1.5">
					<Label for="g-key">
						API-Key {view.hasApiKey ? '(gesetzt – leer lassen zum Beibehalten)' : fProvider === 'openai' ? '(bei OpenAI erforderlich)' : ''}
					</Label>
					<Input
						id="g-key"
						bind:value={fApiKey}
						type="password"
						placeholder={view.hasApiKey ? '●●●● (beibehalten)' : fProvider === 'ollama' ? 'nicht benötigt' : 'sk-…'}
						autocomplete="off"
					/>
				</div>
			</div>

			<div class="flex flex-wrap items-center gap-2">
				<Button size="sm" disabled={saving || !fBaseUrl.trim() || !fModel.trim()} onclick={save}>
					{#if saving}<Spinner class="size-3.5" />{/if}
					<span>Speichern</span>
				</Button>
				<Button size="sm" variant="outline" disabled={testing || !fBaseUrl.trim() || !fModel.trim()} onclick={test}>
					{#if testing}<Spinner class="size-3.5" />{:else}<PlugZapIcon class="size-3.5" />{/if}
					<span>Erst testen</span>
				</Button>
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

			<div class="flex items-start gap-2 rounded-md border border-border bg-muted/40 px-3 py-2.5 text-xs text-muted-foreground">
				<ShieldIcon class="mt-0.5 size-3.5 shrink-0" />
				<span>
					Schreibaktionen (Termine, Aufgaben, Workflows anlegen/ändern/löschen) werden dem User immer als
					Bestätigungs-Karte vorgelegt. Der API-Key wird nur serverseitig gespeichert und nicht zurückgegeben.
				</span>
			</div>
		</div>
	{/if}
</section>
