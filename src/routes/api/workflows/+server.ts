import { json } from '@sveltejs/kit';
import { createWorkflow, listWorkflows } from '$server/store/store';
import type { CreateWorkflowInput } from '$lib/types';

export function GET() {
	return json(listWorkflows());
}

export async function POST({ request }: { request: Request }) {
	const body = (await request.json().catch(() => ({}))) as Partial<CreateWorkflowInput>;
	const wf = createWorkflow({ title: body.title ?? '', steps: body.steps ?? [] });
	return json(wf, { status: 201 });
}
