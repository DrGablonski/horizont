import Foundation

// Spiegelt src/lib/types.ts (nur die für die App relevanten Typen).

// ── Auth ──────────────────────────────────────────────────────────────────

public struct AppUser: Codable, Identifiable {
	public let id: String
	public let username: String
	public let createdAt: Int
	public let lastLoginAt: Int?
}

public struct LoginResponse: Codable {
	public let ok: Bool
	public let user: AppUser
}

public struct MeResponse: Codable {
	public let user: AppUser
}

public struct OKResponse: Codable {
	public let ok: Bool
}

// API-Token (Bearer-Auth für /api/*)
public struct ApiTokenGenerated: Codable {
	public let token: String
	public let createdAt: Int
}

/// Status des API-Tokens (GET /api/token) – Zeitstempel in Epoch-ms.
public struct ApiTokenView: Codable {
	public let hasToken: Bool
	public var createdAt: Int?
	public var lastUsedAt: Int?
}

// ── Events & Timeline ─────────────────────────────────────────────────────

public struct EventItem: Codable, Identifiable {
	public let id: String
	public let uid: String
	public let calendarId: String
	public let calendarName: String
	public let calendarColor: String
	public let summary: String
	public var location: String?
	public var description: String?
	public let startMs: Int
	public let endMs: Int
	public let allDay: Bool
	public var kind: String?          // 'event' | 'task'
	public var completed: Bool?
	public var dueKey: String?
	public var category: String?
	public var categoryColor: String?
	public var overdue: Bool?
}

/// Antwort von POST /api/tasks – entspricht dem Server-TaskItem
/// (Tasks haben keine startMs/endMs/allDay, nur eine Fälligkeit).
public struct CreatedTask: Codable, Identifiable {
	public let id: String
	public let uid: String
	public let calendarId: String
	public let calendarName: String
	public let calendarColor: String
	public let summary: String
	public var description: String?
	public let completed: Bool
	public var completedAt: Int?
	public var dueKey: String?
	public var dueMs: Int?
	public var category: String?
	public var categoryColor: String?
	public var overdue: Bool?
	public var priority: Int?
}

public struct DayGroup: Codable, Identifiable {
	public let dayKey: String   // YYYY-MM-DD
	public let label: String
	public let isToday: Bool
	public var events: [EventItem]
	public var id: String { dayKey }
}

public struct TimePanel: Codable, Identifiable {
	public let id: String       // past | now | future
	public let title: String
	public let subtitle: String
	public var days: [DayGroup]
	public let eventCount: Int
	public let defaultOpen: Bool
}

public struct MainEventsResponse: Codable {
	public let todayKey: String
	public var panels: [TimePanel]
	public let configured: Bool
	public var error: String?
}

public struct ArchiveMonth: Codable {
	public let monthKey: String     // YYYY-MM
	public let days: [DayGroup]
	public let eventCount: Int
	public let rangeStart: String   // YYYY-MM-DD
	public let rangeEnd: String
	public let canPrev: Bool
	public let canNext: Bool
	public let configured: Bool
	public var error: String?
}

// ── Workflows ─────────────────────────────────────────────────────────────

public struct WorkflowStep: Codable, Identifiable {
	public let id: String
	public let title: String
	public let done: Bool
	public let completedAt: Int?
}

public struct Workflow: Codable, Identifiable {
	public let id: String
	public let title: String
	public let notes: String
	public let createdAt: Int
	public let updatedAt: Int
	public let completedAt: Int?
	public let activeStepId: String?
	public let steps: [WorkflowStep]
	public let progress: Double
}

// ── Kalender ──────────────────────────────────────────────────────────────

public struct CalDavCalendar: Codable, Identifiable {
	public let id: String
	public let name: String
	public let color: String
	public let url: String
	public var connectionName: String?
}

/// Ein Kalender aus CalDAV plus lokale Präferenzen – spiegelt src/lib/types.ts (CalendarView).
public struct CalendarView: Codable, Identifiable, Equatable {
	public let id: String
	public let name: String
	public let color: String
	public let url: String
	public var connectionName: String?
	public let connectionId: String
	public let role: String                 // primary | secondary
	public let writable: Bool               // Server-Rechte UND kein lokaler Schreibschutz
	public let writeDisabled: Bool          // lokaler Schreibschutz durch den Benutzer
	public let hidden: Bool
	public let isDefault: Bool
	public let order: Int?                  // nil = nicht sortiert (hinten, alphabetisch)
	public let colorOverride: String?       // nil = Server-/Palette-Farbe
	public let supportedComponents: [String]
}

/// Antwort auf GET /api/calendars.
public struct CalendarsResponse: Codable {
	public let configured: Bool
	public let calendars: [CalendarView]
	/// Fehler einzelner Verbindungen (Text je Verbindung), blockiert den Rest nicht.
	public let errors: [String]
	/// ID der Hauptverbindung.
	public let primaryId: String?
}

// ── CalDAV-Verbindungen (Einstellungen) ───────────────────────────────────

