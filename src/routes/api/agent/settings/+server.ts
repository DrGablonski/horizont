// KI-Agent: eigene (pro-User) Konfiguration.
//
//   GET → View der eigenen Config + Status der globalen Config
//   PUT → eigene Config speichern (apiKey bleibt, wenn leer),
//         {enabled: bool} nur an-/ausschalten, oder {reset: true}
//
// Der API-Key wird nie im Klartext zurückgegeben.

import { json } from '@sveltejs/kit';
import type { RequestHandler } from '@sveltejs/kit';
import {
	getAgentGlobalView,
	getAgentUser,
	getAgentUserView,
	saveAgentUser,
	setAgentUserEnabled
} from '$server/agent/configStore';
import type { AgentProvider } from '$lib/types';

export const GET: RequestHandler = ({ locals }) => {
	const user = locals.user;
	if (!user) return json({ error: 'Nicht angemeldet.' }, { status: 401 });
	const g = getAgentGlobalView();
	return json({
		own: getAgentUserView(user.id),
		global: {
			enabled: g.enabled,
			configured: g.configured,
			provider: g.provider,
			baseUrl: g.baseUrl,
			model: g.model
		}
	});
};

export const PUT: RequestHandler = async ({ request, locals }) => {
	const user = locals.user;
	if (!user) return json({ error: 'Nicht angemeldet.' }, { status: 401 });

	const body = (await request.json().catch(() => null)) as {
		reset?: boolean;
		enabled?: boolean;
		provider?: string;
		baseUrl?: string;
		model?: string;
		apiKey?: string;
	} | null;
	if (!body) return json({ error: 'Ungültiger JSON-Body.' }, { status: 400 });

	if (typeof body.enabled === 'boolean') {
		setAgentUserEnabled(user.id, body.enabled);
	} else if (body.reset === true) {
		saveAgentUser(user.id, null);
	} else {
		const provider: AgentProvider = body.provider === 'ollama' ? 'ollama' : 'openai';
		const baseUrl = typeof body.baseUrl === 'string' ? body.baseUrl.trim() : '';
		const model = typeof body.model === 'string' ? body.model.trim() : '';
		if (!baseUrl || !model) {
			return json({ error: 'Basis-URL und Modell sind erforderlich.' }, { status: 400 });
		}
		const current = getAgentUser(user.id);
		saveAgentUser(user.id, {
			provider,
			baseUrl,
			model,
			apiKey:
				typeof body.apiKey === 'string' && body.apiKey.trim() !== ''
					? body.apiKey.trim()
					: current?.apiKey ?? ''
		});
	}

	return json({ own: getAgentUserView(user.id) });
};
