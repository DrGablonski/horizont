<script lang="ts">
	import { onMount } from 'svelte';
	import { api } from '$lib/api';
	import type { Workflow } from '$lib/types';
	import { toast } from 'svelte-sonner';
	import WorkflowCard from './WorkflowCard.svelte';
	import Button from '$lib/components/ui/button/button.svelte';
	import Input from '$lib/components/ui/input/input.svelte';
	import Label from '$lib/components/ui/label/label.svelte';
	import Textarea from '$lib/components/ui/textarea/textarea.svelte';
	import Spinner from '$lib/components/ui/spinner/spinner.svelte';
	import ListChecksIcon from '@lucide/svelte/icons/list-checks';
	import PlusIcon from '@lucide/svelte/icons/plus';

	let workflows = $state<Workflow[]>([]);
	let loading = $state(true);
	let creating = $state(false);
	let busy = $state(false);
	let title = $state('');
	let stepsText = $state('');

	function errMsg(e: unknown): string {
		return e instanceof Error ? e.message : String(e);
	}

	function sync(updated: Workflow): void {
		workflows = workflows.map((w) => (w.id === updated.id ? updated : w));
	}

	function remove(id: string): void {
		workflows = workflows.filter((w) => w.id !== id);
	}

	async function load(): Promise<void> {
		loading = true;
		try {
			workflows = await api.workflows();
		} catch (e) {
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
		<div class="flex items-center justify-center gap-2 rounded-xl border border-dashed border-border p-8 text-sm text-muted-foreground">
			<Spinner class="size-4" />
			<span>Workflows werden geladen …</span>
		</div>
	{:else if workflows.length === 0}
		<div class="rounded-xl border border-dashed border-border p-8 text-center text-sm text-muted-foreground">
			<p>Noch keine Workflows vorhanden.</p>
			<p class="mt-1 text-xs">
				Lege oben einen Workflow an, um Aufgaben sequenziell abzuarbeiten.
			</p>
		</div>
	{:else}
		<div class="space-y-4">
			{#each workflows as wf (wf.id)}
				<WorkflowCard {wf} {sync} {remove} />
			{/each}
		</div>
	{/if}
</section>
