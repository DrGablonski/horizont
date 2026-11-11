import SwiftUI

/// Kompakte Detailansicht eines Events (iPhone): Karte mit Farbstreifen,
/// Titel, Datum/Zeit, Ort, Beschreibung, Kategorie-Chips und Aktionen
/// (Abhaken, Bearbeiten, Löschen) als Aktionszeile am Kartenboden.
///
/// Wird von HomeView in einem NavigationStack-Sheet mit „Fertig“ gezeigt;
/// diese View liefert nur den Inhalt – kein eigener Stack, kein eigener
/// Hintergrund. Die Bestätigung fürs Löschen zeigt die Eltern-View.
struct EventDetailView: View {
	let event: EventItem
	var onToggle: () async -> Void = {}
	/// Öffnet den Bearbeiten-Dialog in der Eltern-View (Sheet).
	var onEdit: (EventItem) -> Void = { _ in }
	/// Löst die Löschbestätigung in der Eltern-View aus.
	var onRequestDelete: (EventItem) -> Void = { _ in }

	@Environment(AppStore.self) private var store

	@State private var toggling = false

	private var isTask: Bool { event.kind == "task" }
	private var isDone: Bool { event.completed ?? false }

	var body: some View {
		VStack(spacing: 0) {
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
				actionsRow
			}
			.padding(DS.Space.lg)
			.frame(maxWidth: .infinity, alignment: .leading)
		}
		.clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
		.dsCard()
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
	/// Bearbeiten-Dialog in der Eltern-View via onEdit).
	private var summaryHeader: some View {
		HStack(alignment: .top, spacing: DS.Space.sm) {
			VStack(alignment: .leading, spacing: DS.Space.xs) {
				Text(event.summary)
					.font(.title3.weight(.semibold))
					.foregroundStyle(isDone ? DS.textSecondary : DS.textPrimary)
					.strikethrough(isDone)
				HStack(spacing: DS.Space.xs) {
					Circle().fill(Color(hex: event.calendarColor)).frame(width: 6, height: 6)
					Text(event.calendarName)
						.font(DS.Typo.meta)
						.foregroundStyle(DS.textTertiary)
					Spacer(minLength: 0)
				}
			}
			Spacer(minLength: DS.Space.xs)
			Button(action: startEditing) {
				Image(systemName: "pencil")
					.font(DS.Typo.metaStrong)
					.foregroundStyle(DS.textSecondary)
			}
			.ghostButton()
			.accessibilityLabel("Bearbeiten")
		}
	}

	/// Öffnet den Bearbeiten-Dialog über den Callback der Eltern-View;
	/// bei Tasks vorher Kategorien nachladen, falls noch keine bekannt
	/// sind (für das Kategorie-Menü im Bearbeiten-Sheet).
	private func startEditing() {
		if isTask && store.categories.isEmpty {
			Task { await store.loadCategories() }
		}
		onEdit(event)
	}

	// MARK: – Datum & Zeit

	/// "Donnerstag, 6. November 2025" plus Uhrzeit (bzw. "Ganztägig").
	private var dateRow: some View {
		HStack(alignment: .firstTextBaseline, spacing: DS.Space.sm) {
			Image(systemName: "calendar")
				.font(DS.Typo.metaStrong)
				.foregroundStyle(DS.textSecondary)
			VStack(alignment: .leading, spacing: DS.Space.xxs) {
				Text((isTask ? "Fällig: " : "") + dayText)
					.font(DS.Typo.rowTitle)
					.foregroundStyle(DS.textPrimary)
				if !isTask {
					Text(timeText)
						.font(DS.Typo.meta.monospacedDigit())
						.foregroundStyle(DS.textSecondary)
				}
			}
			Spacer(minLength: 0)
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

	private static let dayFormatter: DateFormatter = {
		let f = DateFormatter()
		f.locale = Locale(identifier: "de_DE")
		f.dateFormat = "EEEE, d. MMMM yyyy"
		return f
	}()

	private func metaRow(systemImage: String, text: String) -> some View {
		HStack(alignment: .firstTextBaseline, spacing: DS.Space.sm) {
			Image(systemName: systemImage)
				.font(DS.Typo.metaStrong)
				.foregroundStyle(DS.textSecondary)
			Text(text)
				.font(DS.Typo.rowTitle)
				.foregroundStyle(DS.textPrimary)
			Spacer(minLength: 0)
		}
	}

	// MARK: – Chips

	@ViewBuilder
	private var chipRow: some View {
		let hasCategory = isTask && event.category != nil
		let isOverdue = event.overdue == true
		if hasCategory || isOverdue {
			HStack(spacing: DS.Space.sm) {
				if isTask, let category = event.category {
					Chip(text: category, color: Color(hex: event.categoryColor))
				}
				if isOverdue {
					Chip(text: "überfällig", color: DS.danger, systemImage: "exclamationmark")
				}
				Spacer(minLength: 0)
			}
		}
	}

	// MARK: – Aktionen (Bodenleiste der Karte)

	/// Status, Abhaken, Bearbeiten und Löschen als eine Zeile am Kartenboden –
	/// die Löschbestätigung selbst zeigt die Eltern-View (HomeView).
	private var actionsRow: some View {
		VStack(spacing: DS.Space.md) {
			Divider()
			if isTask {
				HStack(spacing: DS.Space.sm) {
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
							.frame(maxWidth: .infinity)
					}
					.buttonStyle(.bordered)
					.buttonBorderShape(.capsule)
					.controlSize(.regular)
					.disabled(toggling)
				}
			}
			HStack(spacing: DS.Space.sm) {
				Button {
					startEditing()
				} label: {
					Label("Bearbeiten", systemImage: "pencil")
						.frame(maxWidth: .infinity)
				}
				.buttonStyle(.bordered)
				.buttonBorderShape(.capsule)

				Button(role: .destructive) {
					onRequestDelete(event)
				} label: {
					Label("Löschen", systemImage: "trash")
						.frame(maxWidth: .infinity)
				}
				.buttonStyle(.bordered)
				.buttonBorderShape(.capsule)
			}
		}
	}
}
