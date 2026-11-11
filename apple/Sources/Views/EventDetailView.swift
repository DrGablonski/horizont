import SwiftUI

/// Kompakte Detailansicht eines Events als Popover-Inhalt (~340 pt):
/// Farbstreifen, Titel, Datum/Zeit, Ort, Beschreibung, Kategorie und
/// bei Tasks ein Abhaken-Button mit Status-Chip.
struct EventDetailView: View {
	let event: EventItem
	var onToggle: () async -> Void = {}
	/// Öffnet den Bearbeiten-Dialog im Hauptfenster (Sheets aus dem Popover
	/// heraus erscheinen auf dem Mac nicht – nur die Abdunkelung).
	var onEdit: (EventItem) -> Void = { _ in }
	/// Löst die Löschbestätigung im Hauptfenster aus (gleicher Grund wie oben).
	var onRequestDelete: (EventItem) -> Void = { _ in }

	@Environment(AppStore.self) private var store

	@State private var toggling = false

	private var isTask: Bool { event.kind == "task" }
	private var isDone: Bool { event.completed ?? false }

	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			colorStripe
				.frame(height: 5)
			VStack(alignment: .leading, spacing: DS.Space.md) {
				summaryHeader
				dateRow
				if let location = event.location, !location.isEmpty {
					metaRow(systemImage: "mappin", text: location)
				}
				if let description = event.description, !description.isEmpty {
					Text(description)
						.font(.callout)
						.foregroundStyle(DS.textSecondary)
						.fixedSize(horizontal: false, vertical: true)
				}
				chipRow
				if isTask {
					Divider()
					taskActionRow
				}
				Divider()
				deleteRow
			}
			.padding(DS.Space.lg)
		}
		.frame(width: 340)
		.background(DS.card)
	}

	// MARK: – Kopf

	/// Farbstreifen aus Kalender- und (bei Tasks) Kategorienfarbe.
	@ViewBuilder
	private var colorStripe: some View {
		if let categoryColor = event.categoryColor {
			LinearGradient(
				colors: [Color(hex: event.calendarColor), Color(hex: categoryColor)],
				startPoint: .leading, endPoint: .trailing)
		} else {
			Rectangle().fill(Color(hex: event.calendarColor))
		}
	}

	/// Titel + Kalender, rechts ein dezenter Bearbeiten-Button (öffnet den
	/// Bearbeiten-Dialog als Sheet im Hauptfenster via onEdit).
	private var summaryHeader: some View {
		HStack(alignment: .top, spacing: DS.Space.sm) {
			VStack(alignment: .leading, spacing: DS.Space.xs) {
				Text(event.summary)
					.font(.title3.weight(.semibold))
					.foregroundStyle(isDone ? DS.textSecondary : DS.textPrimary)
					.strikethrough(isDone)
				Text(event.calendarName)
					.font(DS.Typo.meta)
					.foregroundStyle(DS.textTertiary)
			}
			Spacer(minLength: DS.Space.xs)
			Button(action: startEditing) {
				Image(systemName: "pencil")
					.font(DS.Typo.metaStrong)
					.foregroundStyle(DS.textSecondary)
			}
			.ghostButton()
			.help("Bearbeiten")
			.accessibilityLabel("Bearbeiten")
		}
	}

	/// Öffnet den Bearbeiten-Dialog über den Callback der Eltern-View (Sheet
	/// im Hauptfenster); bei Tasks vorher Kategorien nachladen, falls noch
	/// keine bekannt sind (für das Kategorie-Menü im Sheet).
	private func startEditing() {
		if isTask && store.categories.isEmpty {
			Task { await store.loadCategories() }
		}
		onEdit(event)
	}

	// MARK: – Datum & Zeit

	/// "Donnerstag, 6. November 2025" plus Uhrzeit (bzw. "Ganztägig").
	private var dateRow: some View {
		HStack(spacing: DS.Space.sm) {
			Image(systemName: "calendar")
				.font(DS.Typo.metaStrong)
				.foregroundStyle(DS.textSecondary)
			VStack(alignment: .leading, spacing: DS.Space.xxs) {
				Text(dayText)
					.font(DS.Typo.rowTitle)
					.foregroundStyle(DS.textPrimary)
				Text(timeText)
					.font(DS.Typo.meta.monospacedDigit())
					.foregroundStyle(DS.textSecondary)
			}
		}
	}

	/// Wochentag + Datum, abgeleitet vom dayKey (Tasks: Fälligkeit).
	private var dayText: String {
		let key = isTask ? (event.dueKey ?? dayKeyFromStart) : dayKeyFromStart
		guard let date = Fmt.dayKey(key) else { return key }
		return Self.dayFormatter.string(from: date)
	}

	private var timeText: String {
		if event.allDay { return "Ganztägig" }
		return Fmt.time(event.startMs) + " – " + Fmt.time(event.endMs)
	}

	private var dayKeyFromStart: String {
		Fmt.dayKeyFormatter.string(from: Date(timeIntervalSince1970: Double(event.startMs) / 1000))
	}

	// MARK: – Chips & Task-Aktion

	@ViewBuilder
	private var chipRow: some View {
		let chips: [AnyView] = {
			var result: [AnyView] = []
			if isTask, let category = event.category {
				result.append(AnyView(Chip(text: category, color: Color(hex: event.categoryColor))))
			}
			if event.overdue == true {
				result.append(AnyView(Chip(text: "überfällig", color: DS.danger, systemImage: "exclamationmark")))
			}
			return result
		}()
		if !chips.isEmpty {
			HStack(spacing: DS.Space.sm) {
				ForEach(chips.indices, id: \.self) { i in chips[i] }
				Spacer(minLength: 0)
			}
		}
	}

	private var taskActionRow: some View {
		HStack(spacing: DS.Space.md) {
			Chip(
				text: isDone ? "erledigt" : "offen",
				color: isDone ? DS.success : DS.textSecondary,
				systemImage: isDone ? "checkmark.circle.fill" : "circle")
			Spacer(minLength: DS.Space.sm)
			Button {
				guard !toggling else { return }
				toggling = true
				Task {
					await onToggle()
					toggling = false
				}
			} label: {
				Label(isDone ? "Wieder öffnen" : "Abhaken",
				      systemImage: isDone ? "circle" : "checkmark.circle.fill")
			}
			.disabled(toggling)
		}
	}

	/// Dezenter Löschbereich am Ende (für Events und Tasks).
	/// Die Bestätigung selbst zeigt die Eltern-View (HomeView), damit der
	/// Dialog nicht im Popover-Fenster hängt und dort untergeht.
	private var deleteRow: some View {
		HStack(spacing: DS.Space.sm) {
			Spacer(minLength: 0)
			Button {
				onRequestDelete(event)
			} label: {
				Label("Löschen", systemImage: "trash")
					.font(.callout)
					.foregroundStyle(DS.danger)
			}
			.ghostButton()
		}
	}

	private func metaRow(systemImage: String, text: String) -> some View {
		HStack(spacing: DS.Space.sm) {
			Image(systemName: systemImage)
				.font(DS.Typo.metaStrong)
				.foregroundStyle(DS.textSecondary)
			Text(text)
				.font(.callout)
				.foregroundStyle(DS.textSecondary)
				.fixedSize(horizontal: false, vertical: true)
		}
	}

	private static let dayFormatter: DateFormatter = {
		let f = DateFormatter()
		f.locale = Locale(identifier: "de_DE")
		f.dateFormat = "EEEE, d. MMMM yyyy"
		return f
	}()
}
