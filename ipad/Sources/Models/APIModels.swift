import Foundation

// Spiegelt src/lib/types.ts (nur die für die App relevanten Typen).

// ── Auth ──────────────────────────────────────────────────────────────────

struct AppUser: Codable, Identifiable {
	let id: String
	let username: String
	let createdAt: Int
	let lastLoginAt: Int?
}

struct LoginResponse: Codable {
	let ok: Bool
	let user: AppUser
}

struct MeResponse: Codable {
	let user: AppUser
}

struct OKResponse: Codable {
	let ok: Bool
}

// API-Token (Bearer-Auth für /api/*)
struct ApiTokenGenerated: Codable {
	let token: String
	let createdAt: Int
}

/// Status des API-Tokens (GET /api/token) – Zeitstempel in Epoch-ms.
struct ApiTokenView: Codable {
	let hasToken: Bool
	var createdAt: Int?
	var lastUsedAt: Int?
}

// ── Events & Timeline ─────────────────────────────────────────────────────

struct EventItem: Codable, Identifiable {
	let id: String
	let uid: String
	let calendarId: String
	let calendarName: String
	let calendarColor: String
	let summary: String
	var location: String?
	var description: String?
	let startMs: Int
	let endMs: Int
	let allDay: Bool
	var kind: String?          // 'event' | 'task'
	var completed: Bool?
	var dueKey: String?
	var category: String?
	var categoryColor: String?
	var overdue: Bool?
}

struct DayGroup: Codable, Identifiable {
	let dayKey: String   // YYYY-MM-DD
	let label: String
	let isToday: Bool
	var events: [EventItem]
	var id: String { dayKey }
}

struct TimePanel: Codable, Identifiable {
	let id: String       // past | now | future
	let title: String
	let subtitle: String
	var days: [DayGroup]
	let eventCount: Int
	let defaultOpen: Bool
}

struct MainEventsResponse: Codable {
	let todayKey: String
	var panels: [TimePanel]
	let configured: Bool
	var error: String?
}

struct ArchiveMonth: Codable {
	let monthKey: String     // YYYY-MM
	let days: [DayGroup]
	let eventCount: Int
	let rangeStart: String   // YYYY-MM-DD
	let rangeEnd: String
	let canPrev: Bool
	let canNext: Bool
	let configured: Bool
	var error: String?
}

// ── Workflows ─────────────────────────────────────────────────────────────

struct WorkflowStep: Codable, Identifiable {
	let id: String
	let title: String
	let done: Bool
	let completedAt: Int?
}

struct Workflow: Codable, Identifiable {
	let id: String
	let title: String
	let notes: String
	let createdAt: Int
	let updatedAt: Int
	let completedAt: Int?
	let activeStepId: String?
	let steps: [WorkflowStep]
	let progress: Double
}

// ── Kalender ──────────────────────────────────────────────────────────────

struct CalDavCalendar: Codable, Identifiable {
	let id: String
	let name: String
	let color: String
	let url: String
	var connectionName: String?
}

/// Ein Kalender aus CalDAV plus lokale Präferenzen – spiegelt src/lib/types.ts (CalendarView).
struct CalendarView: Codable, Identifiable, Equatable {
	let id: String
	let name: String
	let color: String
	let url: String
	var connectionName: String?
	let connectionId: String
	let role: String                 // primary | secondary
	let writable: Bool               // Server-Rechte UND kein lokaler Schreibschutz
	let writeDisabled: Bool          // lokaler Schreibschutz durch den Benutzer
	let hidden: Bool
	let isDefault: Bool
	let order: Int?                  // nil = nicht sortiert (hinten, alphabetisch)
	let colorOverride: String?       // nil = Server-/Palette-Farbe
	let supportedComponents: [String]
}

/// Antwort auf GET /api/calendars.
struct CalendarsResponse: Codable {
	let configured: Bool
	let calendars: [CalendarView]
	/// Fehler einzelner Verbindungen (Text je Verbindung), blockiert den Rest nicht.
	let errors: [String]
	/// ID der Hauptverbindung.
	let primaryId: String?
}

