import AppKit
import Foundation
import Observation
import UserNotifications

// MARK: – Start-Erkennung

enum AppLaunch {
	/// QA-Screenshot-Durchlauf (`-HZShot`): kein Nutzer weit, also keine
	/// Berechtigungsdialoge und keine Meldungen.
	static let isQARun: Bool = CommandLine.arguments.contains("-HZShot")
}

// MARK: – Einstellungen (nur dieser Mac)

/// Konfiguration der macOS-Systemmeldungen. Bewusst **lokal** (UserDefaults):
/// Der Server kennt nur die Webhook-Variante, diese hier läuft ohne Netz.
/// Jeder Wert hat einen eigenen Schlüssel → ein neues Feld bekommt einfach
/// seinen Standardwert, statt eine gespeicherte Einstellung zu verwerfen.
struct MacNotifySettings: Equatable {
	/// Master-Schalter für alle lokalen Meldungen.
	var master = true
	/// Erinnerung vor Beginn eines Termins.
	var eventsOn = true
	/// Vorlauf in Minuten (0 = genau zum Termin).
	var eventLead = 10
	/// Tagesplan (Termine + Aufgaben von heute) zu fester Uhrzeit.
	var dayPlanOn = false
	var dayPlanTime = "07:30"
	/// Hinweis auf überfällige Aufgaben, einmal täglich.
	var overdueOn = false
	var overdueTime = "08:00"
	/// Ton zur Meldung (aus = nur Banner).
	var sound = false
	/// Kalender-Filter nach Namen; leer = alle Kalender.
	var calendars: [String] = []
	/// Kategorie-Filter für Aufgaben; leer = alle Kategorien.
	var categories: [String] = []

	/// Darf dieser Kalender melden? (leere Auswahl = keine Einschränkung)
	func allows(calendar name: String) -> Bool {
		calendars.isEmpty || calendars.contains(name)
	}

	/// Darf diese Aufgabe melden? Kategorienlose Aufgaben passen nur ungefiltert.
	func allows(category: String?) -> Bool {
		categories.isEmpty || (category.map(categories.contains) ?? false)
	}
}

/// Laden und Speichern der lokalen Meldungseinstellungen.
enum MacNotifyStore {
	private static let p = "hz.notify."

	static func load() -> MacNotifySettings {
		let d = UserDefaults.standard
		var s = MacNotifySettings()
		s.master = d.object(forKey: p + "master") as? Bool ?? s.master
		s.eventsOn = d.object(forKey: p + "eventsOn") as? Bool ?? s.eventsOn
		s.eventLead = d.object(forKey: p + "eventLead") as? Int ?? s.eventLead
		s.dayPlanOn = d.object(forKey: p + "dayPlanOn") as? Bool ?? s.dayPlanOn
		s.dayPlanTime = d.string(forKey: p + "dayPlanTime") ?? s.dayPlanTime
		s.overdueOn = d.object(forKey: p + "overdueOn") as? Bool ?? s.overdueOn
		s.overdueTime = d.string(forKey: p + "overdueTime") ?? s.overdueTime
		s.sound = d.object(forKey: p + "sound") as? Bool ?? s.sound
		s.calendars = d.stringArray(forKey: p + "calendars") ?? []
		s.categories = d.stringArray(forKey: p + "categories") ?? []
		return s
	}

	static func save(_ s: MacNotifySettings) {
		let d = UserDefaults.standard
		d.set(s.master, forKey: p + "master")
		d.set(s.eventsOn, forKey: p + "eventsOn")
		d.set(s.eventLead, forKey: p + "eventLead")
		d.set(s.dayPlanOn, forKey: p + "dayPlanOn")
		d.set(s.dayPlanTime, forKey: p + "dayPlanTime")
		d.set(s.overdueOn, forKey: p + "overdueOn")
		d.set(s.overdueTime, forKey: p + "overdueTime")
		d.set(s.sound, forKey: p + "sound")
		d.set(s.calendars, forKey: p + "calendars")
		d.set(s.categories, forKey: p + "categories")
	}

	/// Wurde die Systemberechtigung schon einmal angefragt? (nur einmal fragen)
	static var didAskPermission: Bool {
		get { UserDefaults.standard.bool(forKey: p + "asked") }
		set { UserDefaults.standard.set(newValue, forKey: p + "asked") }
	}
}

/// Dedup-Protokoll: welche Meldung wurde wann schon rausgeschickt.
/// Ohne das würde jeder Prüftick dieselbe Erinnerung erneut zeigen.
enum NotifyLog {
	private static let firedKey = "hz.notifyFired"
	private static let lastTitleKey = "hz.notifyLastTitle"
	private static let lastAtKey = "hz.notifyLastAt"
	/// Einträge älter als zwei Wochen sind für die Dedup unnütz.
	private static let maxAge: TimeInterval = 14 * 86_400

	static func fired(_ id: String) -> Bool { map[id] != nil }

	static func markFired(_ id: String) {
		var m = map
		m[id] = Date().timeIntervalSince1970
		UserDefaults.standard.set(m, forKey: firedKey)
	}

	/// Alte Einträge entfernen, sonst wächst die Liste mit jedem Termin weiter.
	static func prune() {
		let cutoff = Date().timeIntervalSince1970 - maxAge
		UserDefaults.standard.set(map.filter { $0.value >= cutoff }, forKey: firedKey)
	}

