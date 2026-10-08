<script lang="ts">
	import Modal from './Modal.svelte';
	import Button from './ui/button/button.svelte';
	import Input from './ui/input/input.svelte';
	import Textarea from './ui/textarea/textarea.svelte';
	import Label from './ui/label/label.svelte';
	import Checkbox from './ui/checkbox/checkbox.svelte';
	import { localInputToMs, msToDateInput, msToTimeInput } from '$lib/dates';
	import type { TaskCreateInput, TaskUpdateInput, TaskItem, CalDavCalendar, TaskDueInput } from '$lib/types';
	import { toast } from 'svelte-sonner';

	export let mode: 'create' | 'edit' = 'create';
	export let open = false;
	export let onClose = () => {};
	export let calendars: CalDavCalendar[] = [];
	export let initial: Partial<TaskUpdateInput> & { calendarId?: string; uid?: string } = {};
	export let onSubmit: (input: TaskCreateInput | TaskUpdateInput) => Promise<void> = async () => {};

	let summary = initial.summary ?? '';
	let description = initial.description ?? '';
	let completed = initial.completed ?? false;
	let calendarId = initial.calendarId ?? (calendars[0]?.id ?? '');
	let saving = false;

	let dueKind: 'none' | 'date' | 'time' = 'none';
	let dueDate = '';
	let dueTime = '09:00';

	// Initial state für Edit
	if (initial.due != null) {
		if (initial.due.kind === 'date') {
			dueKind = 'date';
			dueDate = initial.due.key;
		} else if (initial.due.kind === 'time') {
			dueKind = 'time';
			dueDate = msToDateInput(initial.due.ms);
			dueTime = msToTimeInput(initial.due.ms);
		}
	}

	let priority: string = initial.priority != null ? String(initial.priority) : '';

	async function handleSubmit() {
		if (!summary.trim()) {
			toast.error('Aufgabentitel darf nicht leer sein.');
			return;
		}

		saving = true;
		try {
			let due: TaskDueInput | undefined;
			if (dueKind === 'date') {
				if (!dueDate) {
					toast.error('Bitte Datum wählen.');
					saving = false;
					return;
				}
				due = { kind: 'date', key: dueDate };
			} else if (dueKind === 'time') {
				if (!dueDate || !dueTime) {
					toast.error('Bitte Datum und Uhrzeit wählen.');
					saving = false;
					return;
				}
				try {
					const ms = localInputToMs(`${dueDate}T${dueTime}`);
					due = { kind: 'time', ms };
				} catch {
					toast.error('Bitte gültiges Datum/Zeit wählen.');
					saving = false;
					return;
				}
			} else {
				due = { kind: 'none' };
			}

			let pri: number | null | undefined;
			if (priority) {
				pri = Number(priority);
			} else if (mode === 'edit') {
				pri = null; // remove
			}

			const base = {
				summary: summary.trim(),
				description: description.trim() || undefined,
				completed,
				due,
				priority: pri
			};

			if (mode === 'create') {
				await onSubmit({ ...base, calendarId } as TaskCreateInput);
			} else {
				await onSubmit(base as TaskUpdateInput);
			}
			onClose();
		} catch (e: any) {
			toast.error(e.message ?? 'Speichern fehlgeschlagen.');
		} finally {
			saving = false;
		}
	}
</script>

	<Modal title={mode === 'create' ? 'Neue Aufgabe' : 'Aufgabe bearbeiten'} open={open} onClose={onClose}>
	<form onsubmit={(e) => { e.preventDefault(); handleSubmit(); }} class="space-y-4">
		<div class="space-y-1.5">
			<Label for="task-summary">Titel *</Label>
			<Input id="task-summary" bind:value={summary} placeholder="Aufgabentitel" required />
		</div>

		{#if calendars.length > 1}
			<div class="space-y-1.5">
				<Label for="task-calendar">Kalender</Label>
				<select class="h-9 w-full rounded-md border border-input bg-background px-3 py-1 text-sm" bind:value={calendarId}>
					{#each calendars as cal}
						<option value={cal.id}>{cal.name}</option>
					{/each}
				</select>
			</div>
		{/if}

		<div class="space-y-3 rounded-md border p-3">
			<div class="flex items-center gap-2">
				<Checkbox id="task-completed" bind:checked={completed} />
				<Label for="task-completed" class="cursor-pointer">Erledigt</Label>
			</div>

			<div class="space-y-1.5">
				<Label>Fällig</Label>
				<div class="flex items-center gap-2">
					<label class="flex items-center gap-1 text-sm cursor-pointer">
						<input type="radio" value="none" bind:group={dueKind} class="accent-primary" />
						Keine
					</label>
					<label class="flex items-center gap-1 text-sm cursor-pointer">
						<input type="radio" value="date" bind:group={dueKind} class="accent-primary" />
						Datum
					</label>
					<label class="flex items-center gap-1 text-sm cursor-pointer">
						<input type="radio" value="time" bind:group={dueKind} class="accent-primary" />
						Datum & Zeit
					</label>
				</div>
				{#if dueKind === 'date'}
					<Input type="date" bind:value={dueDate} class="mt-2" />
				{:else if dueKind === 'time'}
					<div class="mt-2 grid grid-cols-2 gap-2">
						<Input type="date" bind:value={dueDate} />
						<Input type="time" bind:value={dueTime} />
					</div>
				{/if}
			</div>

			<div class="space-y-1.5">
				<Label for="task-priority">Priorität</Label>
				<select id="task-priority" class="h-9 w-full rounded-md border border-input bg-background px-3 py-1 text-sm" bind:value={priority}>
					<option value="">Keine</option>
					<option value="1">Hoch</option>
					<option value="5">Normal</option>
					<option value="9">Niedrig</option>
				</select>
			</div>
		</div>

		<div class="space-y-1.5">
			<Label for="task-desc">Beschreibung</Label>
			<Textarea id="task-desc" bind:value={description} rows={3} placeholder="Optional" />
		</div>

		<div class="flex justify-end gap-2 pt-2">
			<Button variant="outline" type="button" onclick={onClose}>Abbrechen</Button>
			<Button type="submit" disabled={saving}>
				{#if saving}
					<span class="h-4 w-4 animate-spin rounded-full border-2 border-current border-t-transparent"></span>
				{/if}
				{mode === 'create' ? 'Erstellen' : 'Speichern'}
			</Button>
		</div>
	</form>
</Modal>
