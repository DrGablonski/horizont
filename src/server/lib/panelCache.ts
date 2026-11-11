// Kurzzeit-Cache (TTL) für die teuer gebauten Panel-Antworten (Haupt/Archiv).
// Die CalDAV-Abfragen (v. a. Aufgaben-Listen: PROPFIND + GET pro Objekt)
// dominieren die Ladezeit mit mehreren hundert ms. Fertige Antworten werden
// kurz behalten; jede Schreiboperation (Events/Tasks/Verbindungen/Kalender-
// prefs/Kategorien) verwirft den Cache sofort — nach Änderungen gibt es nie
// veraltete Daten. Concurrente Requests auf denselben Key teilen sich zudem
// denselben Aufbau (Single-Flight), z. B. App-Start mit prefetch + Sections-Task.

const TTL_MS = 20_000;

interface Entry {
	promise: Promise<unknown>;
	expiresAt: number;
	/** Cache-Generation zum Zeitpunkt des Aufbaus (siehe invalidatePanelCache). */
	gen: number;
}

const cache = new Map<string, Entry>();

// Cache-Generation: jede Invalidierung erhöht sie; Einträge älterer Generatio-
// nen gelten nicht mehr als Treffer. So verwerfen z. B. Wechsel der Kalender-
// Sichtbarkeit alle Panels zuverlässig — auch laufende Aufbauten, die vor der
// Änderung gestartet wurden, werden danach nicht mehr weitergereicht.
let generation = 0;

export function cached<T>(key: string, build: () => Promise<T>): Promise<T> {
	const now = Date.now();
	const hit = cache.get(key);
	if (hit && hit.expiresAt > now && hit.gen === generation) return hit.promise as Promise<T>;

	// Alte Einträge (abgelaufen oder aus invalidierter Generation) beim
	// Schreiben mit entfernen, damit der Cache nicht wächst.
	for (const [k, e] of cache) {
		if (e.gen !== generation || e.expiresAt <= now) cache.delete(k);
	}

	const promise = build();
	// Synchron vor dem ersten await ablegen → Single-Flight für parallele Aufrufer.
	cache.set(key, { promise, expiresAt: now + TTL_MS, gen: generation });
	// Fehlgeschlagene Aufbauten nicht einfrieren → beim nächsten Aufruf neu.
	promise.catch(() => {
		const e = cache.get(key);
		if (e && e.promise === promise) cache.delete(key);
	});
	return promise;
}

export function invalidatePanelCache(): void {
	generation += 1;
}
