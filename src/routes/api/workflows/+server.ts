import { json } from '@sveltejs/kit';
import { withUser, mapWorkflowError } from '$server/lib/route';
import { createWorkflow, listWorkflows } from '$server/store/store';
import type { CreateWorkflowInput } from '$lib/types';

export const GET = withUser(
	async ({ locals }) => json(await listWorkflows(locals.user.id)),
	mapWorkflowError
);

export const POST = withUser(
	async ({ request, locals }) => {
		const body = (await request.json().catch(() => ({}))) as Partial<CreateWorkflowInput>;
		const wf = await createWorkflow(locals.user.id, {
			title: body.title ?? '',
			steps: body.steps ?? []
		});
		return json(wf, { status: 201 });
	},
	mapWorkflowError
);
