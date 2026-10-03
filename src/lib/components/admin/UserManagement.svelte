<script lang="ts">
	import { onMount } from 'svelte';
	import { api, type AdminUserPatch } from '$lib/api';
	import type { AdminUserView, CreateUserResult, SystemCaldavConfigView } from '$lib/types';
	import Button from '$lib/components/ui/button/button.svelte';
	import Input from '$lib/components/ui/input/input.svelte';
	import Label from '$lib/components/ui/label/label.svelte';
	import Badge from '$lib/components/ui/badge/badge.svelte';
	import Spinner from '$lib/components/ui/spinner/spinner.svelte';
	import { toast } from 'svelte-sonner';
	import UsersIcon from '@lucide/svelte/icons/users';
	import PlusIcon from '@lucide/svelte/icons/plus';
	import PencilIcon from '@lucide/svelte/icons/pencil';
	import TrashIcon from '@lucide/svelte/icons/trash-2';
	import XIcon from '@lucide/svelte/icons/x';
	import PlugZapIcon from '@lucide/svelte/icons/plug-zap';
	import CopyIcon from '@lucide/svelte/icons/copy';
	import CheckCircleIcon from '@lucide/svelte/icons/circle-check';

	function errMsg(e: unknown): string {
		return e instanceof Error ? e.message : String(e);
	}

	function fmtDate(ts: number | null): string {
		if (!ts) return '–';
		return new Date(ts).toLocaleString('de-DE', { dateStyle: 'medium', timeStyle: 'short' });
	}

	// ── Daten laden ─────────────────────────────────────────────────────────
	let users = $state<AdminUserView[]>([]);
	let sysCaldav = $state<SystemCaldavConfigView | null>(null);
	let loading = $state(true);

	async function load(): Promise<void> {
		loading = true;
		try {
			const r = await api.adminUsers();
			users = r.users;
			sysCaldav = r.systemCaldav;
		} catch (e) {
			toast.error(errMsg(e));
		} finally {
			loading = false;
		}
	}

	// ── User anlegen ────────────────────────────────────────────────────────
	let showCreate = $state(false);
	let cuUser = $state('');
	let cuPass = $state('');
	let creating = $state(false);
	let handover = $state<CreateUserResult | null>(null);

	async function createUser(): Promise<void> {
		if (!cuUser.trim() || !cuPass) {
			toast.error('Benutzername und Passwort sind erforderlich.');
			return;
		}
		creating = true;
		handover = null;
		try {
			const r = await api.adminCreateUser({ username: cuUser.trim(), password: cuPass });
			handover = r;
			cuUser = '';
			cuPass = '';
			await load();
			toast.success('User angelegt.');
		} catch (e) {
			toast.error(errMsg(e));
		} finally {
			creating = false;
		}
	}

	async function copy(text: string): Promise<void> {
		try {
			await navigator.clipboard.writeText(text);
			toast.success('In die Zwischenablage kopiert.');
		} catch {
			toast.error('Kopieren nicht möglich.');
		}
	}

	function copyCaldav(field: 'url' | 'username' | 'password' | 'all'): void {
		const h = handover;
		if (!h) return;
		const c = h.caldav;
		if (!c) return;
		void copy(
			field === 'all'
				? `CalDAV-Zugang für ${h.user.username}:\nURL: ${c.url}\nBenutzername: ${c.username}\nPasswort: ${c.password}`
				: c[field]
		);
	}

	// ── User bearbeiten ─────────────────────────────────────────────────────
	let editing = $state<AdminUserView | null>(null);
	let eRole = $state<'admin' | 'user'>('user');
	let eDisabled = $state(false);
	let ePass = $state('');
	let eCalUrl = $state('');
	let eCalUser = $state('');
	let eCalPass = $state('');
	let showCaldav = $state(false);
	let saving = $state(false);

	function startEdit(u: AdminUserView): void {
		editing = u;
		eRole = u.role;
		eDisabled = u.disabled;
		ePass = '';
		eCalUrl = '';
		eCalUser = '';
		eCalPass = '';
		showCaldav = false;
	}

	async function saveEdit(): Promise<void> {
		if (!editing) return;
		const patch: AdminUserPatch = { role: eRole, disabled: eDisabled };
		if (ePass) patch.password = ePass;
		if (showCaldav) {
			if (!eCalUrl.trim()) {
				toast.error('CalDAV-URL fehlt.');
				return;
			}
			patch.caldav = { url: eCalUrl, username: eCalUser, password: eCalPass };
		}
		saving = true;
		try {
			await api.adminPatchUser(editing.id, patch);
			editing = null;
			await load();
			toast.success('User aktualisiert.');
		} catch (e) {
			toast.error(errMsg(e));
		} finally {
			saving = false;
		}
	}

	// ── User löschen ────────────────────────────────────────────────────────
	let deleting = $state(false);
	async function removeUser(u: AdminUserView): Promise<void> {
		const msg = `User „${u.username}“ unwiderruflich löschen?` +
			(u.hasAssignedConnection ? ' Dessen CalDAV-Account und alle Daten werden ebenfalls entfernt.' : '');
		if (!confirm(msg)) return;
		deleting = true;
		try {
			await api.adminDeleteUser(u.id);
			await load();
			toast.success('User gelöscht.');
		} catch (e) {
			toast.error(errMsg(e));
		} finally {
			deleting = false;
		}
	}

	onMount(() => {
		load();
	});
