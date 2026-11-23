<script lang="ts">
	/**
	 * Ersatzt die native confirm()-Abfrage durch einen designten Dialog
	 * (basis auf dem eigenen Modal → Branding und Animationen inklusive).
	 * Aufrufer mounten den Dialog bedingt ({#if ...}) – er ist immer „offen“.
	 */
	import Modal from './Modal.svelte';
	import Button from './ui/button/button.svelte';
	import Spinner from './ui/spinner/spinner.svelte';

	let {
		title,
		message,
		confirmLabel = 'Löschen',
		cancelLabel = 'Abbrechen',
		danger = true,
		onConfirm,
		onClose
	}: {
		title: string;
		message: string;
		confirmLabel?: string;
		cancelLabel?: string;
		/** true = Bestätigungsbutton als Destruktiv-Aktion kennzeichnen. */
		danger?: boolean;
		onConfirm: () => void | Promise<void>;
		onClose: () => void;
	} = $props();

	let busy = $state(false);

	async function handleConfirm(): Promise<void> {
		if (busy) return;
		busy = true;
		try {
			await onConfirm();
		} finally {
			busy = false;
			onClose();
		}
	}
</script>

<Modal title={title} open onClose={busy ? () => {} : onClose}>
	<p class="text-sm leading-relaxed text-muted-foreground">{message}</p>
	<div class="mt-5 flex justify-end gap-2">
		<Button variant="outline" disabled={busy} onclick={onClose}>{cancelLabel}</Button>
		<Button variant={danger ? 'destructive' : 'default'} disabled={busy} onclick={handleConfirm}>
			{#if busy}<Spinner class="size-3.5" />{/if}
			{confirmLabel}
		</Button>
	</div>
</Modal>
