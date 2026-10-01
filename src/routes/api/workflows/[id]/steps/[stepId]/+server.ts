import { json } from '@sveltejs/kit';
import { deleteStep, updateStep } from '$server/store/store';
import type { UpdateStepInput } from '$lib/types';

export async function PATCH({
	params,
	request
}: {
	params: { id: string; stepId: string };
	request: Request;
}) {
	const body = (await request.json().catch(() => ({}))) as UpdateStepInput;
	const wf = updateStep(params.id, params.stepId, body);
	if (!wf) return json({ error: 'Workflow nicht gefunden.' }, { status: 404 });
	return json(wf);
}

export async function DELETE({ params }: { params: { id: string; stepId: string } }) {
	const wf = deleteStep(params.id, params.stepId);
	if (!wf) return json({ error: 'Workflow nicht gefunden.' }, { status: 404 });
	return json(wf);
}
