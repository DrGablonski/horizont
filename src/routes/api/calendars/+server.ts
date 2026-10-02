import { json } from '@sveltejs/kit';
import { getSettings } from '$server/store/store';
import { resolveCalendars } from '$server/lib/caldav';

export async function GET() {
	const settings = getSettings();
	if (!settings) {
		return json({ configured: false, calendars: [] });
	}
	try {
		const calendars = await resolveCalendars(settings);
		return json({ configured: true, calendars });
	} catch (e: any) {
		return json({ configured: true, calendars: [], error: e.message ?? 'Unbekannter Fehler' }, { status: 502 });
	}
}
