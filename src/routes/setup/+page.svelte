<script lang="ts">
	import { goto } from '$app/navigation';
	import Button from '$lib/components/ui/button/button.svelte';
	import Input from '$lib/components/ui/input/input.svelte';
	import Label from '$lib/components/ui/label/label.svelte';
	import Spinner from '$lib/components/ui/spinner/spinner.svelte';
	import { api } from '$lib/api';
	import HorizontMark from '$lib/components/HorizontMark.svelte';
	import ShieldIcon from '@lucide/svelte/icons/shield-check';
	import CheckCircleIcon from '@lucide/svelte/icons/check-circle';

	let username = $state('');
	let password = $state('');
	let confirm = $state('');
	let busy = $state(false);
	let error = $state<string | null>(null);

	// Nach erfolgreichem Setup: Erfolgsanzeige.
	let setupDone = $state(false);
	let userName = $state('');

	async function enterApp(): Promise<void> {
		await goto('/', { invalidateAll: true });
	}

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
			const r = await api.setup({ username: username.trim(), password });
			userName = r.user.username;
			setupDone = true;
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

	<div class="mx-auto flex min-h-[70vh] w-full max-w-md flex-col justify-center">
		{#if !setupDone}
		<div class="mb-6 flex flex-col items-center gap-3 text-center">
		<HorizontMark size={72} />
		<h1 class="text-2xl font-bold tracking-tight">Ersteinrichtung</h1>
		<p class="text-sm text-muted-foreground">
			Lege deinen Benutzer an. Damit wird Horizont freigeschaltet.
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
				placeholder="gabriel"
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
				<span>Benutzer anlegen</span>
			{/if}
		</Button>
	</form>
		{:else}
		<div class="mb-6 flex flex-col items-center gap-2 text-center">
			<CheckCircleIcon class="size-8 text-emerald-500" />
			<h1 class="text-xl font-semibold tracking-tight">Setup abgeschlossen</h1>
			<p class="text-sm text-muted-foreground">
				Benutzer „{userName}" ist angelegt und angemeldet.
			</p>
		</div>

		<p class="rounded-md bg-muted px-3 py-2 text-xs text-muted-foreground">
			Verbinde jetzt unter „Einstellungen" deinen Kalender (CalDAV) – oder starte
			direkt mit lokalen Terminen und Aufgaben.
		</p>

		<Button class="mt-4 w-full" onclick={enterApp}>
			<ShieldIcon class="size-4" />
			<span>Weiter zur App</span>
		</Button>
		{/if}
	</div>
