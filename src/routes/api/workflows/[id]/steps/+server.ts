import { json } from '@sveltejs/kit';
import { addStep } from '$server/store/store';
import { mapError } from '$server/lib/workflowErrors';

export async function POST({ params, request }: { params: { id: string }; request: Request }) {
	try {
		const body = (await request.json().catch(() => ({}))) as { title?: string };
		const wf = await addStep(params.id, body.title ?? '');
		if (!wf) return json({ error: 'Workflow nicht gefunden.' }, { status: 404 });
		return json(wf, { status: 201 });
	} catch (err) {
		const e = mapError(err);
		return json({ error: e.message }, { status: e.status });
	}
}
