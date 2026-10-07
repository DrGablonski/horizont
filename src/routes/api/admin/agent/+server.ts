// Admin: globale KI-Agent-Konfiguration.
//
//   GET  → Status (API-Key nie im Klartext)
//   POST → speichern (apiKey nur setzen, wenn neu angegeben)

import { json } from '@sveltejs/kit';
import type { RequestHandler } from '@sveltejs/kit';
import { getAgentGlobalView, saveAgentGlobal } from '$server/agent/configStore';
import type { AgentProvider } from '$lib/types';

export const GET: RequestHandler = ({ locals }) => {
	if (locals.user?.role !== 'admin') {
		return json({ error: 'Keine Berechtigung.' }, { status: 403 });
	}
	return json(getAgentGlobalView());
};

export const POST: RequestHandler = async ({ request, locals }) => {
	if (locals.user?.role !== 'admin') {
		return json({ error: 'Keine Berechtigung.' }, { status: 403 });
	}

	const body = (await request.json().catch(() => null)) as {
		enabled?: boolean;
		provider?: string;
		baseUrl?: string;
		model?: string;
		apiKey?: string;
	} | null;

	if (!body) return json({ error: 'Ungültiger JSON-Body.' }, { status: 400 });
	const baseUrl = typeof body.baseUrl === 'string' ? body.baseUrl.trim() : '';
	const model = typeof body.model === 'string' ? body.model.trim() : '';
	if (!baseUrl || !model) {
		return json({ error: 'Basis-URL und Modell sind erforderlich.' }, { status: 400 });
	}

	const provider: AgentProvider = body.provider === 'ollama' ? 'ollama' : 'openai';
	try {
		saveAgentGlobal({
			enabled: Boolean(body.enabled),
			provider,
			baseUrl,
			model,
			apiKey:
				typeof body.apiKey === 'string' && body.apiKey.trim() !== ''
					? body.apiKey.trim()
					: undefined
		});
	} catch (e) {
		return json({ error: e instanceof Error ? e.message : 'Unbekannter Fehler' }, { status: 400 });
	}
	return json(getAgentGlobalView());
};
