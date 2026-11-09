// Kurzzeit-Cache (TTL) für die teuer gebauten Panel-Antworten (Haupt/Archiv).
// Die CalDAV-Abfragen (v. a. Aufgaben-Listen: PROPFIND + GET pro Objekt)
// dominieren die Ladezeit mit mehreren hundert ms. Fertige Antworten werden
// kurz behalten; jede Schreiboperation (Events/Tasks/Verbindungen/Kategorien)
// verwirft den Cache sofort — nach Änderungen gibt es nie veraltete Daten.
// Concurrente Requests auf denselben Key teilen sich zudem denselben Aufbau
// (Single-Flight), z. B. App-Start mit prefetch + Sections-Task.

const TTL_MS = 20_000;

interface Entry {
	promise: Promise<unknown>;
	expiresAt: number;
}

const cache = new Map<string, Entry>();

export function cached<T>(key: string, build: () => Promise<T>): Promise<T> {
	const now = Date.now();
	const hit = cache.get(key);
	if (hit && hit.expiresAt > now) return hit.promise as Promise<T>;

	const promise = build();
	cache.set(key, { promise, expiresAt: now + TTL_MS });
	// Fehlgeschlagene Aufbauten nicht einfrieren → beim nächsten Aufruf neu.
	promise.catch(() => {
		const e = cache.get(key);
		if (e && e.promise === promise) cache.delete(key);
	});
	return promise;
}

export function invalidatePanelCache(): void {
	cache.clear();
}
