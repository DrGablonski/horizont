import Foundation
import Observation

/// Prüft regelmäßig Termine und Aufgaben und schickt dazu die
/// macOS-Systemmeldungen (Einstellungen: Support/LocalNotifications.swift,
/// UI: Einstellungen → Mitteilungen → „Meldungen auf diesem Mac").
///
/// Läuft unabhängig vom Fenster: gestartet wird er in `AuthStore`, sobald eine
/// Session steht, und stoppt beim Abmelden.
@MainActor
@Observable
final class ReminderEngine {
	static let shared = ReminderEngine()

	/// Eigene Datenquelle – hängt an keinem View und überlebt geschlossene
	/// Fenster (genau wie der Store der Menuleiste).
	private var store: AppStore?
	private var loop: Task<Void, Never>?

	/// Für die Einstellungen sichtbar: letzter Prüfdurchlauf + letzte Meldung.
	private(set) var lastCheck: Date?
	private(set) var lastSendTitle: String?

	/// Prüfabstand: reicht für Minuten-Vorläufe, ohne den Server zu belasten.
	let tickSeconds: Double = 30
	/// Daten höchstens so alt lassen (jeder Abruf löst serverseitig CalDAV aus).
	private let dataTTL: TimeInterval = 180
	/// Terminmeldung noch bis 30 Min nach der Feuerzeit (Rechner kurz im Schlaf).
	private let eventGraceMs = 30 * 60_000
	/// Tagesplan/Überfällig noch bis 3 h nach der Sollzeit.
	private let digestGraceMs = 3 * 3_600_000

	private init() {}

	// MARK: – Lebenszyklus

	/// Startet den Prüflauf für diesen Server (vorherigen Lauf ersetzen).
	func start(client: APIClient) {
		stop()
		guard !AppLaunch.isQARun else { return }
		let local = AppStore(client: client)
		store = local
		NotifyLog.prune()
		lastSendTitle = NotifyLog.lastSent()?.title
		loop = Task { [weak self] in
			guard let self else { return }
			await Notifier.shared.ensurePermission()
			var lastLoad = Date.distantPast
			var ticks = 0
			while !Task.isCancelled {
				if Date().timeIntervalSince(lastLoad) >= self.dataTTL {
					await local.loadHome()
					lastLoad = Date()
				}
				self.check(now: Date())
				// Berechtigung kann der Nutzer jederzeit ändern → alle ~5 Min neu lesen.
				ticks += 1
				if ticks % 10 == 0 { await Notifier.shared.refresh() }
				try? await Task.sleep(nanoseconds: UInt64(self.tickSeconds * 1_000_000_000))
			}
		}
	}

	func stop() {
		loop?.cancel()
		loop = nil
		store = nil
	}

	// MARK: – Prüfdurchlauf

	/// Ein Durchlauf: welche Meldungen sind jetzt dran und noch nicht raus?
	private func check(now: Date) {
		defer { lastCheck = now }
		let s = MacNotifyStore.load()
		guard s.master, let home = store?.home else { return }
		let ms = Int(now.timeIntervalSince1970 * 1000)
		let todayKey = Fmt.dayKeyFormatter.string(from: now)
		let days = home.panels.flatMap(\.days)
		let all = days.flatMap(\.events)

		// 1) Erinnerung vor Terminbeginn
		if s.eventsOn {
			let leadMs = s.eventLead * 60_000
			for e in all where e.kind != "task" && !e.allDay && s.allows(calendar: e.calendarName) {
				let fireAt = e.startMs - leadMs
				guard ms >= fireAt, ms < e.endMs, ms - fireAt <= eventGraceMs else { continue }
				// Vorlauf in der ID: nach einer neuen Vorlauf-Einstellung darf
				// derselbe Termin noch einmal melden.
				let id = "ev:\(e.uid):\(e.startMs):\(s.eventLead)"
				guard !NotifyLog.fired(id) else { continue }
				fire(id: id,
				     title: (ms >= e.startMs ? "Läuft jetzt: " : "Gleich: ") + e.summary,
				     body: "\(Fmt.time(e.startMs)) · \(e.calendarName) · \(Self.remaining(ms: e.startMs - ms))",
				     sound: s.sound)
			}
		}

		// 2) Tagesplan zu fester Uhrzeit (einmal pro Tag)
		if s.dayPlanOn, let at = Self.millis(todayKey: todayKey, time: s.dayPlanTime),
		   ms >= at, ms - at <= digestGraceMs {
			let id = "plan:\(todayKey)"
			if !NotifyLog.fired(id), let msg = dayPlanMessage(days: days, todayKey: todayKey, s: s) {
				// Ohne Berechtigung nicht markieren → nächster Tick versucht es erneut.
				if !fire(id: id, title: msg.title, body: msg.body, sound: s.sound) { return }
			}
		}

		// 3) Überfällige Aufgaben zu fester Uhrzeit (einmal pro Tag)
		if s.overdueOn, let at = Self.millis(todayKey: todayKey, time: s.overdueTime),
		   ms >= at, ms - at <= digestGraceMs {
			let id = "overdue:\(todayKey)"
			// Leere Liste wird nicht markiert: wird später etwas überfällig,
			// darf die Meldung innerhalb des Zeitfensters noch kommen.
			if !NotifyLog.fired(id), let msg = overdueMessage(all, s: s) {
				fire(id: id, title: msg.title, body: msg.body, sound: s.sound)
			}
		}
	}

