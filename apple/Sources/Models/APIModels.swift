import Foundation

// Spiegelt src/lib/types.ts (nur die für die App relevanten Typen).

// ── Auth ──────────────────────────────────────────────────────────────────

struct AppUser: Codable, Identifiable {
	let id: String
	let username: String
	let role: String
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

struct CalendarsResponse: Codable {
	let configured: Bool
	let calendars: [CalDavCalendar]
	var error: String?
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
