// KI-Agent: Verbindungstest der eigenen (vor dem Speichern) Konfiguration.
//
//   POST { provider, baseUrl, model, apiKey? } → { ok, reply? } | { ok: false, error }
// (leerer apiKey = aktuell gespeicherter Schlüssel, falls vorhanden)

import { json } from '@sveltejs/kit';
import type { RequestHandler } from '@sveltejs/kit';
import { getAgentUser } from '$server/agent/configStore';
import { testLLM } from '$server/agent/upstream';
import type { AgentConfig, AgentProvider } from '$lib/types';

export const POST: RequestHandler = async ({ request, locals }) => {
	const user = locals.user;
	if (!user) return json({ error: 'Nicht angemeldet.' }, { status: 401 });

	const body = (await request.json().catch(() => null)) as {
		provider?: string;
		baseUrl?: string;
		model?: string;
		apiKey?: string;
	} | null;
	const provider: AgentProvider = body?.provider === 'ollama' ? 'ollama' : 'openai';
	const baseUrl = typeof body?.baseUrl === 'string' ? body.baseUrl.trim() : '';
	const model = typeof body?.model === 'string' ? body.model.trim() : '';
	if (!baseUrl || !model) {
		return json({ ok: false, error: 'Basis-URL und Modell sind erforderlich.' });
	}

	const config: AgentConfig = {
		provider,
		baseUrl,
		model,
		apiKey:
			typeof body?.apiKey === 'string' && body.apiKey.trim() !== ''
				? body.apiKey.trim()
				: getAgentUser(user.id)?.apiKey ?? ''
	};

	try {
		const reply = await testLLM(config, 'Alles klar? Antworte nur mit „ja".', request.signal);
		return json({ ok: true, reply: reply.slice(0, 200) });
	} catch (e) {
		const msg = e instanceof Error ? e.message : 'Unbekannter Fehler beim Verbindungstest.';
		return json({ ok: false, error: msg });
	}
};
