<script lang="ts">
	import { onMount, tick } from 'svelte';
	import { api } from '$lib/api';
	import { errMsg } from '$lib/errors';
	import type { Workflow } from '$lib/types';
	import { toast } from 'svelte-sonner';
	import WorkflowCard from './WorkflowCard.svelte';
	import Button from '$lib/components/ui/button/button.svelte';
	import Input from '$lib/components/ui/input/input.svelte';
	import Label from '$lib/components/ui/label/label.svelte';
	import Textarea from '$lib/components/ui/textarea/textarea.svelte';
	import Spinner from '$lib/components/ui/spinner/spinner.svelte';
	import Skeleton from '$lib/components/ui/skeleton/skeleton.svelte';
	import ListChecksIcon from '@lucide/svelte/icons/list-checks';
	import PlusIcon from '@lucide/svelte/icons/plus';
	import TriangleAlertIcon from '@lucide/svelte/icons/triangle-alert';

	let workflows = $state<Workflow[]>([]);
	let loading = $state(true);
	let loadError = $state(false);
	let creating = $state(false);
	let busy = $state(false);
	let title = $state('');
	let stepsText = $state('');
	let titleInput = $state<HTMLInputElement | null>(null);

	function sync(updated: Workflow): void {
		workflows = workflows.map((w) => (w.id === updated.id ? updated : w));
	}

	function remove(id: string): void {
		workflows = workflows.filter((w) => w.id !== id);
	}

	async function load(): Promise<void> {
		loading = true;
		loadError = false;
		try {
			workflows = await api.workflows();
		} catch (e) {
			loadError = true;
			toast.error(`Workflows konnten nicht geladen werden: ${errMsg(e)}`);
		} finally {
			loading = false;
		}
	}

	async function create(): Promise<void> {
		const t = title.trim();
		const steps = stepsText
			.split('\n')
			.map((s) => s.trim())
			.filter(Boolean);
		if (!t) {
			toast.error('Bitte einen Titel angeben.');
			return;
		}
		busy = true;
		try {
			const wf = await api.createWorkflow({ title: t, steps });
			workflows = [...workflows, wf];
			title = '';
			stepsText = '';
			creating = false;
			toast.success('Workflow erstellt.');
		} catch (e) {
			toast.error(errMsg(e));
		} finally {
			busy = false;
		}
	}

	/** Öffnet das Anlege-Formular (z. B. aus dem Empty State) und holt das Titelfeld in den Fokus. */
	function startCreate(): void {
		creating = true;
		void tick().then(() => {
			titleInput?.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
			titleInput?.focus();
		});
	}

	onMount(load);
</script>

<section class="mt-8">
	<div class="mb-4 flex items-center justify-between gap-3">
		<h2 class="flex items-center gap-2 text-base font-semibold">
			<ListChecksIcon class="size-4 text-muted-foreground" />
			Workflows
		</h2>
		<Button
			variant={creating ? 'ghost' : 'outline'}
			size="sm"
			disabled={loading}
			onclick={() => (creating = !creating)}
		>
			{#if creating}
				<span>abbrechen</span>
			{:else}
				<PlusIcon class="size-4" />
				<span>Neuer Workflow</span>
			{/if}
		</Button>
	</div>

	{#if creating}
		<div class="mb-5 space-y-3 rounded-xl border border-border bg-card p-4">
			<div class="space-y-1.5">
				<Label for="wf-title">Titel</Label>
				<Input
					id="wf-title"
					bind:ref={titleInput}
					bind:value={title}
					placeholder="z. B. Projektabschluss – Woche 12"
					maxlength={120}
				/>
			</div>
			<div class="space-y-1.5">
				<Label for="wf-steps">Schritte (einer pro Zeile)</Label>
				<Textarea
					id="wf-steps"
					bind:value={stepsText}
					placeholder={'Kundenpräsentation finalisieren\nProtokoll versenden\nRückmeldung einholen'}
				/>
			</div>
			<div class="flex justify-end">
				<Button onclick={create} disabled={busy || !title.trim()}>
					{#if busy}
						<Spinner class="size-4" />
					{:else}
						<PlusIcon class="size-4" />
					{/if}
					<span>{busy ? 'Wird erstellt …' : 'Workflow erstellen'}</span>
				</Button>
			</div>
		</div>
	{/if}

	{#if loading}
		<div class="space-y-4" aria-hidden="true">
			{#each [1, 2, 3] as i (i)}
				<div class="space-y-3 rounded-xl border border-border bg-card p-4">
					<Skeleton class="h-4 w-40" />
					<Skeleton class="h-1.5 w-full" />
					<Skeleton class="h-3 w-full" />
					<Skeleton class="h-3 w-4/5" />
					<Skeleton class="h-3 w-2/3" />
				</div>
			{/each}
		</div>
	{:else if loadError}
		<div
			class="flex flex-col gap-3 rounded-xl border border-destructive/40 bg-destructive/5 p-4 sm:flex-row sm:items-center sm:justify-between"
		>
			<div class="flex items-start gap-3 text-destructive">
				<TriangleAlertIcon class="mt-0.5 size-4 shrink-0" />
				<p class="text-sm leading-relaxed">Workflows konnten nicht geladen werden.</p>
			</div>
			<Button variant="outline" size="sm" class="shrink-0" onclick={load}>Erneut versuchen</Button>
		</div>
	{:else if workflows.length === 0}
		<div class="rounded-xl border border-dashed border-border p-8 text-center text-sm text-muted-foreground">
			<p>Noch keine Workflows vorhanden.</p>
			<Button variant="outline" size="sm" class="mt-4" onclick={startCreate}>
				<PlusIcon class="size-4" />
				<span>Workflow anlegen</span>
			</Button>
		</div>
	{:else}
		<div class="space-y-4">
			{#each workflows as wf (wf.id)}
				<WorkflowCard {wf} {sync} {remove} />
			{/each}
		</div>
	{/if}
</section>
