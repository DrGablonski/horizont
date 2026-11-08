<script lang="ts">
	import { page } from '$app/state';
	import { goto } from '$app/navigation';
	import { api } from '$lib/api';
	import type { Workflow, WorkflowStep } from '$lib/types';
	import Button from '$lib/components/ui/button/button.svelte';
	import Progress from '$lib/components/ui/progress/progress.svelte';
	import Separator from '$lib/components/ui/separator/separator.svelte';
	import Spinner from '$lib/components/ui/spinner/spinner.svelte';
	import { toast } from 'svelte-sonner';
	import TargetIcon from '@lucide/svelte/icons/target';
	import CheckIcon from '@lucide/svelte/icons/check';
	import CheckCheckIcon from '@lucide/svelte/icons/check-check';
	import RotateCcwIcon from '@lucide/svelte/icons/rotate-ccw';
	import ArrowLeftIcon from '@lucide/svelte/icons/arrow-left';
	import FlagIcon from '@lucide/svelte/icons/flag';

	const id = $derived(page.params.id ?? '');

	let wf = $state<Workflow | null>(null);
	let loading = $state(true);
	let notFound = $state(false);
	let busy = $state(false);
	let seq = 0;

	function errMsg(e: unknown): string {
		return e instanceof Error ? e.message : String(e);
	}

	function back(): void {
		void goto('/');
	}

	async function load(): Promise<void> {
		const my = ++seq;
		if (!id) {
			notFound = true;
			loading = false;
			return;
		}
		loading = true;
		notFound = false;
		try {
			const w = await api.workflow(id);
			if (my !== seq) return;
			wf = w;
		} catch (e) {
			if (my !== seq) return;
			notFound = true;
			toast.error(errMsg(e));
		} finally {
			if (my === seq) loading = false;
		}
	}

	$effect(() => {
		load();
	});

	async function toggleStep(step: WorkflowStep): Promise<void> {
		if (!wf) return;
		const my = ++seq;
		busy = true;
		try {
			const updated = await api.updateStep(id, step.id, { done: !step.done });
			if (my === seq) wf = updated;
		} catch (e) {
			toast.error(errMsg(e));
		} finally {
			if (my === seq) busy = false;
		}
	}

	async function reset(): Promise<void> {
		if (!wf) return;
		if (!confirm('Alle Fortschritte zurücksetzen?')) return;
		busy = true;
		try {
			wf = await api.resetWorkflow(id);
			toast.success('Workflow zurückgesetzt.');
		} catch (e) {
			toast.error(errMsg(e));
		} finally {
			busy = false;
		}
	}

	const activeStep = $derived.by(() => {
		const w = wf;
		if (!w) return null;
		return w.steps.find((s) => s.id === w.activeStepId) ?? null;
	});

	const nextStep = $derived.by(() => {
		const w = wf;
		if (!w) return null;
		return w.steps.filter((s) => !s.done).find((s) => s.id !== w.activeStepId) ?? null;
	});
	const doneCount = $derived(wf?.steps.filter((s) => s.done).length ?? 0);
	const allDone = $derived(
		!!wf && wf.steps.length > 0 && wf.steps.every((s) => s.done)
	);
</script>

