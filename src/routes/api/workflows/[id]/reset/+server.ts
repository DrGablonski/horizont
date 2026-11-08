import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { resetWorkflow } from '$server/store/store';
import { mapError } from '$server/lib/workflowErrors';

export const POST: RequestHandler = async ({ params, locals }) => {
	try {
		const wf = await resetWorkflow(locals.user!.id, params.id);
		if (!wf) return json({ error: 'Workflow nicht gefunden.' }, { status: 404 });
		return json(wf);
	} catch (err) {
		const e = mapError(err);
		return json({ error: e.message }, { status: e.status });
	}
};
