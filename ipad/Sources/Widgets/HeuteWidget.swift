import SwiftUI
import WidgetKit

// MARK: – Timeline

/// Ein Widget-Zustand: aktueller Snapshot (nil = nie in der App gewesen).
struct HeuteEntry: TimelineEntry {
	let date: Date
	let snapshot: WidgetSnapshot?
}

/// Datenquelle: liest den von der App geschriebenen App-Group-Snapshot.
/// Die App stößt nach jedem Laden `WidgetCenter.reloadAllTimelines()` an;
/// der Timeline-Eintrag selbst sorgt nur für den Wechsel über die Mitternacht.
struct HeuteProvider: TimelineProvider {
	func placeholder(in context: Context) -> HeuteEntry {
		HeuteEntry(date: .now, snapshot: .sample)
	}

	func getSnapshot(in context: Context, completion: @escaping (HeuteEntry) -> Void) {
		completion(HeuteEntry(date: .now, snapshot: WidgetSnapshotSupport.load() ?? .sample))
	}

	func getTimeline(in context: Context, completion: @escaping (Timeline<HeuteEntry>) -> Void) {
		let entry = HeuteEntry(date: .now, snapshot: WidgetSnapshotSupport.load())
		let next = Calendar.current.nextDate(
			after: .now,
			matching: DateComponents(hour: 0, minute: 1),
			matchingPolicy: .nextTime) ?? .now.addingTimeInterval(3600)
		completion(Timeline(entries: [entry], after: next))
	}
}

// MARK: – Home-Screen-Widget (mittel + groß)

struct HeuteWidgetView: View {
	@Environment(\.widgetFamily) private var family

	let entry: HeuteEntry

	private var maxRows: Int { family == .systemLarge ? 7 : 3 }

	var body: some View {
		VStack(alignment: .leading, spacing: DS.Space.sm) {
			header
			if let snap = entry.snapshot {
				list(snap)
				Spacer(minLength: 0)
				footer(snap)
			} else {
				Spacer(minLength: 0)
				VStack(alignment: .leading, spacing: DS.Space.xs) {
					Image(systemName: "circle.dotted")
						.font(.system(size: 22, weight: .light))
						.foregroundStyle(DS.accent)
					Text("In Horizont anmelden")
						.font(.footnote.weight(.medium))
						.foregroundStyle(DS.textPrimary)
					Text("Die App aktualisiert dieses Widget.")
						.font(.caption2)
						.foregroundStyle(DS.textTertiary)
				}
				Spacer(minLength: 0)
			}
		}
		.containerBackground(for: .widget) { AmbientBackground() }
	}

	private var header: some View {
		HStack(spacing: DS.Space.xs) {
			Image(systemName: "circle.dotted")
				.font(.system(size: 12, weight: .semibold))
				.foregroundStyle(DS.accent)
			VStack(alignment: .leading, spacing: 0) {
				Text("Heute")
					.font(.system(size: 13, weight: .semibold))
					.foregroundStyle(DS.textPrimary)
				if let label = entry.snapshot?.dayLabel {
					Text(label)
						.font(.system(size: 10))
						.foregroundStyle(DS.textTertiary)
						.lineLimit(1)
				}
			}
			Spacer(minLength: 0)
		}
	}

	@ViewBuilder
	private func list(_ snap: WidgetSnapshot) -> some View {
		if snap.todayEntries.isEmpty {
			HStack(spacing: DS.Space.xs) {
				Image(systemName: "calendar.day.timeline.left")
					.font(.system(size: 11))
					.foregroundStyle(DS.textTertiary)
				Text("Heute nichts eingetragen")
					.font(.footnote)
					.foregroundStyle(DS.textSecondary)
			}
			.padding(.vertical, DS.Space.xs)
		} else {
			VStack(alignment: .leading, spacing: family == .systemLarge ? 6 : 5) {
				ForEach(Array(snap.todayEntries.prefix(maxRows).enumerated()), id: \.offset) { _, item in
					row(item)
				}
				let rest = snap.todayEntries.count - maxRows
				if rest > 0 {
					Text("+\(rest) weitere")
						.font(.system(size: 10))
						.foregroundStyle(DS.textTertiary)
				}
			}
		}
	}

