import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { deleteWorkflow, getWorkflow, updateWorkflow } from '$server/store/store';
import { mapError } from '$server/lib/workflowErrors';
import type { UpdateWorkflowInput } from '$lib/types';

export const GET: RequestHandler = async ({ params, locals }) => {
	try {
		const wf = await getWorkflow(locals.user!.id, params.id);
		if (!wf) return json({ error: 'Workflow nicht gefunden.' }, { status: 404 });
		return json(wf);
	} catch (err) {
		const e = mapError(err);
		return json({ error: e.message }, { status: e.status });
	}
};

export const PATCH: RequestHandler = async ({ params, request, locals }) => {
	try {
		const body = (await request.json().catch(() => ({}))) as UpdateWorkflowInput;
		const wf = await updateWorkflow(locals.user!.id, params.id, body);
		if (!wf) return json({ error: 'Workflow nicht gefunden.' }, { status: 404 });
		return json(wf);
	} catch (err) {
		const e = mapError(err);
		return json({ error: e.message }, { status: e.status });
	}
};

export const DELETE: RequestHandler = async ({ params, locals }) => {
	try {
		const ok = await deleteWorkflow(locals.user!.id, params.id);
		if (!ok) return json({ error: 'Workflow nicht gefunden.' }, { status: 404 });
		return json({ ok: true });
	} catch (err) {
		const e = mapError(err);
		return json({ error: e.message }, { status: e.status });
	}
};
