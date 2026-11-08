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
			if let i = workflows.firstIndex(where: { $0.id == id }) {
				workflows[i] = updated
			}
		} catch {
			workflowsError = error.localizedDescription
		}
	}

	// MARK: – Kalender / Kategorien

	func loadCalendars() async {
		do {
			let r = try await client.calendars()
			calendars = r.calendars
		} catch {}
		calendarsLoaded = true
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
