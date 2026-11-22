import { json } from '@sveltejs/kit';
import type { RequestEvent } from './$types';
import { withUser, mapWorkflowError } from '$server/lib/route';
import { deleteWorkflow, getWorkflow, updateWorkflow } from '$server/store/store';
import type { UpdateWorkflowInput } from '$lib/types';

export const GET = withUser<RequestEvent>(
	async ({ params, locals }) => {
		const wf = await getWorkflow(locals.user.id, params.id);
		if (!wf) return json({ error: 'Workflow nicht gefunden.' }, { status: 404 });
		return json(wf);
	},
	mapWorkflowError
);

export const PATCH = withUser<RequestEvent>(
	async ({ params, request, locals }) => {
		const body = (await request.json().catch(() => ({}))) as UpdateWorkflowInput;
		const wf = await updateWorkflow(locals.user.id, params.id, body);
		if (!wf) return json({ error: 'Workflow nicht gefunden.' }, { status: 404 });
		return json(wf);
	},
	mapWorkflowError
);

export const DELETE = withUser<RequestEvent>(
	async ({ params, locals }) => {
		const ok = await deleteWorkflow(locals.user.id, params.id);
		if (!ok) return json({ error: 'Workflow nicht gefunden.' }, { status: 404 });
		return json({ ok: true });
	},
	mapWorkflowError
);