	/// Raus damit, Dedup-Merkzettel und „zuletzt"-Anzeige aktualisieren.
	/// Rückgabe: false = das System lehnt aktuell ab (Berechtigung).
	@discardableResult
	private func fire(id: String, title: String, body: String, sound: Bool) -> Bool {
		guard Notifier.shared.send(identifier: id, title: title, body: body, sound: sound) == nil else {
			return false      // Grund steht in Notifier.lastError
		}
		NotifyLog.markFired(id)
		NotifyLog.recordSent(title: title)
		lastSendTitle = title
		return true
	}

	// MARK: – Meldungen bauen

	/// Tagesplan: „Heute · 3 Termine · 5 Aufgaben" mit bis zu vier Zeilen.
	private func dayPlanMessage(days: [DayGroup], todayKey: String,
	                            s: MacNotifySettings) -> (title: String, body: String)? {
		let todays = days.filter { $0.isToday || $0.dayKey == todayKey }
		let all = todays.flatMap(\.events)
		let events = all.filter { $0.kind != "task" && s.allows(calendar: $0.calendarName) }
		let tasks = all.filter { $0.kind == "task" && $0.completed != true && s.allows(category: $0.category) }
		let label = todays.first?.label ?? "Heute"

		var lines: [String] = events.prefix(4).map {
			$0.allDay ? "ganztags · \($0.summary)" : "\(Fmt.time($0.startMs)) · \($0.summary)"
		}
		if events.count > 4 { lines.append("+ \(events.count - 4) weitere Termine") }
		if !tasks.isEmpty { lines.append("\(tasks.count) offene Aufgaben") }
		return (("\(label) · \(events.count) Termine · \(tasks.count) Aufgaben"),
		        lines.isEmpty ? "Nichts geplant." : lines.joined(separator: "\n"))
	}

	/// Hinweis auf überfällige Aufgaben; nil wenn nichts überfällig ist.
	private func overdueMessage(_ events: [EventItem],
	                            s: MacNotifySettings) -> (title: String, body: String)? {
		let list = events.filter {
			$0.kind == "task" && $0.completed != true && $0.overdue == true && s.allows(category: $0.category)
		}
		guard !list.isEmpty else { return nil }
		let lines = list.prefix(4).map { task -> String in
			guard let dueKey = task.dueKey else { return "• " + task.summary }
			return "• \(task.summary) · fällig \(Self.dueText(dueKey))"
		}
		var body = lines.joined(separator: "\n")
		if list.count > 4 { body += "\n+ \(list.count - 4) weitere" }
		return ((list.count == 1 ? "Eine Aufgabe überfällig" : "\(list.count) Aufgaben überfällig"), body)
	}

	/// Nächster anstehender Termin (für die Vorschau in den Einstellungen).
	private func nextEventMessage(_ events: [EventItem], now: Date,
	                              s: MacNotifySettings) -> (title: String, body: String)? {
		let ms = Int(now.timeIntervalSince1970 * 1000)
		let upcoming = events.filter {
			$0.kind != "task" && !$0.allDay && $0.startMs > ms && s.allows(calendar: $0.calendarName)
		}
		guard let next = upcoming.min(by: { $0.startMs < $1.startMs }) else { return nil }
		return (("Nächster Termin: \(next.summary)",
		         "\(Fmt.time(next.startMs)) · \(next.calendarName) · \(Self.remaining(ms: next.startMs - ms))"))
	}

