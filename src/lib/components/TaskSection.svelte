<script lang="ts">
	import { onMount } from 'svelte';
	import { api } from '$lib/api';
	import type { TaskItem, CalDavCalendar, TaskCreateInput, TaskUpdateInput } from '$lib/types';
	import Button from './ui/button/button.svelte';
	import Checkbox from './ui/checkbox/checkbox.svelte';
	import Badge from './ui/badge/badge.svelte';
	import Spinner from './ui/spinner/spinner.svelte';
	import TaskEditor from './TaskEditor.svelte';
	import { toast } from 'svelte-sonner';

	export let onTasksChange: () => void = () => {};

	let tasks: TaskItem[] = [];
	let calendars: CalDavCalendar[] = [];
	let loading = true;
	let editorOpen = false;
	let editorMode: 'create' | 'edit' = 'create';
	let editorInitial: Partial<TaskUpdateInput> & { calendarId?: string; uid?: string } = {};

	async function load() {
		loading = true;
		try {
			const [tasksRes, calRes] = await Promise.all([api.tasks(), api.calendars()]);
			tasks = tasksRes.tasks;
			calendars = calRes.calendars;
		} catch (e: any) {
			toast.error(e.message ?? 'Aufgaben konnten nicht geladen werden.');
		} finally {
			loading = false;
		}
	}

	onMount(load);

	function openCreate() {
		editorMode = 'create';
		editorInitial = { calendarId: calendars[0]?.id ?? '' };
		editorOpen = true;
	}

	function openEdit(task: TaskItem) {
		editorMode = 'edit';
		editorInitial = {
			uid: task.uid,
			summary: task.summary,
			description: task.description,
			completed: task.completed,
			due: task.dueKey
				? { kind: 'date' as const, key: task.dueKey }
				: task.dueMs != null
					? { kind: 'time' as const, ms: task.dueMs }
					: { kind: 'none' as const },
			priority: task.priority ?? null,
			calendarId: task.calendarId
		};
		editorOpen = true;
	}

	async function handleEditorSubmit(input: TaskCreateInput | TaskUpdateInput) {
		try {
			if (editorMode === 'create') {
				await api.createTask(input as TaskCreateInput);
				toast.success('Aufgabe erstellt.');
			} else {
				const task = tasks.find((t) => t.uid === (editorInitial as any).uid);
				if (task) {
					await api.updateTask(task.calendarId, task.uid, input as TaskUpdateInput);
					toast.success('Aufgabe aktualisiert.');
				}
			}
			await load();
			onTasksChange();
		} catch (e: any) {
			toast.error(e.message ?? 'Speichern fehlgeschlagen.');
		}
	}

	async function toggleComplete(task: TaskItem) {
		try {
			await api.updateTask(task.calendarId, task.uid, { completed: !task.completed });
			tasks = tasks.map((t) => (t.uid === task.uid ? { ...t, completed: !task.completed } : t));
		} catch (e: any) {
			toast.error(e.message ?? 'Fehler beim Aktualisieren.');
		}
	}

	async function handleDelete(task: TaskItem) {
		if (!confirm(`Aufgabe "${task.summary}" wirklich löschen?`)) return;
		try {
			await api.deleteTask(task.calendarId, task.uid);
			tasks = tasks.filter((t) => t.uid !== task.uid);
			toast.success('Aufgabe gelöscht.');
			onTasksChange();
		} catch (e: any) {
			toast.error(e.message ?? 'Löschen fehlgeschlagen.');
		}
	}

	function priorityLabel(p: number | undefined): string {
		if (p == null) return '';
		if (p <= 2) return 'Hoch';
		if (p <= 5) return 'Normal';
		return 'Niedrig';
	}

	function dueDisplay(t: TaskItem): string {
		if (t.dueKey) return t.dueKey;
		if (t.dueMs != null) {
			const d = new Date(t.dueMs);
			const p = (n: number) => String(n).padStart(2, '0');
			return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}`;
		}
		return '';
	}
</script>

<div class="space-y-3">
	<div class="flex items-center justify-between">
		<h3 class="text-sm font-semibold text-foreground">Aufgaben</h3>
		<Button variant="outline" size="sm" onclick={openCreate}>
			<span class="mr-1">+</span> Neue Aufgabe
		</Button>
	</div>

	{#if loading}
		<div class="flex items-center justify-center py-8">
			<Spinner class="h-6 w-6" />
		</div>
	{:else if tasks.length === 0}
		<p class="py-4 text-center text-sm text-muted-foreground">Keine Aufgaben vorhanden.</p>
	{:else}
		<ul class="space-y-1">
			{#each tasks as task (task.uid)}
				<li
					class="group flex items-center gap-2 rounded-md border p-2 text-sm hover:bg-muted/50 transition-colors"
				>
					<Checkbox
						checked={task.completed}
						onchange={() => toggleComplete(task)}
						class="shrink-0"
					/>
					<button
						class="flex-1 text-left truncate cursor-pointer hover:underline {task.completed
							? 'line-through text-muted-foreground'
							: ''}"
						onclick={() => openEdit(task)}
					>
						{task.summary}
					</button>
					{#if task.priority != null}
						<Badge class="shrink-0 text-xs" variant="secondary">
							{priorityLabel(task.priority)}
						</Badge>
					{/if}
					{#if dueDisplay(task)}
						<span class="shrink-0 text-xs text-muted-foreground">{dueDisplay(task)}</span>
					{/if}
					<button
						class="shrink-0 rounded p-1 text-muted-foreground hover:text-destructive hover:bg-destructive/10 opacity-0 group-hover:opacity-100 transition-opacity"
						onclick={() => handleDelete(task)}
						title="Löschen"
					>
						<svg class="h-3.5 w-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
							<path d="M3 6h18M8 6V4a2 2 0 012-2h4a2 2 0 012 2v2m3 0v14a2 2 0 01-2 2H7a2 2 0 01-2-2V6h14" />
						</svg>
					</button>
				</li>
			{/each}
		</ul>
	{/if}
</div>

{#if editorOpen}
	<TaskEditor
		mode={editorMode}
		open={editorOpen}
		calendars={calendars}
		initial={editorInitial}
		onSubmit={handleEditorSubmit}
		onClose={() => (editorOpen = false)}
	/>
{/if}
