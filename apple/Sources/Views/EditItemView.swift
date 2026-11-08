import SwiftUI

/// Bearbeiten-Dialog für eine bestehende Aufgabe bzw. einen bestehenden Termin
/// als Sheet-Inhalt (wird von EventDetailView präsentiert). Gleicher Look wie
/// QuickAddTaskView (Breite 420, Padding DS.Space.xl, Hintergrund DS.card),
/// aber eigene Datei mit eigenen privaten Helfern – QuickAdd bleibt unverändert.
/// Speichert über store.updateTaskEdit bzw. store.updateEventEdit; bei Erfolg
/// schließt sich der Dialog (der Store lädt die Timeline ohnehin neu), sonst
/// erscheint ein ErrorBanner.
struct EditItemView: View {
	/// Zu bearbeitendes Event (unveränderliche Referenz für Vorbelegung + Update).
	private let event: EventItem

	@Environment(AppStore.self) private var store
	@Environment(\.dismiss) private var dismiss

	// Gemeinsame Felder
	@State private var summary: String
	@State private var error: String?
	@State private var saving = false

	// Aufgaben-Felder
	@State private var category: String?
	@State private var hasDueDate: Bool
	@State private var dueDate: Date

	// Termin-Felder
	@State private var location: String
	@State private var isAllDay: Bool
	@State private var eventDate: Date

	@FocusState private var summaryFocused: Bool

	private var isTask: Bool { event.kind == "task" }

	init(event: EventItem) {
		self.event = event
		// Vorbelegung: Tasks nutzen dueKey (Fallback startMs),
		// Termine startMs als Datum + Uhrzeit.
		let start = Date(timeIntervalSince1970: Double(event.startMs) / 1000)
		_summary = State(initialValue: event.summary)
		_category = State(initialValue: event.category)
		_hasDueDate = State(initialValue: event.dueKey != nil)
		_dueDate = State(initialValue: event.dueKey.flatMap(Fmt.dayKey) ?? start)
		_location = State(initialValue: event.location ?? "")
		_isAllDay = State(initialValue: event.allDay)
		_eventDate = State(initialValue: start)
	}

	/// Farbpunkt zu einem Hex-Wert – nutzt Color(hex:) aus Theme.swift.
	private func dot(_ hex: String) -> some View {
		Circle()
			.fill(Color(hex: hex))
			.frame(width: 8, height: 8)
	}

