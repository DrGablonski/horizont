import { json } from '@sveltejs/kit';
import { deleteWorkflow, getWorkflow, updateWorkflow } from '$server/store/store';
import { mapError } from '$server/lib/workflowErrors';
import type { UpdateWorkflowInput } from '$lib/types';

export async function GET({ params }: { params: { id: string } }) {
	try {
		const wf = await getWorkflow(params.id);
		if (!wf) return json({ error: 'Workflow nicht gefunden.' }, { status: 404 });
		return json(wf);
	} catch (err) {
		const e = mapError(err);
		return json({ error: e.message }, { status: e.status });
	}
}

export async function PATCH({ params, request }: { params: { id: string }; request: Request }) {
	try {
		const body = (await request.json().catch(() => ({}))) as UpdateWorkflowInput;
		const wf = await updateWorkflow(params.id, body);
		if (!wf) return json({ error: 'Workflow nicht gefunden.' }, { status: 404 });
		return json(wf);
	} catch (err) {
		const e = mapError(err);
		return json({ error: e.message }, { status: e.status });
	}
}

export async function DELETE({ params }: { params: { id: string } }) {
	try {
		const ok = await deleteWorkflow(params.id);
		if (!ok) return json({ error: 'Workflow nicht gefunden.' }, { status: 404 });
		return json({ ok: true });
	} catch (err) {
		const e = mapError(err);
		return json({ error: e.message }, { status: e.status });
	}
}
