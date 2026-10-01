import { json } from '@sveltejs/kit';
import { addStep } from '$server/store/store';

export async function POST({ params, request }: { params: { id: string }; request: Request }) {
	const body = (await request.json().catch(() => ({}))) as { title?: string };
	const wf = addStep(params.id, body.title ?? '');
	if (!wf) return json({ error: 'Workflow nicht gefunden.' }, { status: 404 });
	return json(wf, { status: 201 });
}
