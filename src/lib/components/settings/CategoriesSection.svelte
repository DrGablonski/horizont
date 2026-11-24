<script lang="ts">
	import { onMount } from 'svelte';
	import { api } from '$lib/api';
	import { errMsg } from '$lib/errors';
	import type { TaskCategory } from '$lib/types';
	import { DEFAULT_TASK_CATEGORIES, normalizeCategoryName } from '$lib/categories';
	import { toast } from 'svelte-sonner';
	import Button from '$lib/components/ui/button/button.svelte';
	import Input from '$lib/components/ui/input/input.svelte';
	import Spinner from '$lib/components/ui/spinner/spinner.svelte';
	import ConfirmDialog from '$lib/components/ConfirmDialog.svelte';
	import TagsIcon from '@lucide/svelte/icons/tags';
	import PlusIcon from '@lucide/svelte/icons/plus';
	import TrashIcon from '@lucide/svelte/icons/trash-2';

	/** Nach oben durchgereicht — der Benachrichtigungs-Abschnitt nutzt die Kategorien mit. */
	let { cats = $bindable<TaskCategory[]>([]) } = $props();

	const form = $state({ saving: false, name: '', color: '#2563eb' });

	/** Ausstehender Lösch-Beschluss (Kategoriename) für den Bestätigungsdialog. */
	let pendingDelete = $state<string | null>(null);
	/** Sprungmarken, damit der Empty-State-Button das Eingabeformular fokussiert. */
	let formSection = $state<HTMLDivElement | null>(null);
	let nameInput = $state<HTMLInputElement | null>(null);

	function focusForm(): void {
		formSection?.scrollIntoView({ behavior: 'smooth', block: 'start' });
		// preventScroll: sonst bricht der fokussierte Input den sanften Scroll sofort ab.
		nameInput?.focus({ preventScroll: true });
	}

	async function loadCategories(): Promise<void> {
		try {
			const r = await api.categories();
			cats = r.categories;
		} catch (e) {
			toast.error(errMsg(e));
		}
	}

	async function saveCats(next: TaskCategory[]): Promise<boolean> {
		form.saving = true;
		try {
			const r = await api.saveCategories(next);
			cats = r.categories;
			return true;
		} catch (e) {
			toast.error(errMsg(e));
			return false;
		} finally {
			form.saving = false;
		}
	}

	async function addCategory(): Promise<void> {
		const name = normalizeCategoryName(form.name);
		if (!name) {
			toast.error('Ungültiger Kategoriename (1–40 Zeichen, ohne Komma/Semikolon).');
			return;
		}
		if (cats.some((c) => c.name.toLowerCase() === name.toLowerCase())) {
			toast.error('Diese Kategorie gibt es schon.');
			return;
		}
		if (await saveCats([...cats, { name, color: form.color }])) {
			form.name = '';
			toast.success('Kategorie angelegt.');
		}
	}

	async function renameCategory(oldName: string, newNameRaw: string): Promise<void> {
		const name = normalizeCategoryName(newNameRaw);
		if (!name || name === oldName) return;
		if (cats.some((c) => c.name.toLowerCase() === name.toLowerCase())) {
			toast.error('Diese Kategorie gibt es schon.');
			return;
		}
		if (await saveCats(cats.map((c) => (c.name === oldName ? { ...c, name } : c)))) {
			toast.success('Kategorie umbenannt.');
		}
	}

	async function setCatColor(name: string, color: string): Promise<void> {
		await saveCats(cats.map((c) => (c.name === name ? { ...c, color } : c)));
	}

	function removeCategory(name: string): void {
		pendingDelete = name;
	}

	async function confirmRemoveCategory(): Promise<void> {
		if (!pendingDelete) return;
		const name = pendingDelete;
		if (await saveCats(cats.filter((c) => c.name !== name))) {
			toast.success('Kategorie gelöscht.');
		}
	}

	async function resetCategories(): Promise<void> {
		if (await saveCats(DEFAULT_TASK_CATEGORIES.map((c) => ({ ...c })))) {
			toast.success('Standard-Kategorien wiederhergestellt.');
		}
	}

	onMount(() => {
		loadCategories();
	});
</script>

<div class="rounded-xl border border-border bg-card p-5">
	<div class="flex items-center justify-between gap-3">
		<div>
			<div class="flex items-center gap-2">
				<TagsIcon class="size-4" />
				<span class="text-sm font-medium">Aufgaben-Kategorien</span>
			</div>
			<p class="mt-1 text-xs text-muted-foreground">
				Hier benennst und einfärbst du die Kategorien, die du deinen Aufgaben geben
				kannst — z. B. „Schule", „Privat" oder „Garten". Die Kategorie wird direkt
				in der Aufgabe gespeichert und ist deshalb auch in anderen Kalender-Apps sichtbar.
			</p>
		</div>
		<Button size="sm" variant="ghost" disabled={form.saving} onclick={resetCategories}>
			Standard herstellen
		</Button>
	</div>

	<div class="mt-4 space-y-2">
		{#each cats as c (c.name)}
			<div class="flex items-center gap-2">
				<input
					type="color"
					value={c.color}
					onchange={(e) => setCatColor(c.name, (e.target as HTMLInputElement).value)}
					class="h-8 w-10 cursor-pointer rounded border border-input bg-background p-0.5"
					aria-label={`Farbe für ${c.name}`}
					title="Farbe ändern"
				/>
				<Input
					value={c.name}
					onchange={(e) => renameCategory(c.name, (e.target as HTMLInputElement).value)}
					class="h-8 max-w-56 text-sm"
					maxlength={40}
					aria-label={`Name von ${c.name}`}
				/>
				<Button
					size="sm"
					variant="ghost"
					class="text-muted-foreground hover:text-destructive"
					disabled={form.saving}
					onclick={() => removeCategory(c.name)}
					title="Kategorie löschen"
				>
					<TrashIcon class="size-3.5" />
				</Button>
			</div>
		{:else}
			<div class="flex items-center justify-between gap-3">
				<p class="text-sm text-muted-foreground">Noch keine Kategorien vorhanden.</p>
				<Button size="sm" variant="outline" onclick={focusForm}>
					<PlusIcon class="size-3.5" />
					<span>Kategorie anlegen</span>
				</Button>
			</div>
		{/each}
	</div>

	<div class="mt-4 flex flex-wrap items-center gap-2" bind:this={formSection}>
		<input
			type="color"
			bind:value={form.color}
			class="h-9 w-11 cursor-pointer rounded border border-input bg-background p-0.5"
			aria-label="Farbe der neuen Kategorie"
		/>
		<Input
			bind:value={form.name}
			bind:ref={nameInput}
			placeholder="Neue Kategorie (z. B. Garten)"
			class="h-9 max-w-56 text-sm"
			maxlength={40}
			onkeydown={(e) => e.key === 'Enter' && addCategory()}
		/>
		<Button size="sm" disabled={form.saving || !form.name.trim()} onclick={addCategory}>
			{#if form.saving}<Spinner class="size-3.5" />{:else}<PlusIcon class="size-3.5" />{/if}
			<span>Hinzufügen</span>
		</Button>
	</div>
</div>

{#if pendingDelete}
	<ConfirmDialog
		title="Kategorie löschen"
		message={`Kategorie „${pendingDelete}“ wirklich löschen? Bestehende Aufgaben behalten ihren Kategorienamen (ohne Farbe).`}
		confirmLabel="Löschen"
		onConfirm={confirmRemoveCategory}
		onClose={() => (pendingDelete = null)}
	/>
{/if}
