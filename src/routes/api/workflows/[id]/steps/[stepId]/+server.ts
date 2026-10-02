import { json } from '@sveltejs/kit';
import { deleteStep, updateStep } from '$server/store/store';
import { mapError } from '$server/lib/workflowErrors';
import type { UpdateStepInput } from '$lib/types';

export async function PATCH({
	params,
	request
}: {
	params: { id: string; stepId: string };
	request: Request;
}) {
	try {
		const body = (await request.json().catch(() => ({}))) as UpdateStepInput;
		const wf = await updateStep(params.id, params.stepId, body);
		if (!wf) return json({ error: 'Workflow nicht gefunden.' }, { status: 404 });
		return json(wf);
	} catch (err) {
		const e = mapError(err);
		return json({ error: e.message }, { status: e.status });
	}
}

export async function DELETE({ params }: { params: { id: string; stepId: string } }) {
	try {
		const wf = await deleteStep(params.id, params.stepId);
		if (!wf) return json({ error: 'Workflow nicht gefunden.' }, { status: 404 });
		return json(wf);
	} catch (err) {
		const e = mapError(err);
		return json({ error: e.message }, { status: e.status });
	}
}