public struct ConnectionView: Codable, Identifiable {
	public let id: String
	public let name: String
	public let url: String
	public let username: String
	public let hasPassword: Bool
	public let role: String        // primary | secondary
	public let provider: String    // generic | icloud | google | nextcloud | radicale | bailkal | fastmail
}

public struct ConnectionsResponse: Codable {
	public let configured: Bool
	public let connections: [ConnectionView]
	/// ID der Hauptverbindung (Workflows, Standard).
	public let primaryId: String?
}

/// Anbieter-Vorlage für das Verbindungsformular (GET /api/settings/presets).
public struct ProviderPreset: Codable, Identifiable, Equatable {
	public let id: String
	public let label: String
	public let url: String
	public let usernameLabel: String
	public let hint: String
	/// false = Kalender-Anlage vom Anbieter typischerweise abgelehnt.
	public let supportsCalendarCreation: Bool
}

/// Hülle der Preset-Antwort.
public struct ProviderPresetsResponse: Codable {
	public let presets: [ProviderPreset]
}

public struct TestResult: Codable {
	public let ok: Bool
	public var error: String?
	public var calendars: [CalDavCalendar]?
	public var eventCount: Int?
}

// ── Task-Kategorien ───────────────────────────────────────────────────────

public struct TaskCategory: Codable, Hashable {
	public let name: String
	public let color: String

	// Explizit: public Memberwise-Init (wäre synthetisiert nur internal,
	// wird aber von den Apps zum Anlegen neuer Kategorien benutzt).
	public init(name: String, color: String) {
		self.name = name
		self.color = color
	}
}

public struct CategoriesResponse: Codable {
	public let categories: [TaskCategory]
}

/// Kategorien-Regeln – spiegelt src/lib/categories.ts.
public enum TaskCategories {
	/// Standard-Kategorien („Standard herstellen" wie in der Web-App).
	public static let defaults: [TaskCategory] = [
		TaskCategory(name: "Hoch", color: "#dc2626"),
		TaskCategory(name: "Schule", color: "#2563eb"),
		TaskCategory(name: "Niedrig", color: "#16a34a")
	]

	/// Erlaubter Kategoriename: 1–40 Zeichen ohne iCal-Sonderzeichen
	/// (Komma, Semikolon, Backslash); whitespace bereinigt. nil = ungültig.
	public static func normalize(_ raw: String) -> String? {
		let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
			.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
		if s.isEmpty || s.count > 40 { return nil }
		if s.contains(where: { $0 == "," || $0 == ";" || $0 == "\\" }) { return nil }
		return s
	}
}

// ── Benachrichtigungen (Webhook) ──────────────────────────────────────────

public enum NotifyFrequency: String, Codable, CaseIterable {
	case manual, daily, weekly, interval
}

public struct NotifyLastRun: Codable {
	public let date: String
	public let status: String        // ok | skipped | error
	public var error: String?
	public var at: Int?
}

/// Ergebnis des Webhook-Tests (POST /api/notify/test).
public struct NotifyTestResult: Codable {
	public let ok: Bool
	public var status: Int?
	/// Ergebnis des Empfängers (Header x-t3-hook-outcome), z. B. „accepted".
	public var outcome: String?
	public var error: String?

	// Explizit: public Memberwise-Init mit Null-Standards (App-Fehlerpfade).
	public init(ok: Bool, status: Int? = nil, outcome: String? = nil, error: String? = nil) {
		self.ok = ok
		self.status = status
		self.outcome = outcome
		self.error = error
	}
}

/// Ergebnis des manuellen Versands (POST /api/notify/send).
public struct NotifySendResult: Codable {
	public let ok: Bool
	/// true = nichts gesendet (keine offenen Tasks o. ä.).
	public var skipped: Bool?
	public var status: Int?
	public var outcome: String?
	public var error: String?

	// Explizit: public Memberwise-Init mit Null-Standards (App-Fehlerpfade).
	public init(ok: Bool, skipped: Bool? = nil, status: Int? = nil,
	            outcome: String? = nil, error: String? = nil) {
		self.ok = ok
		self.skipped = skipped
		self.status = status
		self.outcome = outcome
		self.error = error
	}
}

public struct NotifyConfigView: Codable {
	public let frequency: NotifyFrequency
	public let time: String          // HH:MM
	public let weekday: Int          // 0=Mo … 6=So
	public let intervalHours: Int
	public var url: String?
	public let hasToken: Bool
	public let prompt: String
	public let categories: [String]
	public var lastRun: NotifyLastRun?
}

// ── Fehler ────────────────────────────────────────────────────────────────

public enum APIError: LocalizedError {
	case notConfigured
	case unauthorized
	case server(String)
	case network(String)
	case decoding

	public var errorDescription: String? {
		switch self {
		case .notConfigured: return "Server-URL nicht konfiguriert."
		case .unauthorized: return "Nicht angemeldet."
		case .server(let msg): return msg
		case .network(let msg): return "Server nicht erreichbar: \(msg)"
		case .decoding: return "Unerwartete Antwort vom Server."
		}
	}
}
