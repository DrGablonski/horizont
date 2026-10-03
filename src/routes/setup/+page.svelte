<script lang="ts">
	import { goto } from '$app/navigation';
	import Button from '$lib/components/ui/button/button.svelte';
	import Input from '$lib/components/ui/input/input.svelte';
	import Label from '$lib/components/ui/label/label.svelte';
	import Spinner from '$lib/components/ui/spinner/spinner.svelte';
	import { api } from '$lib/api';
	import CalendarIcon from '@lucide/svelte/icons/calendar';
	import ShieldIcon from '@lucide/svelte/icons/shield-check';

	let username = $state('');
	let password = $state('');
	let confirm = $state('');
	let busy = $state(false);
	let error = $state<string | null>(null);

	function validate(): string | null {
		if (!username.trim()) return 'Bitte einen Benutzernamen angeben.';
		if (password.length < 8) return 'Das Passwort muss mindestens 8 Zeichen haben.';
		if (password !== confirm) return 'Die Passwörter stimmen nicht überein.';
		return null;
	}

	async function submit(e: SubmitEvent): Promise<void> {
		e.preventDefault();
		if (busy) return;
		const v = validate();
		if (v) {
			error = v;
			return;
		}
		busy = true;
		error = null;
		try {
			await api.setup({ username: username.trim(), password });
			await goto('/', { invalidateAll: true });
		} catch (e) {
			error = e instanceof Error ? e.message : String(e);
		} finally {
			busy = false;
		}
	}
</script>

<svelte:head>
	<title>Ersteinrichtung · Horizont</title>
</svelte:head>

<div class="mx-auto flex min-h-[70vh] w-full max-w-sm flex-col justify-center">
	<div class="mb-6 flex flex-col items-center gap-2 text-center">
		<CalendarIcon class="size-8" />
		<h1 class="text-xl font-semibold tracking-tight">Ersteinrichtung</h1>
		<p class="text-sm text-muted-foreground">
			Lege den ersten Admin-Account an. Damit wird Horizont freigeschaltet.
		</p>
	</div>

	<form class="space-y-4 rounded-xl border border-border bg-card p-5" onsubmit={submit} novalidate>
		<div class="space-y-1.5">
			<Label for="setup-user">Benutzername</Label>
			<Input
				id="setup-user"
				bind:value={username}
				autocomplete="username"
				autofocus
				placeholder="admin"
				required
			/>
			<p class="text-xs text-muted-foreground">
				2–32 Zeichen: a–z, A–Z, 0–9, Punkt, Unterstrich, Bindestrich.
			</p>
		</div>

		<div class="space-y-1.5">
			<Label for="setup-pass">Passwort</Label>
			<Input
				id="setup-pass"
				bind:value={password}
				type="password"
				autocomplete="new-password"
				required
			/>
			<p class="text-xs text-muted-foreground">Mindestens 8 Zeichen.</p>
		</div>

		<div class="space-y-1.5">
			<Label for="setup-pass2">Passwort bestätigen</Label>
			<Input
				id="setup-pass2"
				bind:value={confirm}
				type="password"
				autocomplete="new-password"
				required
			/>
		</div>

		{#if error}
			<p class="rounded-md bg-destructive/10 px-3 py-2 text-sm text-destructive">{error}</p>
		{/if}

		<Button type="submit" class="w-full" disabled={busy}>
			{#if busy}
				<Spinner class="size-4" />
				<span>Wird eingerichtet …</span>
			{:else}
				<ShieldIcon class="size-4" />
				<span>Account anlegen</span>
			{/if}
		</Button>
	</form>
</div>
