import { json } from '@sveltejs/kit';
import type { RequestEvent } from './$types';
import { withUser, mapWorkflowError } from '$server/lib/route';
import { deleteStep, updateStep } from '$server/store/store';
import type { UpdateStepInput } from '$lib/types';

export const PATCH = withUser<RequestEvent>(
	async ({ params, request, locals }) => {
		const body = (await request.json().catch(() => ({}))) as UpdateStepInput;
		const wf = await updateStep(locals.user.id, params.id, params.stepId, body);
		if (!wf) return json({ error: 'Workflow nicht gefunden.' }, { status: 404 });
		return json(wf);
	},
	mapWorkflowError
);

export const DELETE = withUser<RequestEvent>(
	async ({ params, locals }) => {
		const wf = await deleteStep(locals.user.id, params.id, params.stepId);
		if (!wf) return json({ error: 'Workflow nicht gefunden.' }, { status: 404 });
		return json(wf);
	},
	mapWorkflowError
);