</script>

{#if loading && users.length === 0}
	<div class="flex items-center gap-2 rounded-xl border border-dashed border-border p-8 text-sm text-muted-foreground">
		<Spinner class="size-4" />
		<span>Wird geladen …</span>
	</div>
{:else}
	<!-- ══ User-Verwaltung ═════════════════════════════════════════════════ -->
	<section class="space-y-3">
		<div class="flex items-center justify-between">
			<div class="flex items-center gap-2">
				<UsersIcon class="size-4" />
				<h2 class="text-sm font-semibold">Users</h2>
				<Badge variant="outline" class="text-xs">{users.length}</Badge>
			</div>
			<Button size="sm" variant="outline" onclick={() => (showCreate = !showCreate)}>
				<PlusIcon class="size-3.5" />
				<span>Neuer User</span>
			</Button>
		</div>

		{#if showCreate}
			<div class="space-y-4 rounded-xl border border-border bg-card p-5">
				<div class="grid gap-4 sm:grid-cols-2">
					<div class="space-y-1.5">
						<Label for="cu-user">Benutzername</Label>
						<Input id="cu-user" bind:value={cuUser} placeholder="vorname.nachname" autocomplete="off" />
					</div>
					<div class="space-y-1.5">
						<Label for="cu-pass">Anfangs-Passwort</Label>
						<Input
							id="cu-pass"
							bind:value={cuPass}
							type="text"
							placeholder="mind. 8 Zeichen"
							autocomplete="new-password"
						/>
					</div>
				</div>
				{#if sysCaldav?.configured}
					<p class="rounded-md bg-muted px-3 py-2 text-xs text-muted-foreground">
						Der CalDAV-Account wird automatisch beim System-CALDAV
						({sysCaldav.baseUrl}) angelegt. Die Zugangsdaten erscheinen nach dem Anlegen.
					</p>
				{:else}
					<p class="rounded-md bg-muted px-3 py-2 text-xs text-muted-foreground">
						Kein System-CALDAV konfiguriert – es wird nur der App-Account angelegt.
						Den CalDAV-Zugang kannst du später im User-Bearbeiten zuordnen.
					</p>
				{/if}
				<Button size="sm" disabled={creating || !cuUser.trim() || !cuPass} onclick={createUser}>
					{#if creating}<Spinner class="size-3.5" />{:else}<PlusIcon class="size-3.5" />{/if}
					<span>Anlegen</span>
				</Button>
			</div>
		{/if}

		<!-- Handover nach User-Anlage -->
		{#if handover}
			<div class="space-y-3 rounded-xl border border-emerald-500/30 bg-emerald-500/5 p-5">
				<div class="flex items-center gap-2">
					<CheckCircleIcon class="size-4 text-emerald-600 dark:text-emerald-400" />
					<span class="text-sm font-medium text-emerald-700 dark:text-emerald-400">
						User „{handover.user.username}“ angelegt – Zugangsdaten einmalig anzeigen
					</span>
				</div>
				<div class="space-y-2 text-sm">
					<div class="flex items-center justify-between gap-2 rounded-md bg-background px-3 py-2">
						<div class="min-w-0">
							<p class="text-xs text-muted-foreground">App-Login</p>
							<p class="truncate font-mono text-xs">{handover.user.username} / (das Anfangs-Passwort oben)</p>
						</div>
					</div>
					{#if handover.caldav}
						<div class="space-y-2 rounded-md bg-background px-3 py-2">
							<p class="text-xs font-medium text-muted-foreground">CalDAV-Zugang (an den User übergeben)</p>
							<div class="flex items-center justify-between gap-2">
								<p class="truncate font-mono text-xs">{handover.caldav.url}</p>
								<Button size="icon-xs" variant="ghost" title="Kopieren" onclick={() => copyCaldav('url')}>
									<CopyIcon class="size-3" />
								</Button>
							</div>
							<div class="flex items-center justify-between gap-2">
								<p class="truncate font-mono text-xs">{handover.caldav.username}</p>
								<Button size="icon-xs" variant="ghost" title="Kopieren" onclick={() => copyCaldav('username')}>
									<CopyIcon class="size-3" />
								</Button>
							</div>
							<div class="flex items-center justify-between gap-2">
								<p class="truncate font-mono text-xs">{handover.caldav.password}</p>
								<Button size="icon-xs" variant="ghost" title="Kopieren" onclick={() => copyCaldav('password')}>
									<CopyIcon class="size-3" />
								</Button>
							</div>
							<Button size="sm" variant="secondary" class="mt-1" onclick={() => copyCaldav('all')}>
								<CopyIcon class="size-3.5" />
								<span>Alles kopieren</span>
							</Button>
						</div>
					{:else}
						<p class="text-xs text-muted-foreground">
							Kein CalDAV-Account angelegt (kein System-CALDAV konfiguriert).
						</p>
					{/if}
					<div class="flex justify-end">
						<Button size="sm" variant="ghost" onclick={() => (handover = null)}>
							<XIcon class="size-3.5" />
							<span>Schließen</span>
						</Button>
					</div>
				</div>
			</div>
		{/if}

		<!-- User-Tabelle -->
		<div class="overflow-x-auto rounded-xl border border-border">
			<table class="w-full text-sm">
				<thead>
					<tr class="border-b border-border bg-muted/40 text-left text-xs text-muted-foreground">
						<th class="px-3 py-2 font-medium">Benutzername</th>
						<th class="px-3 py-2 font-medium">Rolle</th>
						<th class="px-3 py-2 font-medium">Status</th>
						<th class="px-3 py-2 font-medium">CalDAV</th>
						<th class="px-3 py-2 font-medium">Zuletzt</th>
						<th class="px-3 py-2"></th>
					</tr>
				</thead>
				<tbody>
					{#each users as u (u.id)}
						{#if editing?.id === u.id}
							<!-- Bearbeitungs-Panel -->
							<tr class="bg-muted/20">
								<td class="px-3 py-4" colspan="6">
									<div class="space-y-4">
										<div class="flex items-center justify-between">
											<span class="text-sm font-medium">{u.username} bearbeiten</span>
											<Button size="sm" variant="ghost" onclick={() => (editing = null)}>
												<XIcon class="size-3.5" />
												<span>Fertig</span>
											</Button>
										</div>
										<div class="grid gap-4 sm:grid-cols-3">
											<div class="space-y-1.5">
												<Label for="e-role">Rolle</Label>
												<select id="e-role" class="h-8 w-full rounded-md border border-border bg-transparent px-2 text-sm" bind:value={eRole}>
													<option value="user">User</option>
													<option value="admin">Admin</option>
												</select>
											</div>
											<div class="space-y-1.5">
												<Label for="e-disabled">Status</Label>
												<select
													id="e-disabled"
													class="h-8 w-full rounded-md border border-border bg-transparent px-2 text-sm"
													bind:value={eDisabled}
												>
													<option value={false}>Aktiv</option>
													<option value={true}>Deaktiviert</option>
												</select>
											</div>
											<div class="space-y-1.5">
												<Label for="e-pass">Neues Passwort (optional)</Label>
												<Input
													id="e-pass"
													bind:value={ePass}
													type="text"
													placeholder="leer = beibehalten"
													autocomplete="new-password"
												/>
											</div>
										</div>
										<div class="rounded-md border border-border p-3">
											<button
												type="button"
												class="flex items-center gap-2 text-sm"
												onclick={() => (showCaldav = !showCaldav)}
											>
												<PlugZapIcon class="size-3.5" />
												<span class="font-medium">
													CalDAV-Verbindung {u.hasAssignedConnection ? 'ersetzen' : 'zuordnen'}
												</span>
												<span class="text-xs text-muted-foreground">{showCaldav ? 'ausblenden' : 'aufklappen'}</span>
											</button>
											{#if showCaldav}
												<div class="mt-3 grid gap-3 sm:grid-cols-3">
													<div class="space-y-1.5 sm:col-span-3">
														<Label for="e-cal-url">CalDAV-URL</Label>
														<Input id="e-cal-url" bind:value={eCalUrl} type="url" placeholder="http://host:5232" />
													</div>
													<div class="space-y-1.5">
														<Label for="e-cal-user">Benutzername</Label>
														<Input id="e-cal-user" bind:value={eCalUser} placeholder={u.username} />
													</div>
													<div class="space-y-1.5">
														<Label for="e-cal-pass">Passwort</Label>
														<Input id="e-cal-pass" bind:value={eCalPass} type="text" placeholder="passwort" />
													</div>
												</div>
											{/if}
										</div>
										<div class="flex justify-end">
											<Button size="sm" disabled={saving} onclick={saveEdit}>
												{#if saving}<Spinner class="size-3.5" />{/if}
												<span>Speichern</span>
											</Button>
										</div>
									</div>
								</td>
							</tr>
						{:else}
							<tr class="border-b border-border last:border-0 hover:bg-muted/20">
								<td class="px-3 py-2 font-medium">{u.username}</td>
								<td class="px-3 py-2">
									{#if u.role === 'admin'}
										<Badge variant="secondary" class="text-[10px]">admin</Badge>
									{:else}
										<Badge variant="outline" class="text-[10px]">user</Badge>
									{/if}
								</td>
								<td class="px-3 py-2">
									{#if u.disabled}
										<Badge variant="destructive" class="text-[10px]">deaktiviert</Badge>
									{:else}
										<Badge variant="outline" class="text-[10px] text-emerald-700 dark:text-emerald-400">aktiv</Badge>
									{/if}
								</td>
								<td class="px-3 py-2">
									{#if u.hasAssignedConnection}
										<span class="text-xs text-emerald-700 dark:text-emerald-400">zugewiesen</span>
									{:else}
										<span class="text-xs text-muted-foreground">–</span>
									{/if}
								</td>
								<td class="px-3 py-2 text-xs text-muted-foreground">{fmtDate(u.lastLoginAt)}</td>
								<td class="px-3 py-2">
									<div class="flex items-center justify-end gap-1">
										<Button variant="ghost" size="icon" title="Bearbeiten" onclick={() => startEdit(u)}>
											<PencilIcon class="size-3.5" />
										</Button>
										<Button
											variant="ghost"
											size="icon"
											title="Löschen"
											disabled={deleting}
											onclick={() => removeUser(u)}
										>
											<TrashIcon class="size-3.5" />
										</Button>
									</div>
								</td>
							</tr>
						{/if}
					{/each}
				</tbody>
			</table>
		</div>
	</section>
{/if}
