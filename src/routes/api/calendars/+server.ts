import { json } from '@sveltejs/kit';
import type { RequestHandler } from '@sveltejs/kit';
import { listConnections } from '$server/store/connections';
import { resolveAllCalendars } from '$server/caldav/multi';

export const GET: RequestHandler = async ({ locals }) => {
	const connections = locals.user ? listConnections(locals.user.id) : [];
	if (connections.length === 0) {
		return json({ configured: false, calendars: [] });
	}

	const { items, errors } = await resolveAllCalendars(connections);
	return json({
		configured: true,
		calendars: items.map((i) => i.calendar),
		error: errors.length > 0 ? errors.join(' | ') : undefined
	});
};
