import SwiftUI

/// Eine Zeile in der Timeline: Termin oder Aufgabe (mit Abhaken).
///
/// Die ganze Zeile ist klickbar, wenn `onSelect` gesetzt ist (öffnet z. B.
/// das Detail-Popover). Das Abhaken von Tasks bleibt als eigener Button
/// verschachtelt. Archiv-Views rufen die Zeile ohne `onSelect` – dann ist
/// sie rein dekorativ (kein Hover-Highlight).
struct EventRowView: View {
	let event: EventItem
	var onToggle: () async -> Void
	var onSelect: (() -> Void)? = nil

	@State private var toggling = false
	@State private var hovering = false

	private var isTask: Bool { event.kind == "task" }
	private var isDone: Bool { event.completed ?? false }
	private var selectable: Bool { onSelect != nil }

	var body: some View {
		HStack(alignment: .firstTextBaseline, spacing: DS.Space.md) {
			if isTask {
				toggleButton
			} else {
				Circle()
					.fill(Color(hex: event.calendarColor))
					.frame(width: 9, height: 9)
					.padding(.top, 3)
			}

			VStack(alignment: .leading, spacing: DS.Space.xs) {
				Text(event.summary)
					.font(DS.Typo.rowTitle)
					.strikethrough(isDone)
					.foregroundStyle(isDone ? DS.textSecondary : DS.textPrimary)
					.lineLimit(2)

				HStack(spacing: DS.Space.sm) {
					if !event.allDay {
						Text(Fmt.time(event.startMs))
							.font(DS.Typo.meta.monospacedDigit())
							.foregroundStyle(DS.textSecondary)
					}
					if isTask, let cat = event.category {
						Chip(text: cat, color: Color(hex: event.categoryColor))
					}
					if event.overdue == true {
						Chip(text: "überfällig", color: DS.danger, systemImage: "exclamationmark")
					}
				}
			}

			Spacer(minLength: DS.Space.sm)

			if !isTask {
				HStack(spacing: DS.Space.xs) {
					Circle()
						.fill(Color(hex: event.calendarColor))
						.frame(width: 8, height: 8)
					Text(event.calendarName)
						.font(DS.Typo.chip)
						.foregroundStyle(DS.textTertiary)
						.lineLimit(1)
				}
			}
		}
		.padding(.horizontal, DS.Space.sm)
		.padding(.vertical, DS.Space.xs + 2)
		.background(
			DS.rowHover.opacity(hovering ? 1 : 0),
			in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
		)
		.animation(.easeOut(duration: 0.12), value: hovering)
		.contentShape(Rectangle())
		.onTapGesture { onSelect?() }
		.onHover { hovering = selectable && $0 }
	}

	/// Großer Kreis-Button zum Abhaken mit animiertem Füllwechsel.
	private var toggleButton: some View {
		Button {
			guard !toggling else { return }
			toggling = true
			Task {
				await onToggle()
				toggling = false
			}
		} label: {
			Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
				.font(.system(size: 18, weight: .regular))
				.foregroundStyle(isDone ? DS.success : Color(hex: event.categoryColor))
				.scaleEffect(toggling ? 0.8 : 1)
		}
		.buttonStyle(.plain)
		.disabled(toggling)
		.animation(.spring(response: 0.25, dampingFraction: 0.6), value: isDone)
		.animation(.easeOut(duration: 0.15), value: toggling)
	}
}
