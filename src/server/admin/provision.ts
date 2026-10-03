// CalDAV-Provisionierung für Users: stellt sicher, dass ein User eine zugewiesene
// CalDAV-Verbindung hat – sofern eine System-CalDAV-Konfiguration hinterlegt ist.
//
// Idempotent: User, die bereits eine „assigned"-Verbindung haben, werden nicht
// berührt. Wird genutzt von
//   1. User-Anlage (POST /api/admin/users)
//   2. Setup (POST /api/auth/setup) – für den Admin
//   3. (Rück-)Konfiguration der System-CalDAV (POST /api/admin/caldav) –
//      rückwirkend für alle bestehenden Users (davor: Bug, es passierte nichts).

import { randomBytes } from 'node:crypto';
import { listUsers } from '$server/auth/userStore';
import { getSystemCaldav } from '$server/store/system';
import { getAssigned, setAssigned } from '$server/store/connections';
import { createCaldavUser } from '$server/admin/caldavAdmin';
import type { CaldavHandover, ProvisionSummary } from '$lib/types';

function generatePassword(): string {
	return randomBytes(12).toString('base64url').slice(0, 16);
}

/**
 * Legt – falls nötig – einen CalDAV-Account für den User an und legt die
 * Zugangsdaten als „assigned"-Verbindung ab.
 *
 * Rückgabe:
 *   - CalDAV-Zugangsdaten, wenn ein Account neu angelegt wurde
 *   - null, wenn der User bereits eine zugewiesene Verbindung hat oder keine
 *     System-CalDAV-Konfiguration existiert
 *
 * Wirft einen SidecarError, wenn die Account-Anlage fehlschlägt (nur, wenn
 * tatsächlich angelegt werden sollte). Der Aufrufer entscheidet, was mit dem
 * Fehler zu tun ist (z. B. User-Anlage rückgängig machen).
 */
export async function ensureCaldavForUser(userId: string, username: string): Promise<CaldavHandover | null> {
	// Idempotenz: bereits zugewiesen → nichts tun.
	if (getAssigned(userId)) return null;

	const cfg = getSystemCaldav();
	if (!cfg) return null;

	const password = generatePassword();
	await createCaldavUser(cfg, username, password);
	setAssigned(userId, { url: cfg.baseUrl, username, password });
	return { url: cfg.baseUrl, username, password };
}

/**
 * Legt CalDAV-Accounts für alle aktiven Users an, die noch keine zugewiesene
 * Verbindung haben. Wird nach (Rück-)Konfiguration der System-CalDAV aufgerufen,
 * damit bestehende Users rückwirkend einen CalDAV-Account erhalten.
 *
 * Wirft nie – einzelne Fehler werden im Summary gesammelt.
 */
export async function ensureCaldavForAllUsers(): Promise<ProvisionSummary> {
	const summary: ProvisionSummary = { provisioned: [], skipped: [], failed: [] };
	const cfg = getSystemCaldav();

	for (const u of listUsers()) {
		// Deaktivierte Users und User mit vorhandener Verbindung überspringen.
		if (u.disabled) {
			summary.skipped.push(u.username);
			continue;
		}
		if (getAssigned(u.id)) {
			summary.skipped.push(u.username);
			continue;
		}
		// Ohne System-CalDAV ist keine Anlage möglich.
		if (!cfg) {
			summary.skipped.push(u.username);
			continue;
		}
		try {
			await ensureCaldavForUser(u.id, u.username);
			summary.provisioned.push(u.username);
		} catch (e) {
			summary.failed.push({ username: u.username, error: e instanceof Error ? e.message : String(e) });
		}
	}
	return summary;
}
