import { json } from '@sveltejs/kit';
import type { RequestEvent } from './$types';
import { withUser, mapWorkflowError } from '$server/lib/route';
import { resetWorkflow } from '$server/store/store';

export const POST = withUser<RequestEvent>(
	async ({ params, locals }) => {
		const wf = await resetWorkflow(locals.user.id, params.id);
		if (!wf) return json({ error: 'Workflow nicht gefunden.' }, { status: 404 });
		return json(wf);
	},
	mapWorkflowError
);
