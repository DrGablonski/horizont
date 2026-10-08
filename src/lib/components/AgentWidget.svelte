<!-- KI-Agent-Widget: schwebender Chat mit Bestätigungs-Cards für Schreibaktionen. -->

<script lang="ts">
	import { onMount } from 'svelte';
	import { agent, type AgentChatHandlers } from '$lib/agent';
	import type { AgentStatus } from '$lib/types';
	import Button from '$lib/components/ui/button/button.svelte';
	import Spinner from '$lib/components/ui/spinner/spinner.svelte';
	import { randomUUID } from '$lib/utils';
	import BotIcon from '@lucide/svelte/icons/bot';
	import XIcon from '@lucide/svelte/icons/x';
	import CheckIcon from '@lucide/svelte/icons/check';
	import ArrowUpIcon from '@lucide/svelte/icons/arrow-up';
	import RefreshIcon from '@lucide/svelte/icons/refresh-cw';

	interface ApprovalCard {
		approvalId: string;
		tool: string;
		summary: string;
		state: 'open' | 'accepted' | 'rejected';
	}

	interface UiMsg {
		id: string;
		role: 'user' | 'assistant';
		content: string;
		tools: { label: string; ok: boolean }[];
		approval?: ApprovalCard;
		error?: string;
	}

	const SUGGESTIONS = [
		'Was steht heute an?',
		'Welche Aufgaben habe ich noch offen?',
		'Zeig mir meine Kalender'
	];

	let status = $state<AgentStatus | null>(null);
	let open = $state(false);
	let sessionKey = $state(randomUUID());
	let msgs = $state<UiMsg[]>([]);
	let busy = $state(false);
	let draft = $state('');
	let note = $state('');
	let aborter = $state<AbortController | null>(null);
	let scrollBox: HTMLDivElement | undefined = $state();
	let inputEl: HTMLTextAreaElement | undefined = $state();

	let counter = 0;
	function nextId(): string {
		return `m${++counter}`;
	}

	/** Der Chat-Widget benachrichtigt andere Seiten, dass Daten sich geändert haben. */
	function notifyDataChanged(): void {
		window.dispatchEvent(new CustomEvent('horizont:agent-changed'));
	}

	function handlersFor(msg: UiMsg): AgentChatHandlers {
		return {
			onDelta: (t) => {
				msg.content += t;
			},
			onToolResult: (_name, ok, write, label) => {
				msg.tools.push({ label, ok });
				if (write && ok) notifyDataChanged();
			},
			onApproval: (a) => {
				msg.approval = { approvalId: a.approvalId, tool: a.tool, summary: a.summary, state: 'open' };
				note = '';
				busy = false;
			},
			onDone: () => {
				busy = false;
			},
			onError: (error) => {
				msg.error = error;
				busy = false;
			}
		};
	}

	async function send(textOverride?: string): Promise<void> {
		const text = (textOverride ?? draft).trim();
		if (!text || busy) return;
		draft = '';
		msgs.push({ id: nextId(), role: 'user', content: text, tools: [] });
		const a: UiMsg = { id: nextId(), role: 'assistant', content: '', tools: [] };
		msgs.push(a);
		busy = true;
		const ac = new AbortController();
		aborter = ac;
		const live = msgs[msgs.length - 1];
		try {
			await agent.chat(sessionKey, text, handlersFor(live), ac.signal);
		} finally {
			if (aborter === ac) aborter = null;
			busy = false;
		}
	}

	function stop(): void {
		aborter?.abort();
	}

	async function decide(decision: 'accept' | 'reject'): Promise<void> {
		const openMsg = msgs.find((m) => m.approval?.state === 'open');
		if (!openMsg?.approval || busy) return;
		const card = openMsg.approval;
		const ac = new AbortController();
		aborter = ac;
		busy = true;
		const next: UiMsg = { id: nextId(), role: 'assistant', content: '', tools: [] };
		msgs.push(next);
		const live = msgs[msgs.length - 1];
		try {
			await agent.approve(
				sessionKey,
				card.approvalId,
				decision,
				note.trim() || undefined,
				handlersFor(live),
				ac.signal
			);
			card.state = decision === 'accept' ? 'accepted' : 'rejected';
		} finally {
			if (aborter === ac) aborter = null;
			busy = false;
		}
	}

	function restart(): void {
		stop();
		sessionKey = randomUUID();
		msgs = [];
		draft = '';
		note = '';
	}

	function onInputKey(e: KeyboardEvent): void {
		if (e.key === 'Enter' && !e.shiftKey) {
			e.preventDefault();
			send();
		}
	}

	async function refreshStatus(): Promise<void> {
		try {
			status = await agent.status();
		} catch {
			status = { available: false, source: null, provider: null, model: null, baseUrl: null };
		}
	}

	onMount(() => {
		refreshStatus();
		// z. B. nach dem An-/Ausschalten der KI-Funktionen in den Einstellungen.
		function onRefresh(): void {
			refreshStatus();
		}
		window.addEventListener('horizont:agent-refresh', onRefresh);
		return () => {
			window.removeEventListener('horizont:agent-refresh', onRefresh);
			aborter?.abort();
		};
	});

	// Automatisch nach unten scrollen, wenn sich der Inhalt ändert.
	$effect(() => {
		const last = msgs[msgs.length - 1];
		const contentLen = last?.content.length ?? 0;
		const toolsLen = last?.tools.length ?? 0;
		const approvalState = last?.approval?.state ?? '';
		const len = msgs.length;
		void contentLen;
		void toolsLen;
		void approvalState;
		void len;
		if (scrollBox) {
			const el = scrollBox;
			requestAnimationFrame(() => (el.scrollTop = el.scrollHeight));
		}
	});

	// Nach dem Öffnen: Fokus ins Eingabefeld.
	$effect(() => {
		if (open) inputEl?.focus();
	});

	const visible = $derived(status?.available === true);
