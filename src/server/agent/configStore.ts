// KI-Agent-Konfiguration:
//   global  → DATA_DIR/system/agent.json   (Admin, mit Freigabe-Toggle)
//   pro User → DATA_DIR/users/{id}/agent.json (Override durch den User selbst)
//
// Auflösung der effektiven Konfiguration:
//   1. eigene User-Config (wenn vollständig) → Source 'user'
//   2. globale Config (wenn vollständig UND freigegeben) → Source 'global'
//   3. sonst null → Chat-Widget bleibt versteckt
//
// API-Keys werden nur serverseitig gehalten; Views enthalten nie Klartext.

import { mkdirSync, readFileSync, writeFileSync, renameSync, existsSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { DATA_DIR } from '$server/lib/constants';
import type { AgentConfig, AgentConfigView, AgentProvider } from '$lib/types';

// ── Global ────────────────────────────────────────────────────────────────

interface GlobalFile {
	version: 1;
	enabled: boolean;
	config: AgentConfig | null;
}

function globalPath(): string {
	mkdirSync(join(DATA_DIR, 'system'), { recursive: true });
	return join(DATA_DIR, 'system', 'agent.json');
}

function readGlobal(): GlobalFile {
	const p = globalPath();
	if (!existsSync(p)) return { version: 1, enabled: false, config: null };
	try {
		const raw = JSON.parse(readFileSync(p, 'utf8')) as Partial<GlobalFile>;
		return {
			version: 1,
			enabled: Boolean(raw.enabled),
			config: sanitizeConfig(raw.config)
		};
	} catch {
		return { version: 1, enabled: false, config: null };
	}
}

function writeGlobal(data: GlobalFile): void {
	const p = globalPath();
	const tmp = `${p}.tmp`;
	writeFileSync(tmp, JSON.stringify(data, null, 2), 'utf8');
	renameSync(tmp, p);
}

/** Global-View (ohne API-Key). */
export function getAgentGlobalView(): {
	enabled: boolean;
	configured: boolean;
	provider: AgentProvider;
	baseUrl: string;
	model: string;
	hasApiKey: boolean;
} {
	const { enabled, config } = readGlobal();
	if (!config) {
		return { enabled, configured: false, provider: 'openai', baseUrl: '', model: '', hasApiKey: false };
	}
	return {
		enabled,
		configured: true,
		provider: config.provider,
		baseUrl: config.baseUrl,
		model: config.model,
		hasApiKey: Boolean(config.apiKey)
	};
}

export function getAgentGlobalRaw(): AgentConfig | null {
	return readGlobal().config;
}

export function saveAgentGlobal(input: {
	enabled: boolean;
	provider: AgentProvider;
	baseUrl: string;
	model: string;
	apiKey?: string;
}): void {
	const current = readGlobal();
	const baseUrl = (input.baseUrl ?? '').trim().replace(/\/+$/, '');
	const model = (input.model ?? '').trim();
	if (!baseUrl) throw new Error('Basis-URL fehlt.');
	if (!model) throw new Error('Modell fehlt.');

	const config: AgentConfig = {
		provider: input.provider === 'ollama' ? 'ollama' : 'openai',
		baseUrl,
		model,
		apiKey:
			input.apiKey && input.apiKey.trim() !== ''
				? input.apiKey.trim()
				: current.config?.apiKey ?? ''
	};
	writeGlobal({ version: 1, enabled: Boolean(input.enabled), config });
}

// ── Pro User ──────────────────────────────────────────────────────────────

interface UserFile {
	version: 1;
	config: AgentConfig | null;
}

function userAgentPath(userId: string): string {
	const p = join(DATA_DIR, 'users', userId);
	mkdirSync(p, { recursive: true });
	return join(p, 'agent.json');
}

function readUserAgent(userId: string): AgentConfig | null {
	const p = userAgentPath(userId);
	if (!existsSync(p)) return null;
	try {
		const raw = JSON.parse(readFileSync(p, 'utf8')) as Partial<UserFile>;
		return sanitizeConfig(raw.config);
	} catch {
		return null;
	}
}

function writeUserAgent(userId: string, config: AgentConfig | null): void {
	const p = userAgentPath(userId);
	if (config == null) {
		rmSync(p, { force: true });
		return;
	}
	const tmp = `${p}.tmp`;
	writeFileSync(tmp, JSON.stringify({ version: 1, config }, null, 2), 'utf8');
	renameSync(tmp, p);
}

export function getAgentUser(userId: string): AgentConfig | null {
	return readUserAgent(userId);
}

export function saveAgentUser(userId: string, config: AgentConfig | null): void {
	if (config != null) {
		const baseUrl = (config.baseUrl ?? '').trim().replace(/\/+$/, '');
		const model = (config.model ?? '').trim();
		if (!baseUrl || !model) throw new Error('Basis-URL und Modell sind erforderlich.');
	}
	writeUserAgent(userId, config);
}

// ── Auflösung ─────────────────────────────────────────────────────────────

export interface ResolvedAgent {
	config: AgentConfig;
	source: 'user' | 'global';
}

/** Effektive Agent-Config für einen User (null = Widget bleibt unsichtbar). */
export function resolveAgent(userId: string): ResolvedAgent | null {
	const own = readUserAgent(userId);
	if (own) return { config: own, source: 'user' };
	const g = readGlobal();
	if (g.enabled && g.config) return { config: g.config, source: 'global' };
	return null;
}

/** Eigene User-Config als View (für die Einstellungen). */
export function getAgentUserView(userId: string): AgentConfigView {
	const c = readUserAgent(userId);
	if (!c) {
		return { configured: false, provider: 'openai', baseUrl: '', model: '', hasApiKey: false };
	}
	return {
		configured: true,
		provider: c.provider,
		baseUrl: c.baseUrl,
		model: c.model,
		hasApiKey: Boolean(c.apiKey)
	};
}

// ── Sanitizing ────────────────────────────────────────────────────────────

function sanitizeConfig(raw: unknown): AgentConfig | null {
	if (raw == null || typeof raw !== 'object') return null;
	const r = raw as Record<string, unknown>;
	const baseUrl = typeof r.baseUrl === 'string' ? r.baseUrl.trim().replace(/\/+$/, '') : '';
	const model = typeof r.model === 'string' ? r.model.trim() : '';
	if (!baseUrl || !model) return null;
	const provider: AgentProvider = r.provider === 'ollama' ? 'ollama' : 'openai';
	const apiKey = typeof r.apiKey === 'string' && r.apiKey !== '' ? r.apiKey : undefined;
	return { provider, baseUrl, model, apiKey };
}
