<script lang="ts">
	import { onMount } from 'svelte';
	import { api } from '$lib/api';
	import { errMsg } from '$lib/errors';
	import type { ApiTokenView } from '$lib/types';
	import { toast } from 'svelte-sonner';
	import Button from '$lib/components/ui/button/button.svelte';
	import Spinner from '$lib/components/ui/spinner/spinner.svelte';
	import ConfirmDialog from '$lib/components/ConfirmDialog.svelte';
	import KeyRoundIcon from '@lucide/svelte/icons/key-round';
	import TrashIcon from '@lucide/svelte/icons/trash-2';

	let apiTokenView = $state<ApiTokenView | null>(null);

	// Erstellungsdatum sicher formatieren: ApiTokenView.createdAt ist number | null
	// (null nur ohne Token) – kein `as number` nötig.
	const tokenCreatedAtLabel = $derived(
		apiTokenView?.hasToken && apiTokenView.createdAt != null
			? new Date(apiTokenView.createdAt).toLocaleDateString('de-DE')
			: null
	);

	const form = $state({ newToken: '', generating: false, revoking: false });

	/** Ausstehender Bestätigungsdialog: Token ersetzen oder ablehnen. */
	let pendingAction = $state<'replace' | 'revoke' | null>(null);

	async function loadApiToken(): Promise<void> {
		try {
			apiTokenView = await api.apiToken();
		} catch (e) {
			toast.error(errMsg(e));
		}
	}

	function createToken(): void {
		if (apiTokenView?.hasToken) {
			pendingAction = 'replace';
			return;
		}
		void generateToken();
	}

	async function generateToken(): Promise<void> {
		form.generating = true;
		try {
			const r = await api.generateApiToken();
			form.newToken = r.token;
			await loadApiToken();
		} catch (e) {
			toast.error(errMsg(e));
		} finally {
			form.generating = false;
		}
	}

	function revokeToken(): void {
		pendingAction = 'revoke';
	}

	async function confirmRevokeToken(): Promise<void> {
		form.revoking = true;
		try {
			await api.revokeApiToken();
			form.newToken = '';
			await loadApiToken();
			toast.success('Token abgelehnt.');
		} catch (e) {
			toast.error(errMsg(e));
		} finally {
			form.revoking = false;
		}
	}

	function copyToken(): void {
		if (!form.newToken) return;
		navigator.clipboard.writeText(form.newToken).then(
			() => toast.success('Token kopiert.'),
			() => toast.error('Kopieren fehlgeschlagen.')
		);
	}

	onMount(() => {
		loadApiToken();
	});
</script>

<div class="rounded-xl border border-border bg-card p-5">
	<div class="flex items-center gap-2">
		<KeyRoundIcon class="size-4" />
		<span class="text-sm font-medium">API-Token (für externe Zugriffe)</span>
	</div>
	<p class="mt-1 text-xs text-muted-foreground">
		Mit diesem Token können externe Programme — z. B. ein Assistenz-/Automatisierungs-
		Tool über den mitgelieferten MCP-Server — auf deine Termine und Aufgaben zugreifen.
		Der Token funktioniert wie ein Passwort (Header <code class="font-mono">Authorization: Bearer &lt;token&gt;</code>).
	</p>

	{#if apiTokenView}
		{#if apiTokenView.hasToken}
			{#if tokenCreatedAtLabel}
				<p class="mt-3 text-xs text-muted-foreground">
					Token erstellt am {tokenCreatedAtLabel}
					{#if apiTokenView.lastUsedAt}
						· zuletzt genutzt {new Date(apiTokenView.lastUsedAt).toLocaleDateString('de-DE')}
					{/if}
				</p>
			{/if}
		{:else}
			<p class="mt-3 text-xs text-muted-foreground">Noch kein Token erstellt.</p>
		{/if}
	{/if}

	{#if form.newToken}
		<div class="mt-3 space-y-2 rounded-lg border border-emerald-500/30 bg-emerald-500/5 p-3">
			<p class="text-xs text-muted-foreground">
				Neuer Token — <strong>wird nur einmal angezeigt</strong>, jetzt kopieren:
			</p>
			<div class="flex gap-2">
				<code class="min-w-0 flex-1 break-all rounded bg-background p-2 font-mono text-xs">{form.newToken}</code>
				<Button size="sm" variant="outline" onclick={copyToken}>Kopieren</Button>
			</div>
		</div>
	{/if}

	<div class="mt-4 flex flex-wrap items-center gap-2">
		<Button size="sm" disabled={form.generating} onclick={createToken}>
			{#if form.generating}<Spinner class="size-3.5" />{:else}<KeyRoundIcon class="size-3.5" />{/if}
			<span>{apiTokenView?.hasToken ? 'Neuen Token erzeugen' : 'Token erzeugen'}</span>
		</Button>
		{#if apiTokenView?.hasToken}
			<Button size="sm" variant="outline" disabled={form.revoking} onclick={revokeToken}>
				{#if form.revoking}<Spinner class="size-3.5" />{:else}<TrashIcon class="size-3.5" />{/if}
				<span>Token ablehnen</span>
			</Button>
		{/if}
	</div>

	{#if pendingAction === 'replace'}
		<ConfirmDialog
			title="Token ersetzen"
			message="Den aktuellen Token ersetzen? Er ist danach ungültig."
			confirmLabel="Ersetzen"
			onConfirm={generateToken}
			onClose={() => (pendingAction = null)}
		/>
	{:else if pendingAction === 'revoke'}
		<ConfirmDialog
			title="Token ablehnen"
			message="API-Token ablehnen? Externe Tools verlieren sofort den Zugriff."
			confirmLabel="Ablehnen"
			onConfirm={confirmRevokeToken}
			onClose={() => (pendingAction = null)}
		/>
	{/if}
</div>
