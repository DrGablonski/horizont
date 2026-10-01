import { json } from '@sveltejs/kit';
import { deleteWorkflow, getWorkflow, updateWorkflow } from '$server/store/store';
import type { UpdateWorkflowInput } from '$lib/types';

export async function GET({ params }: { params: { id: string } }) {
	const wf = getWorkflow(params.id);
	if (!wf) return json({ error: 'Workflow nicht gefunden.' }, { status: 404 });
	return json(wf);
}

export async function PATCH({ params, request }: { params: { id: string }; request: Request }) {
	const body = (await request.json().catch(() => ({}))) as UpdateWorkflowInput;
	const wf = updateWorkflow(params.id, body);
	if (!wf) return json({ error: 'Workflow nicht gefunden.' }, { status: 404 });
	return json(wf);
}

export async function DELETE({ params }: { params: { id: string } }) {
	const ok = deleteWorkflow(params.id);
	if (!ok) return json({ error: 'Workflow nicht gefunden.' }, { status: 404 });
	return json({ ok: true });
}
