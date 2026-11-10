import Foundation
import Observation

/// Datenhaltung für Start-, Archiv- und Workflow-Screens.
/// Mutationen (Abhaken, Schritt fortgeschritten) optimistisch + Rollback bei Fehler.
@MainActor
@Observable
final class AppStore {
	private let client: APIClient

	// Start
	var home: MainEventsResponse?
	var homeError: String?
	var homeBusy = false

	// Archiv
	var archive: ArchiveMonth?
	var archiveError: String?
	var archiveBusy = false

	// Workflows
	var workflows: [Workflow] = []
	var workflowsError: String?
	var workflowsBusy = false

	// Kalender (für Einstellungen + Task-Dialog)
	var calendars: [CalDavCalendar] = []
	var calendarsLoaded = false

	// Kategorien
	var categories: [TaskCategory] = []

	// Einstellungen
	var connections: [ConnectionView] = []
	var notify: NotifyConfigView?

	// API-Token (Einstellungen „API-Zugang")
	var apiToken: ApiTokenView?
	/// Klartext des zuletzt erzeugten Tokens – wird nur einmal angezeigt.
	var newApiToken: String?

	private let serverBase: String
	private var prefetchStarted = false

	init(client: APIClient) {
		self.client = client
		self.serverBase = client.baseURL.absoluteString
		loadSnapshots()
	}

	// MARK: – Snapshot (sofortiger Start aus lokalen Dateien)

	/// Zuerst geladene Antworten von der Disk laden → Views zeigen beim Start
	/// sofort Inhalte, prefetchIfNeeded aktualisiert sie im Hintergrund.
	private func loadSnapshots() {
		home = SnapshotStore.load(MainEventsResponse.self, name: "home", serverBase: serverBase)
		archive = SnapshotStore.load(ArchiveMonth.self, name: "archive", serverBase: serverBase)
		workflows = SnapshotStore.load([Workflow].self, name: "workflows", serverBase: serverBase) ?? []
		calendars = SnapshotStore.load([CalDavCalendar].self, name: "calendars", serverBase: serverBase) ?? []
		categories = SnapshotStore.load([TaskCategory].self, name: "categories", serverBase: serverBase) ?? []
	}

	private func saveSnapshot<T: Encodable>(_ value: T, name: String) {
		SnapshotStore.save(value, name: name, serverBase: serverBase)
	}

	/// Alle Bereiche einmal parallel laden (einmal pro App-Lebenszeit).
	/// Läuft nach dem Login; dank Snapshots sind die Views derweil schon gefüllt.
	func prefetchIfNeeded() async {
		guard !prefetchStarted else { return }
		prefetchStarted = true
		await withTaskGroup(of: Void.self) { group in
			group.addTask { await self.loadHome() }
			group.addTask { await self.loadArchive() }
			group.addTask { await self.loadWorkflows() }
			group.addTask { await self.loadCalendars() }
			group.addTask { await self.loadCategories() }
		}
	}

	// MARK: – Start

	func loadHome() async {
		homeBusy = true
		defer { homeBusy = false }
		do {
			home = try await client.mainEvents()
			homeError = home?.error
			if let home { saveSnapshot(home, name: "home") }
		} catch {
			homeError = error.localizedDescription
		}
	}

	/// Task anlegen und Timeline neu laden. Fehler als String zurück (Dialog zeigt ihn).
	func createTask(summary: String, calendarId: String, category: String?, dueKey: String?) async -> String? {
		do {
			_ = try await client.createTask(summary: summary, calendarId: calendarId,
			                                category: category, dueKey: dueKey)
			await loadHome()
			return nil
		} catch {
			return error.localizedDescription
		}
	}

	/// Termin anlegen und Timeline neu laden. Fehler als String zurück.
	func createEvent(summary: String, calendarId: String, dayKey: String,
	                 allDay: Bool, startMs: Int?) async -> String? {
		do {
			_ = try await client.createEvent(summary: summary, calendarId: calendarId,
			                                dayKey: dayKey, allDay: allDay, startMs: startMs)
			await loadHome()
			return nil
		} catch {
			return error.localizedDescription
		}
	}

