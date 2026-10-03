<script lang="ts">
	import { onMount } from 'svelte';
	import { api } from '$lib/api';
	import type { ProvisionSummary, SystemCaldavConfigView } from '$lib/types';
	import Button from '$lib/components/ui/button/button.svelte';
	import Input from '$lib/components/ui/input/input.svelte';
	import Label from '$lib/components/ui/label/label.svelte';
	import Badge from '$lib/components/ui/badge/badge.svelte';
	import Spinner from '$lib/components/ui/spinner/spinner.svelte';
	import { toast } from 'svelte-sonner';
	import PlugZapIcon from '@lucide/svelte/icons/plug-zap';
	import KeyRoundIcon from '@lucide/svelte/icons/key-round';
	import CheckCircleIcon from '@lucide/svelte/icons/circle-check';
	import CircleXIcon from '@lucide/svelte/icons/circle-x';
	import UsersIcon from '@lucide/svelte/icons/users';

	function errMsg(e: unknown): string {
		return e instanceof Error ? e.message : String(e);
	}

	// ── Daten laden ─────────────────────────────────────────────────────────
	let sysCaldav = $state<SystemCaldavConfigView | null>(null);
	let sBaseUrl = $state('');
	let sAdminApiUrl = $state('');
	let sToken = $state('');
	let savingSys = $state(false);
	let testingSys = $state(false);
	let sysTestResult = $state<{ ok: boolean; error?: string } | null>(null);
	let sysProvisioning = $state<ProvisionSummary | null>(null);

	async function load(): Promise<void> {
		try {
			const r = await api.adminCaldav();
			sysCaldav = r;
			sBaseUrl = r.baseUrl;
			sAdminApiUrl = r.adminApiUrl;
		} catch (e) {
			toast.error(errMsg(e));
		}
	}

	async function saveSys(): Promise<void> {
		if (!sBaseUrl.trim() || !sAdminApiUrl.trim()) {
			toast.error('Basis-URL und Admin-API-URL sind erforderlich.');
			return;
		}
		savingSys = true;
		try {
			const v = await api.adminSaveCaldav({
				baseUrl: sBaseUrl.trim(),
				adminApiUrl: sAdminApiUrl.trim(),
				adminToken: sToken.trim() || undefined
			});
			sysCaldav = v;
			sToken = '';
			// Ergebnis der rückwirkenden Provisionierung für bestehende Users.
			sysProvisioning = v.provisioning;
			const { provisioned, failed } = v.provisioning;
			if (failed.length > 0) {
				toast.warning(
					`Gespeichert, aber ${failed.length}× CalDAV-Anlage fehlgeschlagen. Details unten.`
				);
			} else if (provisioned.length > 0) {
				toast.success(
					`Gespeichert. CalDAV-Accounts für ${provisioned.length} bestehenden User(s) angelegt.`
				);
			} else {
				toast.success('System-CALDAV-Konfiguration gespeichert.');
			}
			await load();
		} catch (e) {
			toast.error(errMsg(e));
		} finally {
			savingSys = false;
		}
	}

	async function testSys(): Promise<void> {
		testingSys = true;
		sysTestResult = null;
		try {
			const r = await api.adminTestCaldav({
				baseUrl: sBaseUrl.trim() || undefined,
				adminApiUrl: sAdminApiUrl.trim() || undefined,
				adminToken: sToken.trim() || undefined
			});
			sysTestResult = r;
			if (r.ok) toast.success('Admin-API erreichbar, Token gültig.');
			else toast.error(r.error ?? 'Test fehlgeschlagen.');
		} catch (e) {
			toast.error(errMsg(e));
		} finally {
			testingSys = false;
		}
	}

	onMount(() => {
		load();
	});
</script>

