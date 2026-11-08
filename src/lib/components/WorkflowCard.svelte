<script lang="ts">
	import { api } from '$lib/api';
	import type { Workflow, WorkflowStep } from '$lib/types';
	import { toast } from 'svelte-sonner';
	import Card from '$lib/components/ui/card/card.svelte';
	import CardHeader from '$lib/components/ui/card/card-header.svelte';
	import CardTitle from '$lib/components/ui/card/card-title.svelte';
	import CardContent from '$lib/components/ui/card/card-content.svelte';
	import Button from '$lib/components/ui/button/button.svelte';
	import Input from '$lib/components/ui/input/input.svelte';
	import Textarea from '$lib/components/ui/textarea/textarea.svelte';
	import Checkbox from '$lib/components/ui/checkbox/checkbox.svelte';
	import Progress from '$lib/components/ui/progress/progress.svelte';
	import Badge from '$lib/components/ui/badge/badge.svelte';
	import Separator from '$lib/components/ui/separator/separator.svelte';
	import { cn } from '$lib/utils';
	import CheckIcon from '@lucide/svelte/icons/check';
	import ChevronDownIcon from '@lucide/svelte/icons/chevron-down';
	import PencilIcon from '@lucide/svelte/icons/pencil';
	import PlayIcon from '@lucide/svelte/icons/play';
	import PlusIcon from '@lucide/svelte/icons/plus';
	import RotateCcwIcon from '@lucide/svelte/icons/rotate-ccw';
	import TargetIcon from '@lucide/svelte/icons/target';
	import TrashIcon from '@lucide/svelte/icons/trash';
	import XIcon from '@lucide/svelte/icons/x';

	let {
		wf,
		sync,
		remove
	}: {
		wf: Workflow;
		sync: (w: Workflow) => void;
		remove: (id: string) => void;
	} = $props();

	let busy = $state(false);
	let collapsed = $state(false);
	let newStep = $state('');

	let editingTitle = $state(false);
	let titleDraft = $state(wf.title);

	let editingNotes = $state(false);
	let notesDraft = $state(wf.notes);

	let percent = $derived(Math.round(wf.progress * 100));
	let activeStep = $derived(wf.steps.find((s) => s.id === wf.activeStepId) ?? null);
	let doneCount = $derived(wf.steps.filter((s) => s.done).length);

	function errMsg(e: unknown): string {
		return e instanceof Error ? e.message : String(e);
	}

	function startTitle(): void {
		titleDraft = wf.title;
		editingTitle = true;
	}

	async function saveTitle(): Promise<void> {
		const t = titleDraft.trim();
		editingTitle = false;
		if (!t || t === wf.title) return;
		busy = true;
		try {
			sync(await api.updateWorkflow(wf.id, { title: t }));
		} catch (e) {
			toast.error(errMsg(e));
		} finally {
			busy = false;
		}
	}

	function startNotes(): void {
		notesDraft = wf.notes;
		editingNotes = true;
	}

	async function saveNotes(): Promise<void> {
		editingNotes = false;
		if (notesDraft === wf.notes) return;
		busy = true;
		try {
			sync(await api.updateWorkflow(wf.id, { notes: notesDraft }));
		} catch (e) {
			toast.error(errMsg(e));
		} finally {
			busy = false;
		}
	}

	async function toggleStep(step: WorkflowStep): Promise<void> {
		try {
			sync(await api.updateStep(wf.id, step.id, { done: !step.done }));
		} catch (e) {
			toast.error(errMsg(e));
		}
	}

	async function deleteStep(step: WorkflowStep): Promise<void> {
		try {
			sync(await api.deleteStep(wf.id, step.id));
		} catch (e) {
			toast.error(errMsg(e));
		}
	}

	async function addStep(): Promise<void> {
		const t = newStep.trim();
		if (!t) return;
		try {
			sync(await api.addStep(wf.id, t));
			newStep = '';
		} catch (e) {
			toast.error(errMsg(e));
		}
	}

	async function reset(): Promise<void> {
		if (!confirm('Workflow wirklich zurücksetzen? Alle Schritte werden als offen markiert.')) return;
		try {
			sync(await api.resetWorkflow(wf.id));
			toast.success('Workflow zurückgesetzt.');
		} catch (e) {
			toast.error(errMsg(e));
		}
	}

	async function del(): Promise<void> {
		if (!confirm(`Workflow „${wf.title}" wirklich löschen?`)) return;
		try {
			await api.deleteWorkflow(wf.id);
			remove(wf.id);
			toast.success('Workflow gelöscht.');
		} catch (e) {
			toast.error(errMsg(e));
		}
	}
</script>

