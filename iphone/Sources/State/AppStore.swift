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

	// Kalender (für Einstellungen, Kalender-Chips + Task-/Termin-Dialog)
	var calendars: [CalendarView] = []
	var calendarsLoaded = false
	var calendarsError: String?

	// Kategorien
	var categories: [TaskCategory] = []

	// Einstellungen
	var connections: [ConnectionView] = []
	var providerPresets: [ProviderPreset] = []
	var notify: NotifyConfigView?

	init(client: APIClient) {
		self.client = client
	}

	// MARK: – Start

	func loadHome() async {
		homeBusy = true
		defer { homeBusy = false }
		do {
			home = try await client.mainEvents()
			homeError = home?.error
			// Widgets (Home-Screen/Sperrbildschirm) mit frischem Stand versorgen.
			if let home { WidgetSnapshotSupport.publish(home) }
		} catch {
			homeError = error.localizedDescription
		}
	}

	// MARK: – Schreibziel

	/// Bevorzugtes Schreibziel für Schnellanlagen: Standardkalender, sonst der
	/// erste beschreibbare Kalender. nil ⇒ der Server wählt selbst.
	var preferredWriteCalendarId: String? {
		let writable = calendars.filter(\.writable)
		return writable.first(where: \.isDefault)?.id ?? writable.first?.id
	}

	/// Task anlegen und Timeline neu laden. Fehler als String zurück (Dialog zeigt ihn).
	/// calendarId = nil ⇒ der Server wählt das Standardziel (Standardkalender).
	/// Veraltete Auswahl (Kalender gelöscht/anderer Hash) ⇒ ein Versuch ohne id.
	func createTask(summary: String, calendarId: String?, category: String?, dueKey: String?) async -> String? {
		let failure = await postTask(summary: summary, calendarId: calendarId, category: category, dueKey: dueKey)
		if let failure, calendarId != nil, failure.contains("Kalender nicht gefunden") {
			return await postTask(summary: summary, calendarId: nil, category: category, dueKey: dueKey)
		}
		return failure
	}

	private func postTask(summary: String, calendarId: String?, category: String?, dueKey: String?) async -> String? {
		var body: [String: Any] = ["summary": summary]
		if let calendarId { body["calendarId"] = calendarId }
		if let category { body["category"] = category }
		if let dueKey { body["due"] = ["kind": "date", "key": dueKey] }
		do {
			_ = try await postItem("/api/tasks", body: body)
			await loadHome()
			return nil
		} catch {
			return error.localizedDescription
		}
	}

	/// Termin anlegen und Timeline neu laden. Fehler als String zurück.
	/// calendarId = nil ⇒ der Server wählt das Standardziel (Standardkalender).
	/// Bei Uhrzeit erwartet der Server zwingend eine Endzeit ⇒ Standard 1 Stunde.
	func createEvent(summary: String, calendarId: String?, dayKey: String,
	                 allDay: Bool, startMs: Int?) async -> String? {
		let failure = await postEvent(summary: summary, calendarId: calendarId, dayKey: dayKey,
		                              allDay: allDay, startMs: startMs)
		if let failure, calendarId != nil, failure.contains("Kalender nicht gefunden") {
			return await postEvent(summary: summary, calendarId: nil, dayKey: dayKey,
			                       allDay: allDay, startMs: startMs)
		}
		return failure
	}

	private func postEvent(summary: String, calendarId: String?, dayKey: String,
	                       allDay: Bool, startMs: Int?) async -> String? {
		var body: [String: Any] = ["summary": summary, "dayKey": dayKey, "allDay": allDay]
		if let calendarId { body["calendarId"] = calendarId }
		if let startMs {
			body["startMs"] = startMs
			body["endMs"] = startMs + 3_600_000   // Standarddauer 1 Stunde
		}
		do {
			_ = try await postItem("/api/events", body: body)
			await loadHome()
			return nil
		} catch {
			return error.localizedDescription
		}
	}

	/// POST mit JSON-Body, decodiert das angelegte Event.
	/// (Eigener Body-Aufbau, damit calendarId beim Anlegen fehlen darf.)
	private func postItem(_ path: String, body: [String: Any]) async throws -> EventItem {
		let data = try await client.raw(path, method: "POST", body: body)
		return try JSONDecoder().decode(EventItem.self, from: data)
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
		} catch {
			// Rollback
			if var p = home?.panels, let l = findEvent(event.id, in: &p) {
				p[l.panel].days[l.day].events[l.item].completed = !newValue
				home?.panels = p
			}
			homeError = error.localizedDescription
		}
		// Widgets spiegeln den neuen Erledigt-Stand (lokale Mutation, kein loadHome).
		if let home { WidgetSnapshotSupport.publish(home) }
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
			let r = try await client.fetchCalendars()
			calendars = r.calendars
			// Fehler einzelner Verbindungen blockieren den Rest nicht – als Text zeigen.
			calendarsError = r.errors.isEmpty ? nil : r.errors.joined(separator: " · ")
		} catch {
			calendarsError = error.localizedDescription
		}
		calendarsLoaded = true
	}

	/// Sichtbarkeit schalten (PATCH hidden) und Timeline neu laden – Panels ändern sich mit.
	func toggleCalendarVisibility(_ id: String) async {
		guard let cal = calendars.first(where: { $0.id == id }) else { return }
		do {
			_ = try await client.updateCalendar(id: id, patch: ["hidden": !cal.hidden])
			await loadCalendars()
			await loadHome()
		} catch {
			calendarsError = error.localizedDescription
		}
	}

	/// Standardkalender setzen (entwertet den bisherigen); Kalenderliste neu laden.
	func setDefaultCalendar(_ id: String) async {
		do {
			_ = try await client.updateCalendar(id: id, patch: ["isDefault": true])
			await loadCalendars()
		} catch {
			calendarsError = error.localizedDescription
		}
	}

	/// Kalender patchen (Name/Farbe/Schreibschutz); Erfolg = nil, sonst Fehlertext.
	func updateCalendarEdit(_ id: String, patch: [String: Any]) async -> String? {
		do {
			_ = try await client.updateCalendar(id: id, patch: patch)
			await loadCalendars()
			return nil
		} catch {
			return error.localizedDescription
		}
	}

	/// Kalender per MKCALENDAR anlegen; Erfolg = nil, sonst Fehlertext (Sheet zeigt ihn).
	func createCalendar(connectionId: String, name: String, color: String) async -> String? {
		do {
			_ = try await client.createCalendar(connectionId: connectionId, name: name, color: color)
			await loadCalendars()
			return nil
		} catch {
			return error.localizedDescription
		}
	}

	/// Kalender löschen (name = Tipp-Bestätigung, muss exakt passen); Timeline neu laden.
	func deleteCalendar(_ id: String, name: String) async -> String? {
		do {
			try await client.deleteCalendar(id: id, name: name)
			await loadCalendars()
			await loadHome()
			return nil
		} catch {
			return error.localizedDescription
		}
	}

	func loadCategories() async {
		do {
			categories = try await client.categories()
		} catch {}
	}

	// MARK: – Einstellungen

	func loadConnections() async {
		do {
			connections = try await client.connections().connections
		} catch {}
	}

	/// Anbieter-Vorlagen für das Anlegen/Bearbeiten von Verbindungen (Referenz-Texte).
	func loadProviderPresets() async {
		do {
			providerPresets = try await client.providerPresets()
		} catch {}
	}

	/// Hauptverbindung setzen (Rollenwechsel); Erfolg = nil, sonst Fehlertext.
	func setPrimaryConnection(_ id: String) async -> String? {
		do {
			_ = try await client.setPrimaryConnection(id: id)
			await loadConnections()
			await loadCalendars()
			return nil
		} catch {
			return error.localizedDescription
		}
	}

	func testConnection(id: String) async -> TestResult? {
		try? await client.testConnection(id: id)
	}

	func loadNotify() async {
		do {
			notify = try await client.notifyConfig()
		} catch {}
	}

	/// Notify-Konfiguration speichern; Erfolg = nil, sonst Fehlertext.
	func saveNotify(frequency: NotifyFrequency, time: String, weekday: Int,
	                intervalHours: Int, url: String, prompt: String,
	                categories: [String]) async -> String? {
		let body: [String: Any] = [
			"frequency": frequency.rawValue,
			"time": time,
			"weekday": weekday,
			"intervalHours": intervalHours,
			"url": url,
			"prompt": prompt,
			"categories": categories
		]
		do {
			notify = try await client.saveNotifyConfig(body)
			return nil
		} catch {
			return error.localizedDescription
		}
	}

	/// Testversand mit den aktuellen Formularwerten (leer = gespeicherte Config); Erfolg = nil.
	func sendNotifyTest(url: String = "", prompt: String = "") async -> String? {
		do {
			_ = try await client.sendNotifyTest(url: url, prompt: prompt)
			return nil
		} catch {
			return error.localizedDescription
		}
	}
}
