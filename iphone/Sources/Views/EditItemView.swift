import SwiftUI

/// Bearbeiten-Dialog für eine bestehende Aufgabe bzw. einen bestehenden Termin
/// als eigenes iPhone-Sheet: gruppiertes Formular mit Abbrechen/Speichern in
/// der Werkzeugleiste. Speichert über store.updateTaskEdit bzw.
/// store.updateEventEdit; bei Erfolg schließt sich das Sheet (der Store lädt
/// die Timeline ohnehin neu), sonst erscheint ein ErrorBanner im Formular.
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

	/// Kalender des Eintrags (Info: Sichtbarkeit) – Verschieben zwischen Kalendern bietet die API nicht.
	private var itemCalendar: CalendarView? {
		store.calendars.first { $0.id == event.calendarId }
	}

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

	var body: some View {
		NavigationStack {
			Form {
				Section {
					TextField("Titel", text: $summary)
						.focused($summaryFocused)
					// Kalender (nur Info, ohne Auswahl): Einträge bleiben in ihrem Kalender.
					LabeledContent("Kalender") {
						HStack(spacing: DS.Space.xs) {
							dot(event.calendarColor)
							Text(event.calendarName)
								.foregroundStyle(DS.textPrimary)
							if itemCalendar?.hidden == true {
								Text("(ausgeblendet)")
									.font(DS.Typo.meta)
									.foregroundStyle(DS.textSecondary)
							}
						}
					}
				}

				if isTask {
					// MARK: Aufgabe – Kategorie + Fälligkeit

					if !store.categories.isEmpty {
						Section("Kategorie") {
							Picker("Kategorie", selection: $category) {
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
							}
						}
					}

					Section("Fälligkeit") {
						Toggle("Fällig am", isOn: $hasDueDate)
						if hasDueDate {
							DatePicker("Datum", selection: $dueDate, displayedComponents: .date)
						}
					}
				} else {
					// MARK: Termin – Ort + Datum/Uhrzeit (Ganztägig-Schalter)

					Section("Termin") {
						Toggle("Ganztägig", isOn: $isAllDay)
						DatePicker("Am", selection: $eventDate,
						           displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute])
					}

					Section("Ort") {
						TextField("Wo?", text: $location)
					}
				}

				if let error {
					Section {
						ErrorBanner(message: error)
							.listRowInsets(EdgeInsets())
							.listRowBackground(Color.clear)
					}
				}
			}
			.formStyle(.grouped)
			.scrollDismissesKeyboard(.interactively)
			.navigationTitle(isTask ? "Aufgabe bearbeiten" : "Termin bearbeiten")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("Abbrechen") { dismiss() }
						.keyboardShortcut(.cancelAction)
				}
				ToolbarItem(placement: .confirmationAction) {
					if saving {
						ProgressView().controlSize(.regular)
					} else {
						Button(action: save) { Text("Speichern") }
							.keyboardShortcut(.defaultAction)
							.disabled(!canSave)
					}
				}
			}
			.tint(DS.accent)
			.task {
				// Kategorien für das Auswahlmenü nachladen (falls noch leer).
				if isTask && store.categories.isEmpty {
					await store.loadCategories()
				}
				// Fokus, sobald das Sheet aufgebaut ist.
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

	/// Farbpunkt zu einem Hex-Wert – nutzt Color(hex:) aus Theme.swift.
	private func dot(_ hex: String) -> some View {
		Circle()
			.fill(Color(hex: hex))
			.frame(width: 8, height: 8)
	}
}