	// MARK: – Vorschau (Knöpfe in den Einstellungen)

	/// Was die Vorschau-Knöpfe schicken sollen.
	enum Preview {
		case test, event, dayPlan, overdue
	}

	/// Schickt eine Meldung sofort, unabhängig vom Dedup-Protokoll.
	/// nil = gesendet, sonst Grund als Text (Banner zeigt ihn nicht, die UI schon).
	func sendPreview(_ kind: Preview) async -> String? {
		let s = MacNotifyStore.load()
		await Notifier.shared.ensurePermission()
		await Notifier.shared.refresh()
		guard Notifier.shared.canSend else {
			return "Mac erlaubt Horizont keine Meldungen – Mac → Einstellungen → Mitteilungen."
		}
		guard kind == .test else {
			// Für die echten Vorlagen müssen die Daten frisch sein.
			if let store { await store.loadHome() }
			guard let home = store?.home else { return "Keine Daten vom Server – Server und Login prüfen." }
			return previewContent(kind, home: home, s: s)
		}
		return previewContent(.test, home: nil, s: s)
	}

	private func previewContent(_ kind: Preview, home: MainEventsResponse?,
	                            s: MacNotifySettings) -> String? {
		let now = Date()
		let todayKey = Fmt.dayKeyFormatter.string(from: now)
		let days = home?.panels.flatMap(\.days) ?? []
		let all = days.flatMap(\.events)
		let msg: (title: String, body: String)?
		switch kind {
		case .test:
			msg = ("Horizont", "Systemmeldungen sind eingeschaltet.")
		case .event:
			msg = nextEventMessage(all, now: now, s: s)
				?? ("Kein Termin in Sicht", "Es steht kein Termin mit Uhrzeit an.")
		case .dayPlan:
			msg = dayPlanMessage(days: days, todayKey: todayKey, s: s)
				?? ("Heute · nichts geplant", "Keine Termine, keine offenen Aufgaben.")
		case .overdue:
			msg = overdueMessage(all, s: s)
				?? ("Nichts überfällig", "Alle Aufgaben sind im Zeitplan.")
		}
		guard let msg else { return "Nichts zu melden." }
		// Frische ID → jeder Knopfdruck erzeugt eine neue Meldung.
		return fire(id: "manual:\(UUID().uuidString)",
		            title: msg.title, body: msg.body, sound: s.sound) ? nil : Notifier.shared.lastError
	}

	// MARK: – Kleine Helfer

	/// „HH:MM" an Tag `todayKey` als Epoch-ms, nil bei ungültigem Wert.
	private static func millis(todayKey: String, time: String) -> Int? {
		let parts = time.split(separator: ":", omittingEmptySubsequences: false)
		guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
		      (0...23).contains(hour), (0...59).contains(minute),
		      let day = Fmt.dayKey(todayKey) else { return nil }
		let startOfDay = Calendar.current.startOfDay(for: day)
		return Int(startOfDay.timeIntervalSince1970 * 1000) + (hour * 3_600 + minute * 60) * 1000
	}

	/// „noch 12 Min" / „gerade eben" für Meldungstexte.
	private static func remaining(ms: Int) -> String {
		let minutes = Int((Double(ms) / 60_000).rounded())
		if minutes <= 0 { return "gerade eben" }
		if minutes < 60 { return "noch \(minutes) Min" }
		let hours = Double(minutes) / 60
		let h = hours == hours.rounded() ? String(format: "%.0f", hours) : String(format: "%.1f", hours)
		return "noch \(h) h"
	}

	/// Fälligkeit „2026-11-09" → „09.11.".
	private static func dueText(_ dayKey: String) -> String {
		guard let date = Fmt.dayKey(dayKey) else { return dayKey }
		return dueFormatter.string(from: date)
	}

	private static let dueFormatter: DateFormatter = {
		let f = DateFormatter()
		f.locale = Locale(identifier: "de_DE")
		f.dateFormat = "dd.MM."
		return f
	}()
}
