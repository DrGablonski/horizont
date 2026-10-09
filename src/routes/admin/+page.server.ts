import { redirect } from '@sveltejs/kit';
import type { PageServerLoad } from './$types';

// Administration ist nur für Admins. Nicht angemeldete Users werden
// bereits im Server-Hook zu /login weitergeleitet; angemeldete
// Nicht-Admins kommen zurück zur Hauptseite.
export const load: PageServerLoad = ({ locals }) => {
	if (locals.user?.role !== 'admin') redirect(303, '/');
};
