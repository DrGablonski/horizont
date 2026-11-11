import SwiftUI

/// Schnell-Dialog „Neue Aufgabe / Neuer Termin“ als Sheet-Inhalt (wird von HomeView präsentiert).
/// Gemeinsame Felder: Titel (Focus beim Öffnen), Kalender (mit Farbpunkt).
/// Modus „Aufgabe“: optionale Kategorie und Fälligkeit.
/// Modus „Termin“: Datum+Uhrzeit mit Ganztägig-Schalter.
/// Speichert über store.createTask bzw. store.createEvent; bei Erfolg schließt sich der
/// Dialog und setzt die Felder zurück, sonst erscheint ein ErrorBanner.
struct QuickAddTaskView: View {
	/// Umgeschalteter Objekttyp des Dialogs.
	private enum Mode: Hashable {
		case task, event
	}

	@Environment(AppStore.self) private var store
	@Environment(\.dismiss) private var dismiss

	@State private var mode: Mode = .task
	@State private var summary = ""
	@State private var calendarId = ""
	@State private var category: String?
	@State private var hasDueDate = false
	@State private var dueDate = Date()
	@State private var eventDate = Date()
	@State private var isAllDay = false
	@State private var error: String?
	@State private var saving = false

	@FocusState private var summaryFocused: Bool

	/// Zur Auswahl stehen nur beschreibbare Kalender (Server-Rechte + kein Schreibschutz).
	private var writableCalendars: [CalendarView] { store.calendars.filter(\.writable) }

	/// initialEvent = true öffnet den Dialog direkt im Termin-Modus
	/// (Button „Neuer Termin“ auf der Startseite).
	init(initialEvent: Bool = false) {
		_mode = State(initialValue: initialEvent ? .event : .task)
	}

	/// Farbpunkt zu einem Hex-Wert – nutzt den bestehenden Helfer Color(hex:) aus Theme.swift
	/// (bewusst nicht dupliziert).
	private func dot(_ hex: String) -> some View {
		Circle()
			.fill(Color(hex: hex))
			.frame(width: 8, height: 8)
	}

	var body: some View {
		VStack(alignment: .leading, spacing: DS.Space.lg) {
			Text(mode == .task ? "Neue Aufgabe" : "Neuer Termin")
				.font(DS.Typo.cardTitle)
				.foregroundStyle(DS.textPrimary)

			// Typ-Umschaltung direkt unter dem Titel.
			Picker("Typ", selection: $mode) {
				Text("Aufgabe").tag(Mode.task)
				Text("Termin").tag(Mode.event)
			}
			.pickerStyle(.segmented)
			.labelsHidden()

			VStack(alignment: .leading, spacing: DS.Space.xs) {
				fieldLabel("Titel")
				TextField("Was ist zu tun?", text: $summary)
					.focused($summaryFocused)
			}

			VStack(alignment: .leading, spacing: DS.Space.xs) {
				fieldLabel("Kalender")
				if writableCalendars.isEmpty {
					Text(store.calendarsLoaded
						? "Kein beschreibbarer Kalender – das Ziel wählt der Server."
						: "Kalender werden geladen …")
						.font(DS.Typo.meta)
						.foregroundStyle(DS.textSecondary)
				} else {
					Picker(selection: $calendarId) {
						ForEach(writableCalendars, id: \.id) { cal in
							HStack(spacing: DS.Space.xs) {
								dot(cal.color)
								Text(cal.name)
								if let conn = cal.connectionName {
									Text("· \(conn)")
										.foregroundStyle(DS.textSecondary)
								}
								if cal.hidden {
									Text("(ausgeblendet)")
										.foregroundStyle(DS.textSecondary)
								}
							}
							.tag(cal.id)
						}
					} label: {
						Text("Kalender")
					}
					.labelsHidden()
				}
			}

			if mode == .task {
				// MARK: Aufgabe – Kategorie + Fälligkeit (unverändert)

				if !store.categories.isEmpty {
					VStack(alignment: .leading, spacing: DS.Space.xs) {
						fieldLabel("Kategorie")
						Picker(selection: $category) {
							Text("Ohne Kategorie").tag(Optional<String>.none)
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
				// MARK: Termin – Datum + Uhrzeit, bei Ganztägig ohne Uhrzeit

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
							Text("Wird angelegt …")
						}
					} else {
						Text(mode == .task ? "Aufgabe anlegen" : "Termin anlegen")
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
			if calendarId.isEmpty {
				// Vorauswahl: Standardkalender, sonst erster beschreibbarer Kalender.
				calendarId = writableCalendars.first(where: \.isDefault)?.id
					?? writableCalendars.first?.id ?? ""
			}
			// Fokus, sobald das Sheet aufgebaut ist.
			Task { @MainActor in
				try? await Task.sleep(for: .milliseconds(120))
				summaryFocused = true
			}
		}
	}

	// MARK: – Speichern

	private var canSave: Bool {
		// Ohne Kalender-Auswahl entscheidet der Server (Standardkalender).
		!summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
	}

	private func save() {
		guard canSave, !saving else { return }
		saving = true
		error = nil
		let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
		let targetCalendar = calendarId.isEmpty ? nil : calendarId
		Task {
			let failure: String?
			if mode == .task {
				// dueKey im Web-Format yyyy-MM-dd (Formatierer aus Fmt, Locale de).
				let dueKey = hasDueDate ? Fmt.dayKeyFormatter.string(from: dueDate) : nil
				failure = await store.createTask(
					summary: trimmed, calendarId: targetCalendar, category: category, dueKey: dueKey)
			} else {
				// dayKey = yyyy-MM-dd; startMs nur bei Uhrzeit als Epoch-Millisekunden.
				let dayKey = Fmt.dayKeyFormatter.string(from: eventDate)
				let startMs = isAllDay ? nil : Int((eventDate.timeIntervalSince1970 * 1000).rounded())
				failure = await store.createEvent(
					summary: trimmed, calendarId: targetCalendar, dayKey: dayKey,
					allDay: isAllDay, startMs: startMs)
			}
			saving = false
			if let failure {
				error = failure
			} else {
				// Erfolg: Felder zurücksetzen und Dialog schließen.
				summary = ""
				category = nil
				hasDueDate = false
				dueDate = Date()
				eventDate = Date()
				isAllDay = false
				error = nil
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