	private func row(_ item: WidgetSnapshot.Entry) -> some View {
		HStack(spacing: 6) {
			Circle()
				.fill(item.overdue ? Color(hex: item.colorHex) ?? DS.danger : Color(hex: item.colorHex))
				.frame(width: 6, height: 6)
			Text(item.time ?? "ganztägig")
				.font(.system(size: 10).monospacedDigit())
				.foregroundStyle(item.time != nil ? DS.textSecondary : DS.textTertiary)
				.frame(width: 44, alignment: .leading)
			Text(item.summary)
				.font(.system(size: 12))
				.foregroundStyle(item.completed ? DS.textTertiary : DS.textPrimary)
				.strikethrough(item.completed)
				.lineLimit(1)
			if item.overdue {
				Image(systemName: "exclamationmark.circle.fill")
					.font(.system(size: 10))
					.foregroundStyle(DS.danger)
			}
			Spacer(minLength: 0)
		}
	}

	private func footer(_ snap: WidgetSnapshot) -> some View {
		HStack(spacing: DS.Space.xs) {
			if snap.openTasks > 0 {
				Chip(text: "\(snap.openTasks) offene Aufgaben", color: DS.accent)
			}
			Spacer(minLength: 0)
			Text("Stand \(timeText(snap))")
				.font(.system(size: 9))
				.foregroundStyle(DS.textTertiary)
		}
	}

	private func timeText(_ snap: WidgetSnapshot) -> String {
		let f = DateFormatter()
		f.locale = Locale(identifier: "de_DE")
		f.dateFormat = "HH:mm"
		return f.string(from: snap.generatedAt)
	}
}

struct HeuteWidget: Widget {
	static let kind = "de.hott.horizont.ipad.heute"

	var body: some WidgetConfiguration {
		StaticConfiguration(kind: Self.kind, provider: HeuteProvider()) { entry in
			HeuteWidgetView(entry: entry)
		}
		.configurationDisplayName("Heute")
		.description("Heutige Termine und offene Aufgaben aus Horizont.")
		.supportedFamilies([.systemMedium, .systemLarge])
	}
}

// MARK: – Sperrbildschirm (Accessory rectangular)

struct HeuteAccessoryView: View {
	let entry: HeuteEntry

	var body: some View {
		VStack(alignment: .leading, spacing: 2) {
			if let snap = entry.snapshot {
				Text("Heute · \(snap.openTasks) offen")
					.font(.system(size: 11, weight: .semibold))
					.foregroundStyle(.primary)
				ForEach(Array(snap.todayEntries.prefix(2).enumerated()), id: \.offset) { _, item in
					HStack(spacing: 4) {
						Text(item.time ?? "–")
							.font(.system(size: 10).monospacedDigit())
							.foregroundStyle(.secondary)
						Text(item.summary)
							.font(.system(size: 12))
							.foregroundStyle(item.completed ? Color(.systemGray) : .primary)
							.lineLimit(1)
					}
				}
				if snap.todayEntries.isEmpty {
					Text("Nichts eingetragen")
						.font(.system(size: 12))
						.foregroundStyle(.secondary)
				}
			} else {
				Text("Horizont")
					.font(.system(size: 12, weight: .semibold))
					.foregroundStyle(.primary)
				Text("In der App anmelden")
					.font(.system(size: 11))
					.foregroundStyle(.secondary)
			}
			Spacer(minLength: 0)
		}
		.containerBackground(for: .widget) { Color.clear }
	}
}

struct HeuteAccessoryWidget: Widget {
	static let kind = "de.hott.horizont.ipad.heute.accessory"

	var body: some WidgetConfiguration {
		StaticConfiguration(kind: Self.kind, provider: HeuteProvider()) { entry in
			HeuteAccessoryView(entry: entry)
		}
		.configurationDisplayName("Heute (kompakt)")
		.description("Kompakter Tages-Überblick fürs Sperrbildschirm-Widget.")
		.supportedFamilies([.accessoryRectangular])
	}
}