	private static var map: [String: TimeInterval] {
		UserDefaults.standard.dictionary(forKey: firedKey) as? [String: TimeInterval] ?? [:]
	}

	/// Zuletzt gesendete Meldung (Titel + Zeit) für die Anzeige in den Einstellungen.
	static func recordSent(title: String) {
		let d = UserDefaults.standard
		d.set(title, forKey: lastTitleKey)
		d.set(Date().timeIntervalSince1970, forKey: lastAtKey)
	}

	static func lastSent() -> (title: String, at: Date)? {
		guard let title = UserDefaults.standard.string(forKey: lastTitleKey),
		      let at = UserDefaults.standard.object(forKey: lastAtKey) as? Double else { return nil }
		return (title, Date(timeIntervalSince1970: at))
	}

	/// Für „Alles zurücksetzen" in den Einstellungen: alle Erinnerungen noch mal erlauben.
	static func clearFired() {
		UserDefaults.standard.removeObject(forKey: firedKey)
	}
}

// MARK: – Notifier (Mitteilungszentrum)

/// Schickt die Meldungen übers macOS-Mitteilungszentrum und hält die
/// Berechtigung für die Einstellungen aktuell.
@MainActor
@Observable
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
	static let shared = Notifier()

	/// Berechtigungsstatus (UI liest live mit).
	private(set) var status: UNAuthorizationStatus = .notDetermined
	/// Letzter Fehler vom Versand (leerer String = alles gut).
	private(set) var lastError: String?

	/// Kategorie: Klick auf die Meldung holt Horizont nach vorn.
	private static let categoryID = "hz.open"
	private static let actionID = "hz.open.action"

	private override init() { super.init() }

	/// Einmal beim App-Start aufrufen: Delegate + Kategorie registrieren.
	func install() {
		let center = UNUserNotificationCenter.current()
		center.delegate = self
		let open = UNNotificationAction(identifier: Self.actionID,
		                                title: "Horizont öffnen",
		                                options: [.foreground])
		center.setNotificationCategories([
			UNNotificationCategory(identifier: Self.categoryID,
			                       actions: [open],
			                       intentIdentifiers: [])
		])
		Task { await refresh() }
	}

	/// Berechtigungsstatus neu einlesen (nutzerseitig änderbar, jederzeit).
	func refresh() async {
		status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
	}

	/// Fragt das Systemdialog an – einmalig, danach entscheidet der Nutzer.
	func requestPermission() async {
		MacNotifyStore.didAskPermission = true
		_ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
		await refresh()
	}

	/// Beim ersten Start unaufdringlich fragen (nicht im QA-Durchlauf).
	func ensurePermission() async {
		await refresh()
		guard status == .notDetermined, !MacNotifyStore.didAskPermission, !AppLaunch.isQARun else { return }
		await requestPermission()
	}

	/// Erlaubt das System gerade Meldungen?
	var canSend: Bool { status == .authorized || status == .provisional }

	/// Eine Meldung sofort senden (nil = rausgeschickt, sonst Grund als Text).
	/// Gleiche `identifier` = Dedup; Vorschau-Knöpfe nutzen eigene, frische IDs.
	func send(identifier: String, title: String, body: String, sound: Bool) -> String? {
		guard canSend else {
			return "Mac erlaubt Horizont keine Meldungen – Mac → Einstellungen → Mitteilungen."
		}
		let content = UNMutableNotificationContent()
		content.title = title
		content.body = body
		content.sound = sound ? .default : nil
		content.categoryIdentifier = Self.categoryID
		let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
		UNUserNotificationCenter.current().add(request) { [weak self] err in
			guard let err else { return }
			Task { @MainActor in self?.lastError = err.localizedDescription }
		}
		lastError = nil
		return nil
	}

	/// Mac → Einstellungen → Mitteilungen (jüngerer Pfad, älteres macOS als Fallback).
	static func openSystemSettings() {
		for raw in ["x-apple.systempreferences:com.apple.Notifications-Settings.extension",
		            "x-apple.systempreferences:com.apple.preference.notifications"] {
			if let url = URL(string: raw), NSWorkspace.shared.open(url) { return }
		}
	}

	// MARK: Delegate (läuft außerhalb des MainActor → zurück ins UI)

	nonisolated func userNotificationCenter(
		_ center: UNUserNotificationCenter,
		willPresent notification: UNNotification,
		withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
	) {
		// Horizont vorn: Banner trotzdem zeigen (sonst wirkt der Testknopf leer).
		completionHandler([.banner])
	}

	nonisolated func userNotificationCenter(
		_ center: UNUserNotificationCenter,
		didReceive response: UNNotificationResponse,
		withCompletionHandler completionHandler: @escaping () -> Void
	) {
		Task { @MainActor in Notifier.openMainWindow() }
		completionHandler()
	}

	/// Meldung angeklickt: Fenster nach vorn, Bereich „Horizont" zeigen.
	private static func openMainWindow() {
		NSApp.activate(ignoringOtherApps: true)
		if let win = NSApp.windows.first(where: { $0.styleMask.contains(.titled) }) {
			win.makeKeyAndOrderFront(nil)
		}
		NotificationCenter.default.post(name: NavCmd.select, object: 0)
	}
}
