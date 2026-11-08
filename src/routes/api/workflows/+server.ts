import { json } from '@sveltejs/kit';
import type { RequestHandler } from '@sveltejs/kit';
import { createWorkflow, listWorkflows } from '$server/store/store';
import { mapError } from '$server/lib/workflowErrors';
import type { CreateWorkflowInput } from '$lib/types';

export const GET: RequestHandler = async ({ locals }) => {
	try {
		return json(await listWorkflows(locals.user!.id));
	} catch (err) {
		const e = mapError(err);
		return json({ error: e.message }, { status: e.status });
	}
};

export const POST: RequestHandler = async ({ request, locals }) => {
	try {
		const body = (await request.json().catch(() => ({}))) as Partial<CreateWorkflowInput>;
		const wf = await createWorkflow(locals.user!.id, {
			title: body.title ?? '',
			steps: body.steps ?? []
		});
		return json(wf, { status: 201 });
	} catch (err) {
		const e = mapError(err);
		return json({ error: e.message }, { status: e.status });
	}
};
