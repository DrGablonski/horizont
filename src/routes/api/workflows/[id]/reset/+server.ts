import { json } from '@sveltejs/kit';
import { resetWorkflow } from '$server/store/store';
import { mapError } from '$server/lib/workflowErrors';

export async function POST({ params }: { params: { id: string } }) {
	try {
		const wf = await resetWorkflow(params.id);
		if (!wf) return json({ error: 'Workflow nicht gefunden.' }, { status: 404 });
		return json(wf);
	} catch (err) {
		const e = mapError(err);
		return json({ error: e.message }, { status: e.status });
	}
}