<!-- ══ System-CALDAV ═══════════════════════════════════════════════════ -->
<section class="space-y-3">
	<div class="flex items-center gap-2">
		<PlugZapIcon class="size-4" />
		<h2 class="text-sm font-semibold">System-CALDAV</h2>
		{#if sysCaldav?.configured}
			<Badge variant="secondary" class="text-[10px] text-emerald-700 dark:text-emerald-400">
				<CheckCircleIcon class="size-3" />
				konfiguriert
			</Badge>
		{:else}
			<Badge variant="outline" class="text-[10px]">
				<CircleXIcon class="size-3" />
				nicht konfiguriert
			</Badge>
		{/if}
	</div>
	<p class="text-xs text-muted-foreground">
		Neue Users bekommen hier automatisch einen CalDAV-Account (via caldav-admin-Sidecar);
		gelöschte Users werden dort mitsamt Collections entfernt.
	</p>

	<div class="space-y-4 rounded-xl border border-border bg-card p-5">
		<div class="grid gap-4 sm:grid-cols-2">
			<div class="space-y-1.5">
				<Label for="s-base">Basis-URL (Radicale)</Label>
				<Input id="s-base" bind:value={sBaseUrl} type="url" placeholder="http://192.168.1.135:5232" />
			</div>
			<div class="space-y-1.5">
				<Label for="s-api">Admin-API (Sidecar)</Label>
				<Input id="s-api" bind:value={sAdminApiUrl} type="url" placeholder="http://192.168.1.135:5233" />
			</div>
			<div class="space-y-1.5 sm:col-span-2">
				<Label for="s-token">Admin-Token {sysCaldav?.hasToken ? '(gesetzt – leer lassen zum Beibehalten)' : ''}</Label>
				<Input
					id="s-token"
					bind:value={sToken}
					type="password"
					placeholder={sysCaldav?.hasToken ? '●●●● (beibehalten)' : 'token'}
					autocomplete="off"
				/>
				<p class="flex items-center gap-1 text-xs text-muted-foreground">
					<KeyRoundIcon class="size-3" />
					Wird auf dem Sidecar in /etc/caldav-admin/admin.env als ADMIN_TOKEN hinterlegt.
				</p>
			</div>
		</div>
		<div class="flex flex-wrap items-center gap-2">
			<Button size="sm" disabled={savingSys || !sBaseUrl.trim() || !sAdminApiUrl.trim()} onclick={saveSys}>
				{#if savingSys}<Spinner class="size-3.5" />{/if}
				<span>Speichern</span>
			</Button>
			<Button size="sm" variant="outline" disabled={testingSys || !sAdminApiUrl.trim()} onclick={testSys}>
				{#if testingSys}<Spinner class="size-3.5" />{:else}<PlugZapIcon class="size-3.5" />{/if}
				<span>Testen</span>
			</Button>
		</div>
		{#if sysTestResult}
			<div
				class={
					'flex items-center gap-2 rounded-md px-3 py-2 text-sm ' +
					(sysTestResult.ok ? 'bg-emerald-500/10 text-emerald-700 dark:text-emerald-400' : 'bg-destructive/10 text-destructive')
				}
			>
				{#if sysTestResult.ok}
					<CheckCircleIcon class="size-4" />
					<span>Admin-API erreichbar, Token gültig.</span>
				{:else}
					<CircleXIcon class="size-4" />
					<span>{sysTestResult.error ?? 'Test fehlgeschlagen.'}</span>
				{/if}
			</div>
		{/if}
		{#if sysProvisioning}
			<div class="rounded-md border border-border bg-muted/40 px-3 py-2.5 text-sm">
				<div class="mb-1.5 flex items-center gap-1.5 font-medium">
					<UsersIcon class="size-4" />
					<span>Rückwirkende CalDAV-Provisionierung</span>
				</div>
				<ul class="space-y-1 text-xs">
					{#if sysProvisioning.provisioned.length > 0}
						<li class="flex items-start gap-1.5 text-emerald-700 dark:text-emerald-400">
							<CheckCircleIcon class="mt-0.5 size-3.5 shrink-0" />
							<span>Angelegt: {sysProvisioning.provisioned.join(', ')}</span>
						</li>
					{/if}
					{#if sysProvisioning.skipped.length > 0}
						<li class="flex items-start gap-1.5 text-muted-foreground">
							<CircleXIcon class="mt-0.5 size-3.5 shrink-0" />
							<span>
								Übersprungen (bereits zugewiesen / deaktiviert): {sysProvisioning.skipped.join(', ')}
							</span>
						</li>
					{/if}
					{#each sysProvisioning.failed as f}
						<li class="flex items-start gap-1.5 text-destructive">
							<CircleXIcon class="mt-0.5 size-3.5 shrink-0" />
							<span>{f.username}: {f.error}</span>
						</li>
					{/each}
					{#if sysProvisioning.provisioned.length === 0 &&
						sysProvisioning.skipped.length === 0 &&
						sysProvisioning.failed.length === 0}
						<li class="text-muted-foreground">
							Nichts zu tun – alle User sind bereits zugewiesen.
						</li>
					{/if}
				</ul>
			</div>
		{/if}
	</div>
</section>
