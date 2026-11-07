import SwiftUI

/// Eine Zeile in der Timeline: Termin oder Aufgabe (mit Abhaken).
struct EventRowView: View {
	let event: EventItem
	var onToggle: () async -> Void

	@State private var toggling = false

	private var isTask: Bool { event.kind == "task" }

	var body: some View {
		HStack(alignment: .firstTextBaseline, spacing: 10) {
			if isTask {
				Button {
					toggling = true
					Task {
						await onToggle()
						toggling = false
					}
				} label: {
					Image(systemName: (event.completed ?? false)
					      ? "checkmark.circle.fill" : "circle")
						.foregroundStyle(
							(event.completed ?? false)
							? AnyShapeStyle(.green)
							: AnyShapeStyle(Color(hex: event.categoryColor)))
				}
				.buttonStyle(.plain)
				.disabled(toggling)
			} else {
				Circle()
					.fill(Color(hex: event.calendarColor))
					.frame(width: 9, height: 9)
					.padding(.top, 3)
			}

			VStack(alignment: .leading, spacing: 2) {
				Text(event.summary)
					.strikethrough(event.completed ?? false)
					.foregroundStyle((event.completed ?? false) ? Color(nsColor: .secondaryLabelColor) : Color(nsColor: .labelColor))
					.font(.body)
				HStack(spacing: 8) {
					if !event.allDay {
						Text(Fmt.time(event.startMs))
							.font(.caption.monospacedDigit())
							.foregroundStyle(.secondary)
					}
					if isTask, let cat = event.category {
						Text(cat)
							.font(.caption2)
							.padding(.horizontal, 6).padding(.vertical, 2)
							.background(Capsule().fill(Color(hex: event.categoryColor).opacity(0.18)))
							.foregroundStyle(Color(hex: event.categoryColor))
					}
					if event.overdue == true {
						Text("überfällig").font(.caption2).foregroundStyle(.red)
					}
				}
			}

			Spacer()

			if !isTask {
				Text(event.calendarName)
					.font(.caption2)
					.foregroundStyle(.secondary)
					.lineLimit(1)
			}
		}
		.padding(.vertical, 2)
	}
}
