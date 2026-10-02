<script lang="ts">
	import Modal from './Modal.svelte';
	import Button from './ui/button/button.svelte';
	import Input from './ui/input/input.svelte';
	import Textarea from './ui/textarea/textarea.svelte';
	import Label from './ui/label/label.svelte';
	import Checkbox from './ui/checkbox/checkbox.svelte';
	import { msToLocalInput, localInputToMs, msToDateInput, dateInputToMs } from '$lib/dates';
	import type { EventCreateInput, EventUpdateInput, CalDavCalendar } from '$lib/types';
	import { toast } from 'svelte-sonner';

	export let mode: 'create' | 'edit' = 'create';
	export let open = false;
	export let onClose = () => {};
	export let calendars: CalDavCalendar[] = [];
	export let initial: Partial<EventUpdateInput> & { calendarId?: string; uid?: string } = {};
	export let onSubmit: (input: EventCreateInput | EventUpdateInput) => Promise<void> = async () => {};

	let summary = initial.summary ?? '';
	let location = initial.location ?? '';
	let description = initial.description ?? '';
	let allDay = initial.allDay ?? false;
	let dayKey = initial.dayKey ?? '';
	let endDateKey = initial.endDateKey ?? '';
	let dateTimeStr = '';
	let calendarId = initial.calendarId ?? (calendars[0]?.id ?? '');
	let saving = false;

	if (!allDay && initial.startMs != null) {
		dateTimeStr = msToLocalInput(initial.startMs);
	} else if (allDay && initial.dayKey) {
		dayKey = initial.dayKey;
		endDateKey = initial.endDateKey ?? initial.dayKey;
	}

	if (!allDay && !dateTimeStr) {
		// Default: heute 09:00
		const now = new Date();
		const d = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 9, 0);
		dateTimeStr = msToLocalInput(d.getTime());
	}

	if (!dayKey) {
		const now = new Date();
		const p = (n: number) => String(n).padStart(2, '0');
		dayKey = `${now.getFullYear()}-${p(now.getMonth() + 1)}-${p(now.getDate())}`;
		endDateKey = dayKey;
	}

	async function handleSubmit() {
		if (!summary.trim()) {
			toast.error('Titel darf nicht leer sein.');
			return;
		}
		if (allDay) {
			if (!dayKey) {
				toast.error('Bitte Startdatum wählen.');
				return;
			}
			if (endDateKey && endDateKey < dayKey) {
				toast.error('Enddatum muss nach dem Startdatum liegen.');
				return;
			}
		} else {
			try {
				const startMs = localInputToMs(dateTimeStr);
			} catch {
				toast.error('Bitte gültiges Datum/Zeit wählen.');
				return;
			}
		}

		saving = true;
		try {
			if (allDay) {
				const input: EventUpdateInput & { calendarId?: string } = {
					summary: summary.trim(),
					location: location.trim() || undefined,
					description: description.trim() || undefined,
					allDay: true,
					dayKey,
					endDateKey: endDateKey !== dayKey ? endDateKey : undefined
				};
				if (mode === 'create') {
					await onSubmit({ ...input, calendarId } as EventCreateInput);
				} else {
					await onSubmit(input);
				}
			} else {
				const startMs = localInputToMs(dateTimeStr);
				const endMs = startMs + 30 * 60 * 1000; // default 30 min
				const input: EventUpdateInput & { calendarId?: string } = {
					summary: summary.trim(),
					location: location.trim() || undefined,
					description: description.trim() || undefined,
					allDay: false,
					startMs,
					endMs
				};
				if (mode === 'create') {
					await onSubmit({ ...input, calendarId } as EventCreateInput);
				} else {
					await onSubmit(input);
				}
			}
			onClose();
		} catch (e: any) {
			toast.error(e.message ?? 'Speichern fehlgeschlagen.');
		} finally {
			saving = false;
		}
	}
</script>

	<Modal title={mode === 'create' ? 'Neues Event' : 'Event bearbeiten'} open={open} onClose={onClose}>
	<form onsubmit={(e) => { e.preventDefault(); handleSubmit(); }} class="space-y-4">
		<div class="space-y-1.5">
			<Label for="ev-summary">Titel *</Label>
			<Input id="ev-summary" bind:value={summary} placeholder="Event-Titel" required />
		</div>

		{#if calendars.length > 1}
			<div class="space-y-1.5">
				<Label for="ev-calendar">Kalender</Label>
				<select class="h-9 w-full rounded-md border border-input bg-background px-3 py-1 text-sm" bind:value={calendarId}>
					{#each calendars as cal}
						<option value={cal.id}>{cal.name}</option>
					{/each}
				</select>
			</div>
		{/if}

		<div class="space-y-1.5">
			<Label for="ev-location">Ort</Label>
			<Input id="ev-location" bind:value={location} placeholder="Optional" />
		</div>

		<div class="space-y-3 rounded-md border p-3">
			<div class="flex items-center gap-2">
				<Checkbox id="ev-allday" bind:checked={allDay} />
				<Label for="ev-allday" class="cursor-pointer">Ganztägig</Label>
			</div>

			{#if allDay}
				<div class="grid grid-cols-2 gap-3">
					<div class="space-y-1.5">
						<Label for="ev-start-date">Startdatum</Label>
						<Input id="ev-start-date" type="date" bind:value={dayKey} />
					</div>
					<div class="space-y-1.5">
						<Label for="ev-end-date">Enddatum</Label>
						<Input id="ev-end-date" type="date" bind:value={endDateKey} />
					</div>
				</div>
			{:else}
				<div class="space-y-1.5">
					<Label for="ev-datetime">Datum & Zeit</Label>
					<Input id="ev-datetime" type="datetime-local" bind:value={dateTimeStr} />
				</div>
			{/if}
		</div>

		<div class="space-y-1.5">
			<Label for="ev-desc">Beschreibung</Label>
			<Textarea id="ev-desc" bind:value={description} rows={3} placeholder="Optional" />
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