	var body: some View {
		VStack(alignment: .leading, spacing: DS.Space.lg) {
			Text(isTask ? "Aufgabe bearbeiten" : "Termin bearbeiten")
				.font(DS.Typo.cardTitle)
				.foregroundStyle(DS.textPrimary)

			VStack(alignment: .leading, spacing: DS.Space.xs) {
				fieldLabel("Titel")
				TextField("Titel", text: $summary)
					.focused($summaryFocused)
			}

			if isTask {
				// MARK: Aufgabe – Kategorie + Fälligkeit

				if !store.categories.isEmpty {
					VStack(alignment: .leading, spacing: DS.Space.xs) {
						fieldLabel("Kategorie")
						Picker(selection: $category) {
							// Remove-Marker: Auswahl entfernt die bestehende Kategorie.
							Text(event.category == nil
							    	? "Ohne Kategorie" : "Kategorie entfernen")
								.tag(Optional<String>.none)
							ForEach(store.categories, id: \.name) { cat in
								HStack(spacing: DS.Space.xs) {
									dot(cat.color)
									Text(cat.name)
								}
								.tag(Optional(cat.name))
							}
						} label: {
							Text("Kategorie")
						}
						.labelsHidden()
					}
				}

				VStack(alignment: .leading, spacing: DS.Space.xs) {
					HStack(spacing: DS.Space.sm) {
						fieldLabel("Fällig am")
						Spacer(minLength: DS.Space.sm)
						Toggle("", isOn: $hasDueDate)
							.toggleStyle(.switch)
							.controlSize(.mini)
							.labelsHidden()
					}
					if hasDueDate {
						DatePicker("", selection: $dueDate, displayedComponents: .date)
							.labelsHidden()
					}
				}
			} else {
				// MARK: Termin – Ort + Datum/Uhrzeit (Ganztägig-Schalter)

				VStack(alignment: .leading, spacing: DS.Space.xs) {
					fieldLabel("Ort")
					TextField("Wo?", text: $location)
				}

				VStack(alignment: .leading, spacing: DS.Space.xs) {
					HStack(spacing: DS.Space.sm) {
						fieldLabel("Termin am")
						Spacer(minLength: DS.Space.sm)
						Toggle("Ganztägig", isOn: $isAllDay)
							.font(DS.Typo.meta)
							.toggleStyle(.switch)
							.controlSize(.mini)
					}
					DatePicker("", selection: $eventDate,
					           displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute])
						.labelsHidden()
				}
			}

			if let error {
				ErrorBanner(message: error)
			}

			HStack(spacing: DS.Space.sm) {
				Button("Abbrechen") { dismiss() }
					.ghostButton()
					.keyboardShortcut(.cancelAction)
				Spacer(minLength: DS.Space.sm)
				Button(action: save) {
					if saving {
						HStack(spacing: DS.Space.xs) {
							ProgressView().controlSize(.small)
							Text("Wird gespeichert …")
						}
					} else {
						Text(isTask ? "Aufgabe speichern" : "Termin speichern")
					}
				}
				.keyboardShortcut(.defaultAction)
				.primaryButton()
				.disabled(saving || !canSave)
			}
			.padding(.top, DS.Space.xxs)
		}
		.padding(DS.Space.xl)
		.frame(width: 420)
		.background(DS.card)
		.onAppear {
			// Fokus, sobald das Sheet aufgebaut ist.
			Task { @MainActor in
				try? await Task.sleep(for: .milliseconds(120))
				summaryFocused = true
			}
		}
	}

	// MARK: – Speichern

	private var canSave: Bool {
		!summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
	}

	private func save() {
		guard canSave, !saving else { return }
		saving = true
		error = nil
		let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
		Task {
			let failure: String?
			if isTask {
				// dueKey im Web-Format yyyy-MM-dd (Formatter aus Fmt, Locale de).
				let dueKey = hasDueDate ? Fmt.dayKeyFormatter.string(from: dueDate) : nil
				// Remove-Marker: Toggle aus bzw. „Kategorie entfernen“ → explizit löschen.
				let clearDue = !hasDueDate && event.dueKey != nil
				let clearCategory = category == nil && event.category != nil
				failure = await store.updateTaskEdit(
					event, summary: trimmed, category: category, dueKey: dueKey,
					clearDue: clearDue, clearCategory: clearCategory)
			} else {
				// dayKey = yyyy-MM-dd; startMs nur bei Uhrzeit als Epoch-ms.
				// endMs wird nicht gesendet (der Store übergibt nil an die API) –
				// das bestehende Ende bleibt unverändert.
				let dayKey = Fmt.dayKeyFormatter.string(from: eventDate)
				let startMs = isAllDay
					? nil : Int((eventDate.timeIntervalSince1970 * 1000).rounded())
				let loc = location.trimmingCharacters(in: .whitespacesAndNewlines)
				failure = await store.updateEventEdit(
					event, summary: trimmed, allDay: isAllDay, dayKey: dayKey,
					startMs: startMs, location: loc.isEmpty ? nil : loc)
			}
			saving = false
			if let failure {
				error = failure
			} else {
				// Erfolg: Store hat die Timeline neu geladen, Dialog schließen.
				dismiss()
			}
		}
	}

	private func fieldLabel(_ text: String) -> some View {
		Text(text)
			.font(DS.Typo.metaStrong)
			.foregroundStyle(DS.textSecondary)
	}
}
