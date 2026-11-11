import Foundation
import WidgetKit

// MARK: – Widget-Daten (iPad-App → Widgets über App Group)

/// Kompakter Snapshot des Tages für die Widgets.
struct WidgetSnapshot: Codable {
	struct Entry: Codable {
		let id: String
		let summary: String
		let time: String?       // "HH:mm", nil bei ganztägig
		let isTask: Bool
		let completed: Bool
		let overdue: Bool
		let colorHex: String?   // Kalenderfarbe
	}

	let generatedAt: Date
	let dayLabel: String        // z. B. "Montag, 10. November"
	let todayEntries: [Entry]
	let openTasks: Int          // offene Aufgaben über alle Horizonte

	/// Beispieldaten für Vorschau/Placeholder.
	static let sample = WidgetSnapshot(
		generatedAt: .now,
		dayLabel: "Heute",
		todayEntries: [
			Entry(id: "1", summary: "Mathe-Nachhilfe", time: "16:00",
			      isTask: false, completed: false, overdue: false, colorHex: "#2563EB"),
			Entry(id: "2", summary: "Arbeitsblatt abgeben", time: nil,
			      isTask: true, completed: false, overdue: false, colorHex: "#059669"),
		],
		openTasks: 3
	)
}

enum WidgetSnapshotSupport {
	private static var fileURL: URL? {
		AppGroup.container?.appendingPathComponent("widget-snapshot.json")
	}

	/// Nach jedem Home-Load: Snapshot schreiben + Widgets neu laden.
	static func publish(_ home: MainEventsResponse) {
		var entries: [WidgetSnapshot.Entry] = []
		for panel in home.panels {
			for day in panel.days where day.dayKey == home.todayKey {
				for ev in day.events {
					entries.append(WidgetSnapshot.Entry(
						id: ev.id,
						summary: ev.summary,
						time: ev.allDay ? nil : Fmt.time(ev.startMs),
						isTask: ev.kind == "task",
						completed: ev.completed == true,
						overdue: ev.overdue == true,
						colorHex: ev.calendarColor))
				}
			}
		}
		let open = home.panels
			.flatMap(\.days)
			.flatMap(\.events)
			.filter { $0.kind == "task" && $0.completed != true }
			.count

		save(WidgetSnapshot(
			generatedAt: .now,
			dayLabel: dayLabel(for: home.todayKey),
			todayEntries: entries.sorted { ($0.time ?? "99:99") < ($1.time ?? "99:99") },
			openTasks: open))
		WidgetCenter.shared.reloadAllTimelines()
	}

	static func load() -> WidgetSnapshot? {
		guard let url = fileURL,
		      let data = try? Data(contentsOf: url) else { return nil }
		return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
	}

	static func save(_ snapshot: WidgetSnapshot) {
		guard let url = fileURL,
		      let data = try? JSONEncoder().encode(snapshot) else { return }
		try? data.write(to: url, options: .atomic)
	}

	private static func dayLabel(for dayKey: String) -> String {
		guard let date = Fmt.dayKey(dayKey) else { return "Heute" }
		let f = DateFormatter()
		f.locale = Locale(identifier: "de_DE")
		f.dateFormat = "EEEE, d. MMMM"
		return f.string(from: date)
	}
}
