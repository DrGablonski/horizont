<script lang="ts">
	import Modal from './Modal.svelte';
	import Button from './ui/button/button.svelte';
	import Input from './ui/input/input.svelte';
	import Textarea from './ui/textarea/textarea.svelte';
	import Label from './ui/label/label.svelte';
	import Checkbox from './ui/checkbox/checkbox.svelte';
	import { localInputToMs, msToTimeInput, dayKey as dayKeyOf } from '$lib/dates';
	import type { EventCreateInput, EventUpdateInput, CalDavCalendar } from '$lib/types';
	import { toast } from 'svelte-sonner';

	export let mode: 'create' | 'edit' = 'create';
	export let open = false;
	export let onClose = () => {};
	export let calendars: CalDavCalendar[] = [];
	export let initial: Partial<EventUpdateInput> & { calendarId?: string; uid?: string } = {};
	export let onSubmit: (input: EventCreateInput | EventUpdateInput) => Promise<void> = async () => {};

	const p2 = (n: number) => String(n).padStart(2, '0');
	const now = new Date();
	const today = `${now.getFullYear()}-${p2(now.getMonth() + 1)}-${p2(now.getDate())}`;
	const DEFAULT_DURATION_MS = 30 * 60 * 1000;

	let summary = initial.summary ?? '';
	let location = initial.location ?? '';
	let description = initial.description ?? '';
	let allDay = initial.allDay ?? false;
	let dayKey = initial.dayKey ?? today; // Ganztägig: das Datum
	let startDay = initial.dayKey ?? today; // Uhrzeit-Termin: Start
	let startTime = '09:00';
	let endDay = initial.dayKey ?? today; // Uhrzeit-Termin: Ende
	let endTime = '09:30';
	let endTouched = false;
	let calendarId = initial.calendarId ?? (calendars[0]?.id ?? '');
	let saving = false;

	if (initial.startMs != null) {
		startDay = dayKeyOf(initial.startMs);
		startTime = msToTimeInput(initial.startMs);
		if (initial.endMs != null) {
			endDay = dayKeyOf(initial.endMs);
			endTime = msToTimeInput(initial.endMs);
			endTouched = true;
		}
	}

	/** Ende automatisch 30 min nach Start, solange der User es nicht selbst geändert hat. */
	function syncEnd() {
		if (endTouched || !startDay || !startTime) return;
		try {
			const ms = localInputToMs(`${startDay}T${startTime}`) + DEFAULT_DURATION_MS;
			endDay = dayKeyOf(ms);
			endTime = msToTimeInput(ms);
		} catch {
			// ungültiger Start – nichts zu synchronisieren
		}
	}

	function onStartInput() {
		syncEnd();
	}

	function onEndInput() {
		endTouched = true;
	}

	function onAllDayToggle() {
		if (allDay) {
			dayKey = startDay; // beim Umschalten das Startdatum behalten
		} else {
			startDay = dayKey;
			syncEnd();
		}
	}

	async function handleSubmit() {
		if (!summary.trim()) {
			toast.error('Titel darf nicht leer sein.');
			return;
		}
		let startMs: number | undefined;
		let endMs: number | undefined;
		if (allDay) {
			if (!dayKey) {
				toast.error('Bitte Datum wählen.');
				return;
			}
		} else {
			if (!startDay || !startTime || !endDay || !endTime) {
				toast.error('Bitte Start- und Endzeit wählen.');
				return;
			}
			try {
				startMs = localInputToMs(`${startDay}T${startTime}`);
				endMs = localInputToMs(`${endDay}T${endTime}`);
			} catch {
				toast.error('Bitte gültiges Datum/Zeit wählen.');
				return;
			}
			if (endMs <= startMs) {
				toast.error('Das Ende muss nach dem Start liegen.');
				return;
			}
		}

		saving = true;
		try {
			const input: EventUpdateInput & { calendarId?: string } = {
				summary: summary.trim(),
				location: location.trim() || undefined,
				description: description.trim() || undefined,
				allDay,
				dayKey: allDay ? dayKey : undefined,
				startMs: allDay ? undefined : startMs,
				endMs: allDay ? undefined : endMs
			};
			if (mode === 'create') {
				await onSubmit({ ...input, calendarId } as EventCreateInput);
			} else {
				await onSubmit(input);
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
				<Checkbox id="ev-allday" bind:checked={allDay} onchange={onAllDayToggle} />
				<Label for="ev-allday" class="cursor-pointer">Ganztägig</Label>
			</div>

			{#if allDay}
				<div class="space-y-1.5">
					<Label for="ev-start-date">Datum</Label>
					<Input id="ev-start-date" type="date" bind:value={dayKey} />
				</div>
			{:else}
				<div class="grid grid-cols-2 gap-3">
					<div class="space-y-1.5">
						<Label for="ev-start-date">Startdatum</Label>
						<Input id="ev-start-date" type="date" bind:value={startDay} onchange={onStartInput} />
					</div>
					<div class="space-y-1.5">
						<Label for="ev-start-time">Startzeit</Label>
						<Input id="ev-start-time" type="time" bind:value={startTime} onchange={onStartInput} />
					</div>
					<div class="space-y-1.5">
						<Label for="ev-end-date">Enddatum</Label>
						<Input id="ev-end-date" type="date" bind:value={endDay} onchange={onEndInput} />
					</div>
					<div class="space-y-1.5">
						<Label for="ev-end-time">Endzeit</Label>
						<Input id="ev-end-time" type="time" bind:value={endTime} onchange={onEndInput} />
					</div>
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
