import SwiftUI

/// Eine Zeile in der Timeline: Termin oder Aufgabe (mit Abhaken).
///
/// Für iPhone kompakt gebaut: Titel, Zeit, Kalenderfarbe, Kategorie-Chip
/// und Überfällig-Markierung – Zeilenhöhe mindestens 44 pt (Touch-Ziel).
/// Die Zeile navigiert selbst nicht: Als List-Zeile hängt die Eltern-View
/// einen NavigationLink davor. Das Abhaken von Tasks bleibt ein eigener
/// verschachtelter Button (44-pt-Touch-Ziel). `onSelect` bleibt für Hosts
/// ohne Navigation erhalten – ist es gesetzt, ist die ganze Zeile tippbar.
struct EventRowView: View {
	let event: EventItem
	var onToggle: () async -> Void
	var onSelect: (() -> Void)? = nil

	@State private var toggling = false

	private var isTask: Bool { event.kind == "task" }
	private var isDone: Bool { event.completed ?? false }
	/// Die Meta-Zeile nur zeigen, wenn sie etwas enthält.
	private var hasMeta: Bool {
		!event.allDay || event.overdue == true || (isTask && event.category != nil)
	}

	var body: some View {
		HStack(spacing: DS.Space.md) {
			if isTask {
				toggleButton
			} else {
				// Kalenderfarbe als Punkt (Termin, nicht abhakbar)
				Circle()
					.fill(Color(hex: event.calendarColor))
					.frame(width: 10, height: 10)
			}

			VStack(alignment: .leading, spacing: DS.Space.xs) {
				Text(event.summary)
					.font(DS.Typo.rowTitle)
					.strikethrough(isDone)
					.foregroundStyle(isDone ? DS.textSecondary : DS.textPrimary)
					.lineLimit(2)

				if hasMeta {
					metaRow
				}
			}

			Spacer(minLength: DS.Space.sm)

			// Termine zeigen rechts den Kalender, Tasks nicht (Platz sparen).
			if !isTask {
				Text(event.calendarName)
					.font(DS.Typo.chip)
					.foregroundStyle(DS.textTertiary)
					.lineLimit(1)
					.truncationMode(.tail)
					.frame(maxWidth: 110, alignment: .trailing)
			}
		}
		.padding(.vertical, DS.Space.sm)
		.frame(minHeight: 44)
		.contentShape(Rectangle())
		.modifier(OptionalTap(action: onSelect))
	}

	/// Zweite Zeile: Uhrzeit, Kategorie-Chip, überfällig-Markierung.
	private var metaRow: some View {
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

	/// Großer Kreis-Button zum Abhaken (44 pt Touch-Ziel) mit animiertem
	/// Füllwechsel; während des Speicherns gesperrt und leicht verkleinert.
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
				.font(.system(size: 22, weight: .regular))
				.foregroundStyle(isDone ? DS.success : Color(hex: event.categoryColor))
				.frame(width: 44, height: 44)
				.contentShape(Rectangle())
				.scaleEffect(toggling ? 0.8 : 1)
		}
		.buttonStyle(.plain)
		.disabled(toggling)
		.animation(.spring(response: 0.25, dampingFraction: 0.6), value: isDone)
		.animation(.easeOut(duration: 0.15), value: toggling)
	}
}

// MARK: – Optionale Tipp-Aktion

/// Wendet `onTapGesture` nur an, wenn eine Aktion gesetzt ist – ein leerer
/// Gestenerkenner würde sonst die Navigation des umgebenden NavigationLinks
/// abfangen (Kind-Gesten gewinnen gegen den Link).
private struct OptionalTap: ViewModifier {
	var action: (() -> Void)?

	@ViewBuilder
	func body(content: Content) -> some View {
		if let action {
			content.onTapGesture(perform: action)
		} else {
			content
		}
	}
}
