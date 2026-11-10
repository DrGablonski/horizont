// Task-Kategorien (Name + Farbe) pro User:
//   GET  → { categories: [{name, color}] }
//   POST → komplette Liste speichern: { categories: [{name, color}] }

import { json } from '@sveltejs/kit';
import type { RequestHandler } from '@sveltejs/kit';
import { getCategories, saveCategories } from '$server/store/categories';
import { invalidatePanelCache } from '$server/lib/panelCache';

export const GET: RequestHandler = ({ locals }) => {
	if (!locals.user) return json({ error: 'Nicht angemeldet.' }, { status: 401 });
	return json({ categories: getCategories(locals.user.id) });
};

export const POST: RequestHandler = async ({ request, locals }) => {
	if (!locals.user) return json({ error: 'Nicht angemeldet.' }, { status: 401 });

	const body = (await request.json().catch(() => null)) as { categories?: unknown } | null;
	if (!body || !Array.isArray(body.categories)) {
		return json({ error: 'Ungültige Eingaben.' }, { status: 400 });
	}
	try {
		const categories = saveCategories(locals.user.id, body.categories);
		invalidatePanelCache();
		return json({ categories });
	} catch (e) {
		return json({ error: e instanceof Error ? e.message : 'Ungültige Eingaben.' }, { status: 400 });
	}
};