<div class="mx-auto max-w-2xl space-y-6">
	<div class="flex items-center justify-between gap-3">
		<button
			class="flex items-center gap-1.5 text-sm text-muted-foreground transition-colors hover:text-foreground"
			onclick={back}
		>
			<ArrowLeftIcon class="size-4" />
			<span>Zur Übersicht</span>
		</button>
		<FlagIcon class="size-4 text-muted-foreground" />
	</div>

	{#if loading}
		<div class="flex items-center justify-center gap-2 rounded-xl border border-dashed border-border p-12 text-sm text-muted-foreground">
			<Spinner class="size-4" />
			<span>Wird geladen …</span>
		</div>
	{:else if notFound || !wf}
		<div class="space-y-4 rounded-xl border border-dashed border-border p-12 text-center">
			<p class="text-sm text-muted-foreground">Workflow nicht gefunden.</p>
			<Button variant="outline" size="sm" onclick={back}>Zur Übersicht</Button>
		</div>
	{:else}
		<div class="space-y-6">
			<div class="space-y-1">
				<div class="flex items-center gap-2 text-xs font-medium uppercase tracking-wide text-muted-foreground">
					<TargetIcon class="size-3.5" />
					<span>Fokus</span>
				</div>
				<h1 class="text-2xl font-semibold tracking-tight">{wf.title}</h1>
				{#if wf.notes}
					<p class="text-sm text-muted-foreground">{wf.notes}</p>
				{/if}
			</div>

			<div class="space-y-2">
				<div class="flex items-center justify-between text-xs text-muted-foreground">
					<span>{doneCount} / {wf.steps.length} Schritte</span>
					<span>{Math.round(wf.progress * 100)} %</span>
				</div>
				<Progress value={wf.progress * 100} />
			</div>

			{#if allDone}
				<div class="space-y-4 rounded-xl border border-emerald-500/30 bg-emerald-500/5 p-8 text-center">
					<CheckCheckIcon class="mx-auto size-8 text-emerald-600 dark:text-emerald-400" />
					<h2 class="text-lg font-semibold text-emerald-700 dark:text-emerald-400">Alles erledigt.</h2>
					<p class="text-sm text-muted-foreground">
						Alle Schritte abgeschlossen. Starte bei Bedarf mit einem frischen Durchlauf.
					</p>
					<div class="flex justify-center">
						<Button variant="outline" size="sm" disabled={busy} onclick={reset}>
							<RotateCcwIcon class="size-4" />
							<span>Neu starten</span>
						</Button>
					</div>
				</div>
			{:else}
				{#if activeStep}
					<div class="space-y-4 rounded-xl border border-border bg-card p-6">
						<p class="text-xs font-medium uppercase tracking-wide text-muted-foreground">
							Aktueller Schritt
						</p>
						<div class="flex items-start gap-4">
							<button
								class="mt-0.5 flex size-9 shrink-0 items-center justify-center rounded-full border-2 border-primary text-primary transition-colors hover:bg-primary hover:text-primary-foreground"
								disabled={busy}
								onclick={() => toggleStep(activeStep)}
								aria-label="Als erledigt markieren"
							>
								<CheckIcon class="size-5" />
							</button>
							<div class="min-w-0 flex-1">
								<h3 class="break-words text-lg font-medium leading-snug">{activeStep.title}</h3>
							</div>
						</div>
						<Button class="w-full" disabled={busy} onclick={() => toggleStep(activeStep)}>
							<CheckIcon class="size-4" />
							<span>Als erledigt markieren</span>
						</Button>
					</div>
				{/if}

				{#if nextStep}
					<div class="flex items-center gap-2 rounded-lg border border-dashed border-border p-3 text-sm text-muted-foreground">
						<span class="text-xs font-medium uppercase tracking-wide">Als Nächstes</span>
						<span class="truncate">{nextStep.title}</span>
					</div>
				{/if}
			{/if}

			{#if wf.steps.length > 0}
				<div class="space-y-3">
					<Separator />
					<p class="text-xs font-medium uppercase tracking-wide text-muted-foreground">Alle Schritte</p>
					<ul class="space-y-1">
						{#each wf.steps as step, i (step.id)}
							<li>
								<button
									class={
										'flex w-full items-center gap-3 rounded-lg px-3 py-2 text-left text-sm transition-colors hover:bg-accent ' +
										(step.id === wf.activeStepId
											? 'bg-accent font-medium text-foreground'
											: 'text-muted-foreground')
									}
									disabled={busy}
									onclick={() => toggleStep(step)}
								>
									<span
										class={
											'flex size-5 shrink-0 items-center justify-center rounded-full border text-[11px] ' +
											(step.done
												? 'border-emerald-500/40 bg-emerald-500/10 text-emerald-600 dark:text-emerald-400'
												: 'border-border text-muted-foreground')
										}
									>
										{#if step.done}
											<CheckIcon class="size-3" />
										{:else}
											{i + 1}
										{/if}
									</span>
									<span class={step.done ? 'line-through opacity-60' : ''}>{step.title}</span>
								</button>
							</li>
						{/each}
					</ul>
				</div>
			{/if}

			<div class="flex items-center justify-end">
				<Button variant="ghost" size="sm" disabled={busy} onclick={reset}>
					<RotateCcwIcon class="size-4" />
					<span>Zurücksetzen</span>
				</Button>
			</div>
		</div>
	{/if}
</div>
