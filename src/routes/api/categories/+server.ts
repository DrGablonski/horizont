// Task-Kategorien (Name + Farbe) pro User:
//   GET  → { categories: [{name, color}] }
//   POST → komplette Liste speichern: { categories: [{name, color}] }

import { json } from '@sveltejs/kit';
import { readJsonBody } from '$server/auth/apiHelpers';
import { withUser } from '$server/lib/route';
import { getCategories, saveCategories } from '$server/store/categories';
import { invalidatePanelCache } from '$server/lib/panelCache';

export const GET = withUser(({ locals }) => json({ categories: getCategories(locals.user.id) }));

export const POST = withUser(async ({ request, locals }) => {
	const body = await readJsonBody<{ categories?: unknown }>(request);
	if (!body || !Array.isArray(body.categories)) {
		return json({ error: 'Ungültige Eingaben.' }, { status: 400 });
	}
	const categories = saveCategories(locals.user.id, body.categories);
	invalidatePanelCache();
	return json({ categories });
});
