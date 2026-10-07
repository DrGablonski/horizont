// Leichtes Rate-Limiting für die Agent-Endpunkte (in-memory, pro IP):
// LLM-Aufrufe kosten Geld/Zeit, daher deutlich locker als das Auth-Limit,
// aber mit Deckel gegen Missbrauch.

const WINDOW_MS = 60_000;
const MAX = 20;

const hits = new Map<string, { count: number; resetAt: number }>();

export function agentRateLimited(ip: string): boolean {
	const now = Date.now();
	const rec = hits.get(ip);
	if (!rec || rec.resetAt <= now) {
		hits.set(ip, { count: 1, resetAt: now + WINDOW_MS });
		return false;
	}
	rec.count += 1;
	if (rec.count > MAX) return true;
	// gelegentlich räumen, damit die Map nicht wächst
	if (hits.size > 500) {
		for (const [k, v] of hits) {
			if (v.resetAt <= now) hits.delete(k);
		}
	}
	return false;
}
