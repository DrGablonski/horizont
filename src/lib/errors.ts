/** Menschlich lesbare Fehlermeldung aus einem beliebigen Fehlerwert (z. B. aus catch). */
export function errMsg(e: unknown): string {
	if (e instanceof Error && e.message) return e.message;
	if (typeof e === 'string' && e) return e;
	return 'Unbekannter Fehler';
}