	/// Task bearbeiten und Timeline neu laden. Fehler als String zurück.
	func updateTaskEdit(_ event: EventItem, summary: String, category: String?,
	                    dueKey: String?, clearDue: Bool, clearCategory: Bool) async -> String? {
		// Doppel-Optional: outer nil = unverändert, .some(inner) = explizit setzen (inner nil = entfernen).
		var catChange: String?? = nil
		if clearCategory { catChange = .some(nil) }
		else if category != event.category { catChange = .some(category) }
		var dueChange: String?? = nil
		if clearDue { dueChange = .some(nil) }
		else if dueKey != event.dueKey { dueChange = .some(dueKey) }

		do {
			_ = try await client.updateTask(
				calendarId: event.calendarId, uid: event.uid, summary: summary,
				category: catChange, dueKey: dueChange)
			await loadHome()
			return nil
		} catch {
			return error.localizedDescription
		}
	}

	/// Termin bearbeiten und Timeline neu laden. Fehler als String zurück.
	func updateEventEdit(_ event: EventItem, summary: String, allDay: Bool,
	                     dayKey: String, startMs: Int?, location: String?) async -> String? {
		do {
			_ = try await client.updateEvent(
				calendarId: event.calendarId, uid: event.uid, summary: summary,
				allDay: allDay, dayKey: dayKey,
				startMs: allDay ? nil : startMs, endMs: nil,
				location: location)
			await loadHome()
			return nil
		} catch {
			return error.localizedDescription
		}
	}

	/// Event/Task löschen (optimistisch; bei Fehler Neu laden).
	func deleteItem(_ event: EventItem) async {
		guard var panels = home?.panels else { return }
		guard let loc = findEvent(event.id, in: &panels) else { return }
		panels[loc.panel].days[loc.day].events.remove(at: loc.item)
		home?.panels = panels

		do {
			if event.kind == "task" {
				try await client.deleteTask(calendarId: event.calendarId, uid: event.uid)
			} else {
				try await client.deleteEvent(calendarId: event.calendarId, uid: event.uid)
			}
		} catch {
			homeError = error.localizedDescription
		}
		await loadHome()
	}

	/// Task in den Timeline-Panels abhaken/anaken (optimistisch).
	func toggleTask(_ event: EventItem) async {
		guard var panels = home?.panels else { return }
		let newValue = !(event.completed ?? false)
		guard let loc = findEvent(event.id, in: &panels) else { return }
		panels[loc.panel].days[loc.day].events[loc.item].completed = newValue
		home?.panels = panels

		do {
			try await client.updateTaskCompleted(
				calendarId: event.calendarId, uid: event.uid, completed: newValue)
			if let home { saveSnapshot(home, name: "home") }
		} catch {
			// Rollback
			if var p = home?.panels, let l = findEvent(event.id, in: &p) {
				p[l.panel].days[l.day].events[l.item].completed = !newValue
				home?.panels = p
			}
			homeError = error.localizedDescription
		}
	}

	private struct EventLocation { let panel: Int; let day: Int; let item: Int }

	private func findEvent(_ id: String, in panels: inout [TimePanel]) -> EventLocation? {
		for p in panels.indices {
			for d in panels[p].days.indices {
				if let i = panels[p].days[d].events.firstIndex(where: { $0.id == id }) {
					return EventLocation(panel: p, day: d, item: i)
				}
			}
		}
		return nil
	}

	// MARK: – Archiv

	func loadArchive(monthKey: String? = nil) async {
		archiveBusy = true
		defer { archiveBusy = false }
		do {
			archive = try await client.archiveMonth(monthKey)
			archiveError = archive?.error
			if let archive { saveSnapshot(archive, name: "archive") }
		} catch {
			archiveError = error.localizedDescription
		}
	}

	// MARK: – Workflows

	func loadWorkflows() async {
		workflowsBusy = true
		defer { workflowsBusy = false }
		do {
			workflows = try await client.workflows()
			workflowsError = nil
			saveSnapshot(workflows, name: "workflows")
		} catch {
			workflowsError = error.localizedDescription
		}
	}

