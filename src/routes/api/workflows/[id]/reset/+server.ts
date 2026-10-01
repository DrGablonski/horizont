import { json } from '@sveltejs/kit';
import { resetWorkflow } from '$server/store/store';

export async function POST({ params }: { params: { id: string } }) {
	const wf = resetWorkflow(params.id);
	if (!wf) return json({ error: 'Workflow nicht gefunden.' }, { status: 404 });
	return json(wf);
}