</script>

{#if visible}
	{#if open}
		<div
			class="fixed bottom-20 right-4 z-50 flex h-[min(34rem,calc(100dvh-8.5rem))] w-[min(24rem,calc(100vw-2rem))] flex-col overflow-hidden rounded-xl border border-border bg-background shadow-2xl"
			role="dialog"
			aria-label="KI-Agent"
		>
			<!-- Kopf -->
			<div class="flex items-center gap-2 border-b border-border px-3 py-2.5">
				<BotIcon class="size-4 text-primary" />
				<div class="min-w-0 flex-1">
					<p class="text-sm font-medium leading-tight">KI-Agent</p>
					<p class="truncate text-[11px] text-muted-foreground">
						{status?.provider} · {status?.model}
					</p>
				</div>
				<Button variant="ghost" size="icon" title="Chat zurücksetzen" disabled={busy} onclick={restart}>
					<RefreshIcon class="size-3.5" />
				</Button>
				<Button variant="ghost" size="icon" title="Schließen" onclick={() => (open = false)}>
					<XIcon class="size-3.5" />
				</Button>
			</div>

			<!-- Nachrichten -->
			<div class="flex-1 space-y-3 overflow-y-auto p-3" bind:this={scrollBox}>
				{#if msgs.length === 0}
					<div class="space-y-3 pt-6 text-center">
						<p class="text-sm text-muted-foreground">
							Frage mich nach Terminen, Aufgaben oder Workflows – oder lass mich etwas anlegen.
							Eindeutige Aktionen führe ich direkt aus – bin ich unsicher, frage ich vorher nach.
						</p>
						<div class="flex flex-col items-center gap-1.5">
							{#each SUGGESTIONS as s (s)}
								<button
									type="button"
									class="rounded-full border border-border px-3 py-1.5 text-xs text-muted-foreground transition-colors hover:bg-muted hover:text-foreground"
									onclick={() => send(s)}
								>
									{s}
								</button>
							{/each}
						</div>
					</div>
				{/if}

				{#each msgs as m (m.id)}
					{#if m.role === 'user'}
						<div class="flex justify-end">
							<div class="max-w-[85%] rounded-lg bg-primary px-3 py-2 text-sm text-primary-foreground">
								{m.content}
							</div>
						</div>
					{:else}
						<div class="space-y-2">
							{#if m.content}
								<p class="whitespace-pre-wrap break-words text-sm leading-relaxed">{m.content}</p>
							{:else if busy && m.id === (msgs[msgs.length - 1]?.id ?? '')}
								<div class="flex items-center gap-2 text-sm text-muted-foreground">
									<Spinner class="size-3.5" />
									<span>Denke nach …</span>
								</div>
							{/if}

							{#if m.tools.length > 0}
								<div class="flex flex-wrap gap-1.5">
									{#each m.tools as t (t)}
										<span
											class={
												'rounded-full border px-2 py-0.5 text-[11px] ' +
												(t.ok
													? 'border-border text-muted-foreground'
													: 'border-destructive/40 text-destructive')
											}
										>
											{t.label}{t.ok ? '' : ' · fehlgeschlagen'}
										</span>
									{/each}
								</div>
							{/if}

							{#if m.approval}
								<div
									class={
										'space-y-2 rounded-lg border p-3 ' +
										(m.approval.state === 'open'
											? 'border-amber-500/40 bg-amber-500/5'
											: m.approval.state === 'accepted'
												? 'border-emerald-500/30 bg-emerald-500/5'
												: 'border-border bg-muted/30')
									}
								>
									<div class="flex items-start gap-2">
										<span class="mt-0.5 shrink-0 rounded bg-muted px-1.5 py-0.5 text-[10px] font-medium uppercase tracking-wide text-muted-foreground">
											Bestätigung
										</span>
										<p class="text-sm">{m.approval.summary}</p>
									</div>
									{#if m.approval.state === 'open'}
										<div class="space-y-2">
											<textarea
												rows="1"
												class="w-full resize-none rounded-md border border-input bg-background px-2.5 py-1.5 text-sm"
												placeholder="Optionale Korrektur (v. a. bei Ablehnen)"
												bind:value={note}
											></textarea>
											<div class="flex gap-2">
												<Button size="sm" disabled={busy} onclick={() => decide('accept')}>
													{#if busy}<Spinner class="size-3.5" />{:else}<CheckIcon class="size-3.5" />{/if}
													<span>Freigeben</span>
												</Button>
												<Button size="sm" variant="outline" disabled={busy} onclick={() => decide('reject')}>
													<XIcon class="size-3.5" />
													<span>Ablehnen</span>
												</Button>
											</div>
										</div>
									{:else}
										<p
											class={
												'text-xs ' +
												(m.approval.state === 'accepted' ? 'text-emerald-600 dark:text-emerald-400' : 'text-muted-foreground')
											}
										>
											{m.approval.state === 'accepted' ? 'Freigegeben' : 'Abgelehnt'}
										</p>
									{/if}
								</div>
							{/if}

							{#if m.error}
								<p class="rounded-md border border-destructive/40 bg-destructive/5 px-2.5 py-1.5 text-sm text-destructive">
									{m.error}
								</p>
							{/if}
						</div>
					{/if}
				{/each}
			</div>

			<!-- Eingabe -->
			<div class="flex items-end gap-2 border-t border-border p-2.5">
				<textarea
					rows="1"
					class="max-h-28 flex-1 resize-none rounded-md border border-input bg-background px-2.5 py-2 text-sm"
					placeholder="Nachricht … (Enter senden)"
					bind:value={draft}
					bind:this={inputEl}
					onkeydown={onInputKey}
				></textarea>
				{#if busy}
					<Button variant="outline" size="icon" title="Abbrechen" onclick={stop}>
						<XIcon class="size-4" />
					</Button>
				{:else}
					<Button size="icon" title="Senden" disabled={!draft.trim()} onclick={() => send()}>
						<ArrowUpIcon class="size-4" />
					</Button>
				{/if}
			</div>
		</div>
	{/if}

	<button
		type="button"
		class="fixed bottom-5 right-4 z-50 grid size-12 place-items-center rounded-full bg-primary text-primary-foreground shadow-lg transition-transform hover:scale-105"
		title="KI-Agent"
		aria-label="KI-Agent öffnen"
		onclick={() => (open = !open)}
	>
		{#if open}
			<XIcon class="size-5" />
		{:else}
			<BotIcon class="size-5" />
		{/if}
	</button>
{/if}
