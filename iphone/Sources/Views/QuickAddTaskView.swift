import SwiftUI

/// Schnell-Dialog „Neue Aufgabe / Neuer Termin“ als Blatt (wird von HomeView präsentiert).
/// Native iPhone-Form: gruppierte Liste, Typ-Umschaltung oben, Titel-Feld mit
/// Auto-Fokus direkt darunter (gut erreichbar, Tastatur schiebt die Speichern-Leiste
/// nach oben), Rest als native Menüs und Datumsfelder.
/// Speichert über store.createTask bzw. store.createEvent; bei Erfolg schließt sich der
/// Dialog und setzt die Felder zurück, sonst erscheint ein ErrorBanner.
struct QuickAddTaskView: View {
	/// Umgeschalteter Objekttyp des Dialogs.
	enum Mode: Hashable {
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

	/// Öffnet den Dialog im gewünschten Modus, optional mit übernommenem Text
	/// (aus dem Schnell-Eingabefeld der Startseite) und Startdatum. Ein mitge-
	/// gabenes Datum setzt beim Typ entsprechend Fälligkeit bzw. Terminzeit.
	init(kind: Mode = .task, initialSummary: String = "", initialDate: Date? = nil) {
		_mode = State(initialValue: kind)
		_summary = State(initialValue: initialSummary)
		if let initialDate {
			_eventDate = State(initialValue: initialDate)
			_dueDate = State(initialValue: initialDate)
			if kind == .task {
				_hasDueDate = State(initialValue: true)
			}
		}
	}

	/// Farbpunkt zu einem Hex-Wert – nutzt den bestehenden Helfer Color(hex:) aus Theme.swift
	/// (bewusst nicht dupliziert).
	private func dot(_ hex: String) -> some View {
		Circle()
			.fill(Color(hex: hex))
			.frame(width: 8, height: 8)
	}

	var body: some View {
		NavigationStack {
			Form {
				// Typ-Umschaltung ganz oben – darunter folgt das Fokus-Feld.
				Section {
					Picker("Typ", selection: $mode) {
						Text("Aufgabe").tag(Mode.task)
						Text("Termin").tag(Mode.event)
					}
					.pickerStyle(.segmented)
					.labelsHidden()
					.listRowSeparator(.hidden)
				}

				Section {
					TextField("Was ist zu tun?", text: $summary)
						.focused($summaryFocused)
						.textInputAutocapitalization(.sentences)
						.onSubmit(save)
				}

				Section("Kalender") {
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
					// MARK: Aufgabe – Kategorie + Fälligkeit

					if !store.categories.isEmpty {
						Picker("Kategorie", selection: $category) {
							Text("Ohne Kategorie").tag(Optional<String>.none)
							ForEach(store.categories, id: \.name) { cat in
								HStack(spacing: DS.Space.xs) {
									dot(cat.color)
									Text(cat.name)
								}
								.tag(Optional(cat.name))
							}
						}
					}

					Section {
						Toggle("Fällig am", isOn: $hasDueDate)
						if hasDueDate {
							DatePicker("Datum", selection: $dueDate, displayedComponents: .date)
						}
					}
				} else {
					// MARK: Termin – Datum + Uhrzeit, bei Ganztägig ohne Uhrzeit

					Section {
						Toggle("Ganztägig", isOn: $isAllDay)
						DatePicker("Termin am", selection: $eventDate,
						           displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute])
					}
				}

				if let error {
					Section {
						ErrorBanner(message: error)
							.listRowBackground(Color.clear)
							.listRowSeparator(.hidden)
					}
				}
			}
			.formStyle(.grouped)
			.scrollDismissesKeyboard(.interactively)
			.navigationTitle(mode == .task ? "Neue Aufgabe" : "Neuer Termin")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("Abbrechen") { dismiss() }
				}
			}
			.safeAreaInset(edge: .bottom, spacing: 0) { saveBar }
		}
		// Kompaktes Blatt – lässt sich über den Ziehgriff vergrößern.
		.presentationDetents([.medium, .large])
		.onAppear {
			if calendarId.isEmpty {
				// Vorauswahl: Standardkalender, sonst erster beschreibbarer Kalender.
				calendarId = writableCalendars.first(where: \.isDefault)?.id
					?? writableCalendars.first?.id ?? ""
			}
		}
		.task {
			// Fokus, sobald das Blatt aufgebaut ist.
			try? await Task.sleep(for: .milliseconds(120))
			summaryFocused = true
		}
	}

	// MARK: – Speichern

	/// Primär-Button unten – liegt über Tastatur und Home-Indikator.
	private var saveBar: some View {
		VStack(spacing: 0) {
			Divider()
			Button(action: save) {
				if saving {
					HStack(spacing: DS.Space.xs) {
						ProgressView().controlSize(.small)
						Text("Wird angelegt …")
					}
				} else {
					Text("Speichern")
				}
			}
			.primaryButton()
			.disabled(saving || !canSave)
			.padding(.horizontal, DS.Space.lg)
			.padding(.top, DS.Space.sm)
			.padding(.bottom, DS.Space.xs)
		}
		.background(.bar)
	}

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
}
