import { json } from '@sveltejs/kit';
import { createWorkflow, listWorkflows } from '$server/store/store';
import { mapError } from '$server/lib/workflowErrors';
import type { CreateWorkflowInput } from '$lib/types';

export async function GET() {
	try {
		return json(await listWorkflows());
	} catch (err) {
		const e = mapError(err);
		return json({ error: e.message }, { status: e.status });
	}
}

export async function POST({ request }: { request: Request }) {
	try {
		const body = (await request.json().catch(() => ({}))) as Partial<CreateWorkflowInput>;
		const wf = await createWorkflow({ title: body.title ?? '', steps: body.steps ?? [] });
		return json(wf, { status: 201 });
	} catch (err) {
		const e = mapError(err);
		return json({ error: e.message }, { status: e.status });
	}
}
