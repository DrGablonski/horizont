// Prioritäts-Buckets (CalDAV priority 1–9 → drei Stufen wie im TaskEditor):
// 1–2 = Hoch, 3–7 = Schule, 8–9 = Niedrig.

export type PriorityBucket = 1 | 5 | 9;

/** Die drei wählbaren Prioritäts-Stufen (Repräsentant-Werte). */
export const PRIORITY_BUCKETS: readonly PriorityBucket[] = [1, 5, 9];

/** Rechen CalDAV-Priorität (1–9) ihrem Bucket-Repräsentanten zu. */
export function priorityBucket(p: number): PriorityBucket {
	if (p <= 2) return 1;
	if (p >= 8) return 9;
	return 5;
}

/** Deutsches Label für einen Bucket (1=Hoch, 5=Schule, 9=Niedrig). */
export function priorityBucketLabel(b: PriorityBucket): string {
	if (b === 1) return 'Hoch';
	if (b === 9) return 'Niedrig';
	return 'Schule';
}
