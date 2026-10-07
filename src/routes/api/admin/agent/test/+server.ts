// Admin: Verbindungstest der globalen KI-Agent-Konfiguration
// (entweder die gespeicherte oder frisch eingegebene Werte).
//
//   POST { provider?, baseUrl?, model?, apiKey? } → { ok, reply? } | { ok: false, error }

import { json } from '@sveltejs/kit';
import type { RequestHandler } from '@sveltejs/kit';
import { getAgentGlobalRaw } from '$server/agent/configStore';
import { testLLM } from '$server/agent/upstream';
import type { AgentConfig, AgentProvider } from '$lib/types';

export const POST: RequestHandler = async ({ request, locals }) => {
	if (locals.user?.role !== 'admin') {
		return json({ error: 'Keine Berechtigung.' }, { status: 403 });
	}

	const saved = getAgentGlobalRaw();
	const body = (await request.json().catch(() => null)) as {
		provider?: string;
		baseUrl?: string;
		model?: string;
		apiKey?: string;
	} | null;

	const provider: AgentProvider =
		body?.provider === 'openai' || body?.provider === 'ollama'
			? body.provider
			: (saved?.provider ?? 'openai');
	const baseUrl = (typeof body?.baseUrl === 'string' ? body.baseUrl.trim() : '') || saved?.baseUrl || '';
	const model = (typeof body?.model === 'string' ? body.model.trim() : '') || saved?.model || '';
	if (!baseUrl || !model) {
		return json({ ok: false, error: 'Basis-URL und Modell sind erforderlich.' });
	}

	const config: AgentConfig = {
		provider,
		baseUrl,
		model,
		apiKey:
			(typeof body?.apiKey === 'string' && body.apiKey.trim() !== ''
				? body.apiKey.trim()
				: saved?.apiKey ?? '')
	};

	try {
		const reply = await testLLM(config, 'Alles klar? Antworte nur mit „ja".', request.signal);
		return json({ ok: true, reply: reply.slice(0, 200) });
	} catch (e) {
		const msg = e instanceof Error ? e.message : 'Unbekannter Fehler beim Verbindungstest.';
		return json({ ok: false, error: msg });
	}
};