	func workflow(_ id: String) -> Workflow? {
		workflows.first { $0.id == id }
	}

	func toggleStep(workflowId: String, stepId: String) async {
		guard let wf = workflow(workflowId),
		      let step = wf.steps.first(where: { $0.id == stepId }) else { return }
		do {
			let updated = try await client.updateStep(
				workflowId: workflowId, stepId: stepId, done: !step.done)
			if let i = workflows.firstIndex(where: { $0.id == workflowId }) {
				workflows[i] = updated
			}
		} catch {
			workflowsError = error.localizedDescription
		}
	}

	func resetWorkflow(_ id: String) async {
		do {
			let updated = try await client.resetWorkflow(workflowId: id)
			replaceWorkflow(updated)
		} catch {
			workflowsError = error.localizedDescription
		}
	}

	/// Workflow anlegen; Erfolg = nil, sonst Fehlertext (Dialog zeigt ihn).
	func createWorkflow(title: String, steps: [String]) async -> String? {
		do {
			_ = try await client.createWorkflow(title: title, steps: steps)
			await loadWorkflows()
			return nil
		} catch {
			return error.localizedDescription
		}
	}

	/// Titel/Notizen ändern; Erfolg = nil, sonst Fehlertext.
	func updateWorkflowEdit(_ wf: Workflow, title: String, notes: String) async -> String? {
		do {
			replaceWorkflow(try await client.updateWorkflow(workflowId: wf.id,
			                                             title: title, notes: notes))
			return nil
		} catch {
			return error.localizedDescription
		}
	}

	/// Workflow löschen (optimistisch; bei Fehler neu laden).
	func deleteWorkflow(_ id: String) async {
		workflows.removeAll { $0.id == id }
		do {
			try await client.deleteWorkflow(workflowId: id)
		} catch {
			workflowsError = error.localizedDescription
			await loadWorkflows()
		}
	}

	/// Schritt anhängen; Erfolg = nil, sonst Fehlertext.
	func addStep(workflowId: String, title: String) async -> String? {
		do {
			replaceWorkflow(try await client.addStep(workflowId: workflowId, title: title))
			return nil
		} catch {
			return error.localizedDescription
		}
	}

	/// Schritt umbenennen; Erfolg = nil, sonst Fehlertext.
	func renameStep(workflowId: String, stepId: String, title: String) async -> String? {
		do {
			replaceWorkflow(try await client.setStepTitle(
				workflowId: workflowId, stepId: stepId, title: title))
			return nil
		} catch {
			return error.localizedDescription
		}
	}

	/// Schritt löschen; Erfolg = nil, sonst Fehlertext.
	func deleteStep(workflowId: String, stepId: String) async -> String? {
		do {
			replaceWorkflow(try await client.deleteStep(
				workflowId: workflowId, stepId: stepId))
			return nil
		} catch {
			return error.localizedDescription
		}
	}

	/// Aktualisierte Antwort (enthält immer den ganzen Workflow) an Stelle des alten einfügen.
	private func replaceWorkflow(_ wf: Workflow) {
		if let i = workflows.firstIndex(where: { $0.id == wf.id }) {
			workflows[i] = wf
		} else {
			workflows.insert(wf, at: 0)
		}
	}

	// MARK: – Kalender / Kategorien

	func loadCalendars() async {
		do {
			let r = try await client.calendars()
			calendars = r.calendars
			saveSnapshot(calendars, name: "calendars")
		} catch {}
		calendarsLoaded = true
	}

	func loadCategories() async {
		do {
			categories = try await client.categories()
			saveSnapshot(categories, name: "categories")
		} catch {}
	}

	/// Ganze Kategorie-Liste ersetzen (wie Web-App); Erfolg = nil, sonst Fehlertext.
	func saveCategories(_ cats: [TaskCategory]) async -> String? {
		do {
			categories = try await client.saveCategories(cats)
			saveSnapshot(categories, name: "categories")
			return nil
		} catch {
			return error.localizedDescription
		}
	}

