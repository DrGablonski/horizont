<script lang="ts">
	import { goto } from '$app/navigation';
	import Button from '$lib/components/ui/button/button.svelte';
	import Input from '$lib/components/ui/input/input.svelte';
	import Label from '$lib/components/ui/label/label.svelte';
	import Spinner from '$lib/components/ui/spinner/spinner.svelte';
	import { api } from '$lib/api';
	import { toast } from 'svelte-sonner';
	import HorizontMark from '$lib/components/HorizontMark.svelte';
	import LogInIcon from '@lucide/svelte/icons/log-in';

	let username = $state('');
	let password = $state('');
	let busy = $state(false);
	let error = $state<string | null>(null);

	async function submit(e: SubmitEvent): Promise<void> {
		e.preventDefault();
		if (busy) return;
		busy = true;
		error = null;
		try {
			await api.login({ username: username.trim(), password });
			await goto('/', { invalidateAll: true });
		} catch (e) {
			error = e instanceof Error ? e.message : String(e);
		} finally {
			busy = false;
		}
	}
</script>

<svelte:head>
	<title>Anmelden · Horizont</title>
</svelte:head>

<div class="mx-auto flex min-h-[70vh] w-full max-w-sm flex-col justify-center">
	<div class="mb-6 flex flex-col items-center gap-3">
		<HorizontMark size={72} />
		<h1 class="text-2xl font-bold tracking-tight">Horizont</h1>
		<p class="text-sm text-muted-foreground">Melde dich an, um fortzufahren.</p>
	</div>

	<form
		class="space-y-4 rounded-xl border border-border bg-card p-5"
		onsubmit={submit}
		novalidate
	>
		<div class="space-y-1.5">
			<Label for="login-user">Benutzername</Label>
			<Input
				id="login-user"
				bind:value={username}
				autocomplete="username"
				autofocus
				required
			/>
		</div>

		<div class="space-y-1.5">
			<Label for="login-pass">Passwort</Label>
			<Input
				id="login-pass"
				bind:value={password}
				type="password"
				autocomplete="current-password"
				required
			/>
		</div>

		{#if error}
			<p class="rounded-md bg-destructive/10 px-3 py-2 text-sm text-destructive">{error}</p>
		{/if}

		<Button type="submit" class="w-full" disabled={busy || !username.trim() || !password}>
			{#if busy}
				<Spinner class="size-4" />
				<span>Wird angemeldet …</span>
			{:else}
				<LogInIcon class="size-4" />
				<span>Anmelden</span>
			{/if}
		</Button>
	</form>
</div>
