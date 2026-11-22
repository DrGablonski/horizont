import { json } from '@sveltejs/kit';
import type { RequestEvent } from './$types';
import { withUser, mapWorkflowError } from '$server/lib/route';
import { addStep } from '$server/store/store';

export const POST = withUser<RequestEvent>(
	async ({ params, request, locals }) => {
		const body = (await request.json().catch(() => ({}))) as { title?: string };
		const wf = await addStep(locals.user.id, params.id, body.title ?? '');
		if (!wf) return json({ error: 'Workflow nicht gefunden.' }, { status: 404 });
		return json(wf, { status: 201 });
	},
	mapWorkflowError
);