<Card class="group">
	<CardHeader class="gap-2">
		<div class="flex items-start gap-3">
			<div class="min-w-0 flex-1">
				{#if editingTitle}
					<div class="flex items-center gap-2">
						<Input bind:value={titleDraft} class="h-8 text-sm" maxlength={120} />
						<Button size="icon-sm" disabled={busy} onclick={saveTitle} aria-label="Speichern">
							<CheckIcon class="size-4" />
						</Button>
						<Button size="icon-sm" variant="ghost" onclick={() => (editingTitle = false)} aria-label="Abbrechen">
							<XIcon class="size-4" />
						</Button>
					</div>
				{:else}
					<CardTitle class="flex items-center gap-2">
						<span class="min-w-0 truncate">{wf.title}</span>
						{#if wf.completedAt}
							<Badge variant="secondary" class="shrink-0">
								<ChevronDownIcon class="hidden size-0" />
								erledigt
							</Badge>
						{:else if wf.activeStepId}
							<Badge class="shrink-0" variant="outline">
								<TargetIcon class="size-3" />
								aktiv
							</Badge>
						{/if}
						<button
							type="button"
							class="ml-auto shrink-0 rounded p-1 text-muted-foreground opacity-0 transition-opacity hover:bg-muted hover:text-foreground group-hover:opacity-100 focus-visible:opacity-100"
							onclick={startTitle}
							aria-label="Titel bearbeiten"
						>
							<PencilIcon class="size-3.5" />
						</button>
					</CardTitle>
					<p class="mt-1 text-xs tabular-nums text-muted-foreground">
						{doneCount}/{wf.steps.length} Schritte · {percent} %
					</p>
				{/if}
			</div>
		</div>

		<div class="flex items-center gap-1">
			<Button
				variant="ghost"
				size="icon-sm"
				href="/fokus/{wf.id}"
				aria-label="Fokusmodus öffnen"
				title="Fokusmodus"
			>
				<PlayIcon class="size-3.5" />
			</Button>
			<Button
				variant="ghost"
				size="icon-sm"
				disabled={busy || wf.completedAt != null}
				onclick={reset}
				aria-label="Zurücksetzen"
				title="Zurücksetzen"
			>
				<RotateCcwIcon class="size-3.5" />
			</Button>
			<Button
				variant="ghost"
				size="icon-sm"
				onclick={del}
				aria-label="Löschen"
				title="Löschen"
			>
				<TrashIcon class="size-3.5" />
			</Button>
			<Button
				variant="ghost"
				size="icon-sm"
				onclick={() => (collapsed = !collapsed)}
				aria-label={collapsed ? 'Ausklappen' : 'Einklappen'}
				class="group/chev"
			>
				<ChevronDownIcon class="size-4 transition-transform group-data-[collapsed=true]/chev:-rotate-90" />
			</Button>
		</div>
	</CardHeader>

	{#if !collapsed}
		<CardContent class="space-y-4">
			<Progress value={percent} max={100} class="h-1.5" />

			{#if wf.notes || editingNotes}
				<div class="space-y-1.5">
					{#if editingNotes}
						<Textarea bind:value={notesDraft} placeholder="Notizen …" class="min-h-20 text-sm" />
						<div class="flex justify-end gap-2">
							<Button size="sm" variant="ghost" onclick={() => (editingNotes = false)}>
								Abbrechen
							</Button>
							<Button size="sm" disabled={busy} onclick={saveNotes}>
								Speichern
							</Button>
						</div>
					{:else}
						<div class="flex items-start gap-2 rounded-lg bg-muted/40 p-3">
							<p class="min-w-0 flex-1 whitespace-pre-wrap text-sm text-muted-foreground">
								{wf.notes || ' '}
							</p>
							<button
								type="button"
								class="shrink-0 rounded p-1 text-muted-foreground transition-colors hover:bg-muted hover:text-foreground"
								onclick={startNotes}
								aria-label="Notizen bearbeiten"
							>
								<PencilIcon class="size-3.5" />
							</button>
						</div>
					{/if}
				</div>
			{/if}

			<ul class="space-y-1.5">
				{#each wf.steps as step, i (step.id)}
					{@const isActive = step.id === wf.activeStepId}
					<li
						class={cn(
							'flex items-center gap-3 rounded-lg border p-2.5 transition-colors',
							isActive
								? 'border-primary/40 bg-primary/5'
								: 'border-transparent hover:bg-muted/40'
						)}
					>
						<span class="w-5 shrink-0 text-right text-xs tabular-nums text-muted-foreground">
							{i + 1}
						</span>
						<Checkbox
							checked={step.done}
							disabled={busy}
							onchange={() => toggleStep(step)}
							aria-label="Schritt als erledigt markieren"
						/>
						<span
							class={cn(
								'min-w-0 flex-1 truncate text-sm',
								step.done && 'text-muted-foreground line-through'
							)}
						>
							{step.title}
						</span>
							{#if isActive && !step.done}
								<Badge class="shrink-0" variant="secondary">
									<TargetIcon class="size-3" />
									jetzt
								</Badge>
							{/if}
						<button
							type="button"
							class="shrink-0 rounded p-1 text-muted-foreground transition-colors hover:bg-muted hover:text-destructive"
							onclick={() => deleteStep(step)}
							aria-label="Schritt löschen"
						>
							<XIcon class="size-3.5" />
						</button>
					</li>
				{/each}
			</ul>

			<Separator />

			<div class="flex items-center gap-2">
				<Input
					bind:value={newStep}
					class="h-8 text-sm"
					placeholder="Schritt hinzufügen …"
					maxlength={160}
					onkeydown={(e) => {
						if (e.key === 'Enter') {
							e.preventDefault();
							addStep();
						}
					}}
				/>
				<Button size="icon-sm" disabled={!newStep.trim()} onclick={addStep} aria-label="Schritt hinzufügen">
					<PlusIcon class="size-4" />
				</Button>
			</div>
		</CardContent>
	{/if}
</Card>