// ── CalDAV-Verbindungen (Einstellungen) ───────────────────────────────────

struct ConnectionView: Codable, Identifiable {
	let id: String
	let name: String
	let url: String
	let username: String
	let hasPassword: Bool
	let role: String        // primary | secondary
	let provider: String    // generic | icloud | google | nextcloud | radicale | bailkal | fastmail
}

struct ConnectionsResponse: Codable {
	let configured: Bool
	let connections: [ConnectionView]
	/// ID der Hauptverbindung (Workflows, Standard).
	let primaryId: String?
}

/// Anbieter-Vorlage für das Verbindungsformular (GET /api/settings/presets).
struct ProviderPreset: Codable, Identifiable, Equatable {
	let id: String
	let label: String
	let url: String
	let usernameLabel: String
	let hint: String
	/// false = Kalender-Anlage vom Anbieter typischerweise abgelehnt.
	let supportsCalendarCreation: Bool
}

/// Hülle der Preset-Antwort.
struct ProviderPresetsResponse: Codable {
	let presets: [ProviderPreset]
}

struct TestResult: Codable {
	let ok: Bool
	var error: String?
	var calendars: [CalDavCalendar]?
	var eventCount: Int?
}

// ── Task-Kategorien ───────────────────────────────────────────────────────

struct TaskCategory: Codable, Hashable {
	let name: String
	let color: String
}

struct CategoriesResponse: Codable {
	let categories: [TaskCategory]
}

/// Kategorien-Regeln – spiegelt src/lib/categories.ts.
enum TaskCategories {
	/// Standard-Kategorien („Standard herstellen" wie in der Web-App).
	static let defaults: [TaskCategory] = [
		TaskCategory(name: "Hoch", color: "#dc2626"),
		TaskCategory(name: "Schule", color: "#2563eb"),
		TaskCategory(name: "Niedrig", color: "#16a34a")
	]

	/// Erlaubter Kategoriename: 1–40 Zeichen ohne iCal-Sonderzeichen
	/// (Komma, Semikolon, Backslash); whitespace bereinigt. nil = ungültig.
	static func normalize(_ raw: String) -> String? {
		let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
			.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
		if s.isEmpty || s.count > 40 { return nil }
		if s.contains(where: { $0 == "," || $0 == ";" || $0 == "\\" }) { return nil }
		return s
	}
}

// ── Benachrichtigungen (Webhook) ──────────────────────────────────────────

enum NotifyFrequency: String, Codable, CaseIterable {
	case manual, daily, weekly, interval
}

struct NotifyLastRun: Codable {
	let date: String
	let status: String        // ok | skipped | error
	var error: String?
	var at: Int?
}

/// Ergebnis des Webhook-Tests (POST /api/notify/test).
struct NotifyTestResult: Codable {
	let ok: Bool
	var status: Int?
	/// Ergebnis des Empfängers (Header x-t3-hook-outcome), z. B. „accepted".
	var outcome: String?
	var error: String?
}

/// Ergebnis des manuellen Versands (POST /api/notify/send).
struct NotifySendResult: Codable {
	let ok: Bool
	/// true = nichts gesendet (keine offenen Tasks o. ä.).
	var skipped: Bool?
	var status: Int?
	var outcome: String?
	var error: String?
}

struct NotifyConfigView: Codable {
	let frequency: NotifyFrequency
	let time: String          // HH:MM
	let weekday: Int          // 0=Mo … 6=So
	let intervalHours: Int
	var url: String?
	let hasToken: Bool
	let prompt: String
	let categories: [String]
	var lastRun: NotifyLastRun?
}

// ── Fehler ────────────────────────────────────────────────────────────────

enum APIError: LocalizedError {
	case notConfigured
	case unauthorized
	case server(String)
	case network(String)
	case decoding

	var errorDescription: String? {
		switch self {
		case .notConfigured: return "Server-URL nicht konfiguriert."
		case .unauthorized: return "Nicht angemeldet."
		case .server(let msg): return msg
		case .network(let msg): return "Server nicht erreichbar: \(msg)"
		case .decoding: return "Unerwartete Antwort vom Server."
		}
	}
}