	// MARK: – Einstellungen

	func loadConnections() async {
		do {
			connections = try await client.connections().connections
		} catch {}
	}

	func testConnection(id: String) async -> TestResult? {
		try? await client.testConnection(id: id)
	}

	/// Ungespeicherte Formularwerte testen (ohne zu speichern).
	func testConnection(url: String, username: String, password: String) async -> TestResult? {
		try? await client.testConnection(url: url, username: username, password: password)
	}

	/// Verbindung anlegen; Erfolg = nil, sonst Fehlertext. Lädt Kalender nach (neue Quellen).
	func createConnection(name: String, url: String, username: String,
	                      password: String) async -> String? {
		do {
			connections = try await client.createConnection(
				name: name, url: url, username: username, password: password).connections
			await loadCalendars()
			return nil
		} catch {
			return error.localizedDescription
		}
	}

	/// Verbindung ändern; leeres Passwort = gespeichertes behalten. Erfolg = nil, sonst Fehlertext.
	func updateConnection(id: String, name: String, url: String,
	                      username: String, password: String) async -> String? {
		do {
			connections = try await client.updateConnection(
				id: id, name: name, url: url, username: username,
				password: password.isEmpty ? nil : password).connections
			await loadCalendars()
			return nil
		} catch {
			return error.localizedDescription
		}
	}

	/// Verbindung löschen; Erfolg = nil, sonst Fehlertext.
	func deleteConnection(id: String) async -> String? {
		do {
			connections = try await client.deleteConnection(id: id).connections
			await loadCalendars()
			return nil
		} catch {
			return error.localizedDescription
		}
	}

	func loadNotify() async {
		do {
			notify = try await client.notifyConfig()
		} catch {}
	}

	/// Notify-Konfiguration speichern; leeres token = gespeicherten Wert behalten.
	/// Erfolg = nil, sonst Fehlertext.
	func saveNotify(frequency: NotifyFrequency, time: String, weekday: Int,
	                intervalHours: Int, url: String, token: String, prompt: String,
	                categories: [String]) async -> String? {
		var body: [String: Any] = [
			"frequency": frequency.rawValue,
			"time": time,
			"weekday": weekday,
			"intervalHours": intervalHours,
			"url": url,
			"prompt": prompt,
			"categories": categories
		]
		if !token.isEmpty { body["token"] = token }
		do {
			notify = try await client.saveNotifyConfig(body)
			return nil
		} catch {
			return error.localizedDescription
		}
	}

	/// Testversand mit Formularwerten (leer = gespeicherte Config); Fehler landen im Ergebnis.
	func sendNotifyTest(url: String = "", token: String = "",
	                    prompt: String = "") async -> NotifyTestResult {
		do {
			return try await client.sendNotifyTest(url: url, token: token, prompt: prompt)
		} catch {
			return NotifyTestResult(ok: false, error: error.localizedDescription)
		}
	}

	/// „Jetzt senden": echte offene Tasks verschicken; danach Lauf-Status neu laden.
	func sendNotifyNow() async -> NotifySendResult {
		do {
			let result = try await client.sendNotifyNow()
			await loadNotify()
			return result
		} catch {
			return NotifySendResult(ok: false, error: error.localizedDescription)
		}
	}

	// MARK: – API-Token

	func loadApiToken() async {
		do {
			apiToken = try await client.apiToken()
		} catch {}
	}

	/// Neuen Token erzeugen (Klartext landet in newApiToken); Erfolg = nil, sonst Fehlertext.
	func generateApiToken() async -> String? {
		do {
			let r = try await client.generateApiToken()
			newApiToken = r.token
			await loadApiToken()
			return nil
		} catch {
			return error.localizedDescription
		}
	}

	/// Token ablehnen; Erfolg = nil, sonst Fehlertext.
	func revokeApiToken() async -> String? {
		do {
			try await client.revokeApiToken()
			newApiToken = nil
			await loadApiToken()
			return nil
		} catch {
			return error.localizedDescription
		}
	}
}
