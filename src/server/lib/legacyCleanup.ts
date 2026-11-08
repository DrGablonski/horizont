// Einmaliges Daten-Cleanup für die entfernte KI-Agent-Funktion:
// Die alten Agent-Config-Dateien (global + pro User) liest nichts mehr.
// Läuft beim Server-Start, ist idempotent und no-op, wenn nichts da ist.

import { existsSync, readdirSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { DATA_DIR } from './constants';

function rmQuietly(p: string): void {
	if (!existsSync(p)) return;
	try {
		rmSync(p, { recursive: true, force: true });
	} catch {
		// Best-Effort: Cleanup darf den Start niemals brechen.
	}
}

export function removeLegacyAgentFiles(): void {
	rmQuietly(join(DATA_DIR, 'system', 'agent.json'));

	const usersDir = join(DATA_DIR, 'users');
	if (!existsSync(usersDir)) return;
	for (const entry of readdirSync(usersDir, { withFileTypes: true })) {
		if (!entry.isDirectory()) continue;
		rmQuietly(join(usersDir, entry.name, 'agent.json'));
	}
}
