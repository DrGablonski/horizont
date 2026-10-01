import { json } from '@sveltejs/kit';
import { buildArchiveResponse, buildMainResponse } from '$server/lib/panels';
import { getSettings } from '$server/store/store';

export async function GET({ url }: { url: URL }) {
	const scope = url.searchParams.get('scope') ?? 'main';
	if (scope === 'archive') {
		const page = Number(url.searchParams.get('page') ?? '1');
		return json(await buildArchiveResponse(getSettings(), page));
	}
	return json(await buildMainResponse(getSettings()));
}
