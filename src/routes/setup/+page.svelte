<script lang="ts">
	import { goto } from '$app/navigation';
	import Button from '$lib/components/ui/button/button.svelte';
	import Input from '$lib/components/ui/input/input.svelte';
	import Label from '$lib/components/ui/label/label.svelte';
	import Spinner from '$lib/components/ui/spinner/spinner.svelte';
	import { toast } from 'svelte-sonner';
	import { api } from '$lib/api';
	import CalendarIcon from '@lucide/svelte/icons/calendar';
	import ShieldIcon from '@lucide/svelte/icons/shield-check';
	import ChevronDownIcon from '@lucide/svelte/icons/chevron-down';

	let username = $state('');
	let password = $state('');
	let confirm = $state('');
	let busy = $state(false);
	let error = $state<string | null>(null);

	// Optional: System-CalDAV (Radicale + caldav-admin-Sidecar).
	let showCaldav = $state(false);
	let cBaseUrl = $state('');
	let cAdminApiUrl = $state('');
	let cToken = $state('');

	function validate(): string | null {
		if (!username.trim()) return 'Bitte einen Benutzernamen angeben.';
		if (password.length < 8) return 'Das Passwort muss mindestens 8 Zeichen haben.';
		if (password !== confirm) return 'Die Passwörter stimmen nicht überein.';
		const hasBase = cBaseUrl.trim() !== '';
		const hasApi = cAdminApiUrl.trim() !== '';
		if (hasBase !== hasApi) {
			return 'System-CalDAV: Basis-URL und Admin-API-URL werden zusammen benötigt.';
		}
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
		const cBase = cBaseUrl.trim().replace(/\/+$/, '');
		const cApi = cAdminApiUrl.trim().replace(/\/+$/, '');
		const hasCaldav = cBase !== '' && cApi !== '';
		const input = {
			username: username.trim(),
			password,
			...(hasCaldav
				? {
						caldav: {
							baseUrl: cBase,
							adminApiUrl: cApi,
							...(cToken.trim() ? { adminToken: cToken.trim() } : {})
						}
					}
				: {})
		};
		try {
			const r = await api.setup(input);
			if (r.caldavError) {
				toast.warning(
					`Setup abgeschlossen, aber der CalDAV-Account konnte nicht angelegt werden: ${r.caldavError}`
				);
			} else if (r.caldav) {
				toast.success('System-CalDAV eingerichtet, Admin-CalDAV-Account angelegt.');
			}
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

<div class="mx-auto flex min-h-[70vh] w-full max-w-md flex-col justify-center">
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

		<!-- Optional: System-CalDAV -->
		<div class="rounded-lg border border-border">
			<button
				type="button"
				class="flex w-full items-center justify-between gap-2 px-3 py-2.5 text-sm font-medium"
				aria-expanded={showCaldav}
				onclick={() => (showCaldav = !showCaldav)}
			>
				<span>
					System-CalDAV
					<span class="ml-1 text-xs font-normal text-muted-foreground">(optional)</span>
				</span>
				<span class={'transition-transform' + (showCaldav ? ' rotate-180' : '')}>
					<ChevronDownIcon class="size-4" />
				</span>
			</button>
			{#if showCaldav}
				<div class="space-y-4 border-t border-border p-3">
					<p class="text-xs leading-relaxed text-muted-foreground">
						Optional: Legt jetzt schon den CalDAV-Zielserver (Radicale + caldav-admin-Sidecar) fest.
						Dadurch erhält der Admin direkt einen CalDAV-Account und neue Users automatisch einen.
						Kann später jederzeit auch unter „Admin" nachgeholt werden.
					</p>
					<div class="grid gap-4 sm:grid-cols-2">
						<div class="space-y-1.5">
							<Label for="setup-caldav-base">Basis-URL (Radicale)</Label>
							<Input
								id="setup-caldav-base"
								bind:value={cBaseUrl}
								type="url"
								placeholder="http://192.168.1.135:5232"
							/>
						</div>
						<div class="space-y-1.5">
							<Label for="setup-caldav-api">Admin-API (Sidecar)</Label>
							<Input
								id="setup-caldav-api"
								bind:value={cAdminApiUrl}
								type="url"
								placeholder="http://192.168.1.135:5233"
							/>
						</div>
						<div class="space-y-1.5 sm:col-span-2">
							<Label for="setup-caldav-token">Admin-Token</Label>
							<Input
								id="setup-caldav-token"
								bind:value={cToken}
								type="password"
								placeholder="token"
								autocomplete="off"
							/>
							<p class="text-xs text-muted-foreground">
								Wird auf dem Sidecar in /etc/caldav-admin/admin.env als ADMIN_TOKEN hinterlegt.
							</p>
						</div>
					</div>
				</div>
			{/if}
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
