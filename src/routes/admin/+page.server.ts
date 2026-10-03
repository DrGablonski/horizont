import { redirect } from '@sveltejs/kit';

// Die Admin-Funktionen (User-Verwaltung, System-CALDAV) wurden in
// /einstellungen verlagert (dort nur für Admins sichtbare Tabs).
// Diese Route bleibt als Umleitung für alte Links.
export function load(): void {
	redirect(303, '/einstellungen');
}
