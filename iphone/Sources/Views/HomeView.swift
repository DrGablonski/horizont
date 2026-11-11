import SwiftUI

/// Startseite (iPhone): die drei zusammenklappbaren Zeiträume als native
/// Listen-Sektionen – jeder Bereich eine aufklappbare `DisclosureGroup` mit
/// Zähler und Chevron, Tage als Kopfzeilen, Events als kompakte Zeilen.
///
/// iPhone-Interaktion statt iPad-Schleif-Geste: nach links wischen =
/// erledigen (`.swipeActions`, grün), nach rechts wischen = Löschen,
/// Kontextmenü = Erledigen/Details/Löschen. Details öffnen als Karten-Sheet
/// (der NavigationStack der Shell hält die Liste beim Blättern stabil; das
/// Sheet bringt seinen eigenen Stack für Bearbeiten/„Fertig“ mit).
/// Pull-to-Refresh über `.refreshable`; Neueinträge über das kompakte
/// Schnell-Eingabefeld ganz oben: direkt tippen und per Wischen anlegen
/// (links = Aufgabe, rechts = Termin) oder per Return/Stift-Button im
/// vollen Editor bearbeiten.
struct HomeView: View {
	@Environment(AppStore.self) private var store
	@State private var openPanels: [String: Bool] = [:]
	@State private var selectedEvent: EventItem?
	@State private var deleteCandidate: EventItem?

	// Schnell-Eingabefeld oben (Text, optionales Datum, Datepicker-Popover).
	@State private var composerText = ""
	@State private var composerDate = Date()
	@State private var composerHasDate = false
	@State private var composerDateOpen = false
	@State private var creationError: String?
	// Voller Editor (Quick-Add-Blatt) mit übernommenem Text/Datum.
	@State private var editorPresented = false
	@State private var editorText = ""
	@State private var editorAsEvent = false
	@State private var editorDate: Date?
	@FocusState private var composerFocused: Bool

	var body: some View {
		Group {
			if store.homeBusy && store.home == nil {
				TimelineSkeleton()
			} else if let home = store.home {
				content(home)
			} else {
				EmptyStateView(
					title: "Keine Verbindung",
					systemImage: "wifi.exclamationmark",
					description: store.homeError ?? "Server nicht erreichbar.",
					actionTitle: "Erneut versuchen",
					action: { Task { await store.loadHome() } })
			}
		}
		.navigationTitle("Horizont")
		.navigationBarTitleDisplayMode(.large)
		.sheet(item: $selectedEvent) { event in
			// Immer die aktuelle Version aus dem Store zeigen (nach Abhaken/Bearbeiten).
			EventDetailSheet(event: currentEvent(withID: event.id) ?? event)
		}
		.sheet(isPresented: $editorPresented) {
			QuickAddTaskView(
				kind: editorAsEvent ? .event : .task,
				initialSummary: editorText,
				initialDate: editorDate)
		}
		.alert(
			"Fehler beim Anlegen",
			isPresented: Binding(
				get: { creationError != nil },
				set: { if !$0 { creationError = nil } })
		) {
			Button("OK") { creationError = nil }
		} message: {
			Text(creationError ?? "")
		}
		.confirmationDialog(
			"Wirklich löschen?",
			isPresented: Binding(
				get: { deleteCandidate != nil },
				set: { if !$0 { deleteCandidate = nil } }
			),
			titleVisibility: .visible
		) {
			Button("Löschen", role: .destructive) {
				if let event = deleteCandidate {
					deleteCandidate = nil
					Task { await store.deleteItem(event) }
				}
			}
			Button("Abbrechen", role: .cancel) { deleteCandidate = nil }
		} message: {
			if let event = deleteCandidate {
				Text("„\(event.summary)“ wird dauerhaft aus dem Kalender entfernt.")
			}
		}
		.task {
			if store.home == nil { await store.loadHome() }
			if !store.calendarsLoaded { await store.loadCalendars() }
		}
	}

	// MARK: – Inhalt (Liste)

	@ViewBuilder
	private func content(_ home: MainEventsResponse) -> some View {
		List {
			// Schnell-Eingabefeld immer ganz oben – direkt über den Bereichen.
			// Der Datumsbereich klappt darunter nach unten auf (platzsparend,
			// ganzer Monat sichtbar).
			Section {
				composerRow
					.listRowBackground(DS.card)
				if composerDateOpen {
					composerDateEditor
						.listRowBackground(DS.card)
				}
			}

			if store.calendars.count > 1 {
				// Schmalen Kalender-Chip-Streifen über der Timeline zeigen:
				// Tippen schaltet die Sichtbarkeit des Kalenders (Panels laden neu).
				Section {
					ScrollView(.horizontal, showsIndicators: false) {
						HStack(spacing: DS.Space.xs) {
							ForEach(store.calendars, id: \.id) { cal in
								calendarChip(cal)
							}
						}
						.padding(.vertical, DS.Space.sm)
					}
					.listRowBackground(DS.card)
				}
			}

			if let err = store.homeError {
				Section {
					ErrorBanner(message: err, retry: { Task { await store.loadHome() } })
						.listRowBackground(DS.card)
				}
			}

			if !home.configured {
				Section {
					Label(
						"CalDAV ist auf dem Server noch nicht eingerichtet.",
						systemImage: "exclamationmark.triangle")
						.font(DS.Typo.meta)
						.foregroundStyle(DS.textSecondary)
						.listRowBackground(DS.card)
				}
			}

			if home.panels.allSatisfy({ $0.eventCount == 0 }) {
				Section {
					EmptyStateView(
						title: "Keine Einträge",
						systemImage: "calendar.day.timeline.left",
						description: "In deinem Kalender liegen aktuell keine Termine oder Aufgaben.")
						.listRowBackground(DS.card)
				}
			} else {
				ForEach(home.panels) { panel in
					Section {
						panelDisclosure(panel)
					}
				}
			}
		}
		.listStyle(.insetGrouped)
		.scrollContentBackground(.hidden)   // Ambient-Hintergrund der Shell scheinen durch
		.refreshable { await store.loadHome() }
	}

	/// Ein Chip im Streifen: Farb-Punkt + Name, ausgeblendete Kalender abgeblendet.
	private func calendarChip(_ cal: CalendarView) -> some View {
		Button {
			Task { await store.toggleCalendarVisibility(cal.id) }
		} label: {
			HStack(spacing: DS.Space.xs) {
				Circle()
					.fill(Color(hex: cal.color))
					.frame(width: 8, height: 8)
				Text(cal.name).font(DS.Typo.chip)
			}
			.foregroundStyle(cal.hidden ? DS.textTertiary : DS.textSecondary)
			.padding(.horizontal, 10)
			.padding(.vertical, 6)
			.background(Capsule().fill(DS.fillSubtle))
			.overlay(
				Capsule().strokeBorder(cal.hidden ? Color.clear : DS.border, lineWidth: 1)
			)
			.opacity(cal.hidden ? 0.5 : 1)
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.accessibilityLabel(cal.hidden ? "Kalender \(cal.name) einblenden" : "Kalender \(cal.name) ausblenden")
	}

	// MARK: – Bereiche (aufklappbar)

	/// Ein Zeitraum als aufklappbare Gruppe: Kopf mit Icon, Titel/Subtitle und
	/// Zähler (Chevron ergänzt die Liste selbst), darunter Tage mit Events.
	@ViewBuilder
	private func panelDisclosure(_ panel: TimePanel) -> some View {
		DisclosureGroup(isExpanded: expandedBinding(for: panel)) {
			if panel.days.isEmpty {
				Text("Keine Einträge in diesem Zeitraum.")
					.font(DS.Typo.meta)
					.foregroundStyle(DS.textSecondary)
					.listRowBackground(DS.card)
			} else {
				ForEach(panel.days) { day in
					dayHeader(day)
					ForEach(day.events) { event in
						eventRow(event)
					}
				}
			}
		} label: {
			panelLabel(panel)
		}
		.listRowBackground(DS.card)
	}

	/// Kopfzeile eines Bereichs (als Inhalt des DisclosureGroup-Labels).
	private func panelLabel(_ panel: TimePanel) -> some View {
		HStack(spacing: DS.Space.sm) {
			panelIcon(panel)
			VStack(alignment: .leading, spacing: DS.Space.xxs) {
				Text(panel.title)
					.font(.subheadline.weight(.semibold))
					.foregroundStyle(DS.textPrimary)
				Text(panel.subtitle)
					.font(DS.Typo.meta)
					.foregroundStyle(DS.textSecondary)
			}
			Spacer(minLength: DS.Space.xs)
			if panel.eventCount > 0 {
				Chip(text: "\(panel.eventCount)", color: DS.textSecondary)
			}
		}
		.padding(.vertical, DS.Space.xs)
		.contentShape(Rectangle())
	}

	/// Kleine Bereichs-Icons (Vergangenheit/Jetzt/Zukunft) im Gruppenkopf.
	private func panelIcon(_ panel: TimePanel) -> some View {
		let (symbol, color): (String, Color) = {
			switch panel.id {
			case "past": return ("clock.arrow.circlepath", DS.textSecondary)
			case "now": return ("sparkles", DS.accent)
			default: return ("clock", DS.textSecondary)
			}
		}()
		return Image(systemName: symbol)
			.font(.system(size: 13, weight: .medium))
			.foregroundStyle(color)
			.frame(width: 26, height: 26)
			.background(
				RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
					.fill(DS.fillSubtle)
			)
	}

	/// Kopfzeile eines Tages innerhalb des Bereichs (heute hervorgehoben,
	/// überfällige Tage im Danger-Ton).
	@ViewBuilder
	private func dayHeader(_ day: DayGroup) -> some View {
		let hasOverdue = day.events.contains { $0.overdue == true }
		HStack(spacing: DS.Space.sm) {
			Text(day.label)
				.font(DS.Typo.metaStrong)
				.foregroundStyle(dayLabelColor(day, hasOverdue: hasOverdue))
			if day.isToday {
				Chip(text: "Heute", color: DS.accent)
			}
			Spacer(minLength: 0)
			Chip(text: "\(day.events.count)", color: DS.textTertiary)
		}
		.padding(.vertical, DS.Space.xs)
		.listRowBackground(DS.fillSubtle)
	}

	/// Events eines Tages als Zeile mit Wisch- und Kontextaktionen:
	/// wischen nach links = erledigen (nur Tasks, grün), nach rechts =
	/// Löschen; Tippen oder Kontextmenü „Details“ öffnet das Detail-Sheet.
	@ViewBuilder
	private func eventRow(_ event: EventItem) -> some View {
		EventRowView(
			event: event,
			onToggle: { await store.toggleTask(event) },
			onSelect: { selectedEvent = event })
		.listRowBackground(DS.card)
		.swipeActions(edge: .leading, allowsFullSwipe: true) {
			if event.kind == "task" {
				Button {
					Task { await store.toggleTask(event) }
				} label: {
					Label(event.completed == true ? "Wieder öffnen" : "Erledigen",
					      systemImage: event.completed == true ? "arrow.counterclockwise" : "checkmark.circle.fill")
				}
				.tint(DS.success)
			}
		}
		.swipeActions(edge: .trailing, allowsFullSwipe: false) {
			Button(role: .destructive) {
				requestDelete(event)
			} label: {
				Label("Löschen", systemImage: "trash")
			}
			.tint(DS.danger)
		}
		.contextMenu {
			if event.kind == "task" {
				Button {
					Task { await store.toggleTask(event) }
				} label: {
					Label(event.completed == true ? "Wieder öffnen" : "Erledigen",
					      systemImage: event.completed == true ? "arrow.counterclockwise" : "checkmark.circle")
				}
			}
			Button {
				selectedEvent = event
			} label: {
				Label("Details", systemImage: "info.circle")
			}
			Button(role: .destructive) {
				requestDelete(event)
			} label: {
				Label("Löschen", systemImage: "trash")
			}
		}
	}

	private func dayLabelColor(_ day: DayGroup, hasOverdue: Bool) -> Color {
		if day.isToday { return DS.textPrimary }
		if hasOverdue { return DS.danger }
		return DS.textSecondary
	}

	// MARK: – Schnell-Eingabefeld

	/// Kompakte Eingabezeile ganz oben: Textfeld + kleines Datumsfeld rechts.
	/// Wischen: kurz aufziehen → Button zum Antippen, durchwischen (Full-Swipe)
	/// → sofort anlegen. Links = Aufgabe, rechts = Termin. Tippen/Return →
	/// voller Editor.
	private var composerRow: some View {
		HStack(spacing: DS.Space.sm) {
			Image(systemName: "plus.circle.fill")
				.font(.system(size: 18))
				.foregroundStyle(DS.accent)
			TextField("Aufgabe oder Termin …", text: $composerText)
				.focused($composerFocused)
				.textInputAutocapitalization(.sentences)
				.onSubmit(openEditor)
			composerDateButton
		}
		.contentShape(Rectangle())
		.listRowSeparator(composerDateOpen ? .hidden : .automatic)
		.swipeActions(edge: .trailing, allowsFullSwipe: true) {
			Button("Aufgabe") { quickCreate(asEvent: false) }
				.tint(DS.success)
		}
		.swipeActions(edge: .leading, allowsFullSwipe: true) {
			Button("Termin") { quickCreate(asEvent: true) }
				.tint(DS.accent)
		}
	}

	/// Kleines Datumsfeld ganz rechts: Kalender-Icon, nach Auswahl das kompakte
	/// Datum in Akzentfarbe. Tippen klappt den Datumswähler direkt unter dem
	/// Eingabefeld auf (nach unten, dort ist Platz für den ganzen Monat).
	private var composerDateButton: some View {
		Button {
			withAnimation(.easeInOut(duration: 0.2)) {
				composerDateOpen.toggle()
			}
		} label: {
			if composerHasDate {
				HStack(spacing: DS.Space.xxs) {
					Image(systemName: "calendar")
						.font(.system(size: 12, weight: .medium))
					Text(composerDateLabel)
						.font(DS.Typo.meta.monospacedDigit())
				}
				.foregroundStyle(DS.accent)
				.padding(.horizontal, DS.Space.sm)
				.padding(.vertical, DS.Space.xs)
				.background(Capsule().fill(DS.tintSoft))
			} else {
				Image(systemName: "calendar")
					.font(.system(size: 15, weight: .medium))
					.foregroundStyle(DS.textSecondary)
					.padding(DS.Space.xs)
			}
		}
		.buttonStyle(.plain)
		.accessibilityLabel(composerHasDate ? "Datum ändern" : "Datum hinzufügen")
	}

	/// Aufgeklappter Datumswähler unter dem Eingabefeld: graphical month picker
	/// (volle Breite) plus separates Uhrzeit-Feld und Abbruch-/Übernehmen-Knopf.
	private var composerDateEditor: some View {
		VStack(alignment: .leading, spacing: DS.Space.sm) {
			DatePicker("Datum", selection: $composerDate, displayedComponents: .date)
				.datePickerStyle(.graphical)
				.tint(DS.accent)
				.labelsHidden()
			HStack {
				Text("Uhrzeit")
					.font(DS.Typo.meta)
					.foregroundStyle(DS.textSecondary)
				Spacer()
				DatePicker("Uhrzeit", selection: $composerDate,
				           displayedComponents: .hourAndMinute)
					.datePickerStyle(.compact)
					.labelsHidden()
			}
			HStack {
				// Text folgt dem Zustand: mit aktivem Datum darf man es nur noch
				// entfernen, ein Abbruch wäre falsch (das Chip zeigt es bereits).
				Button(composerHasDate ? "Datum entfernen" : "Abbrechen") {
					composerHasDate = false
					withAnimation(.easeInOut(duration: 0.2)) {
						composerDateOpen = false
					}
				}
				.foregroundStyle(DS.textSecondary)
				Spacer()
				Button("Fertig") {
					composerHasDate = true
					withAnimation(.easeInOut(duration: 0.2)) {
						composerDateOpen = false
					}
				}
				.buttonStyle(.borderedProminent)
			}
		}
		// Tag antippen setzt das Datum automatisch, ohne extra „Fertig“.
		.onChange(of: composerDate) { _, _ in
			composerHasDate = true
		}
	}

	/// Kompakte Datumsanzeige im Feld (heute/morgen sonst TT.MM.).
	private var composerDateLabel: String {
		let cal = Calendar.current
		let f = DateFormatter()
		f.locale = Locale(identifier: "de_DE")
		if cal.isDateInToday(composerDate) { return "Heute" }
		if cal.isDateInTomorrow(composerDate) { return "Morgen" }
		f.dateFormat = "dd.MM."
		return f.string(from: composerDate)
	}

	// MARK: – Aktionen & Klapp-Zustand

	/// Schnellanlage per Wisch: ohne Kalender-/Kategorie-Auswahl (Server wählt
	/// Standardkalender); Datum nur wenn im Feld gesetzt, sonst heute ganztägig.
	private func quickCreate(asEvent: Bool) {
		let text = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !text.isEmpty else { return }
		composerFocused = false
		Task {
			let failure: String?
			if asEvent {
				let dayKey = Fmt.dayKeyFormatter.string(from: composerDate)
				let startMs = composerHasDate
					? Int((composerDate.timeIntervalSince1970 * 1000).rounded())
					: nil
				failure = await store.createEvent(
					summary: text, calendarId: nil, dayKey: dayKey,
					allDay: !composerHasDate, startMs: startMs)
			} else {
				let dueKey = composerHasDate
					? Fmt.dayKeyFormatter.string(from: composerDate)
					: nil
				failure = await store.createTask(
					summary: text, calendarId: nil, category: nil, dueKey: dueKey)
			}
			if let failure {
				creationError = failure
			} else {
				composerText = ""
				composerHasDate = false
				withAnimation(.easeInOut(duration: 0.2)) {
					composerDateOpen = false
				}
			}
		}
	}

	/// Voller Editor mit übernommenem Text/Datum; Auswahl-Listen vorladen.
	private func openEditor() {
		composerFocused = false
		if !store.calendarsLoaded || store.categories.isEmpty {
			Task {
				await store.loadCalendars()
				await store.loadCategories()
			}
		}
		editorText = composerText
		editorDate = composerHasDate ? composerDate : nil
		editorAsEvent = false
		editorPresented = true
	}

	/// Bittet um Löschbestätigung (Dialog hängt an der Root-View der Startseite).
	private func requestDelete(_ event: EventItem) {
		deleteCandidate = event
	}

	/// Klapp-Zustand je Bereich; neu geladene Bereiche starten mit `defaultOpen`.
	private func expandedBinding(for panel: TimePanel) -> Binding<Bool> {
		Binding(
			get: { openPanels[panel.id] ?? panel.defaultOpen },
			set: { value in
				withAnimation(.easeInOut(duration: 0.2)) {
					openPanels[panel.id] = value
				}
			})
	}

	/// Aktuelle Version eines Events aus der Timeline (für das Detail-Sheet).
	private func currentEvent(withID id: String) -> EventItem? {
		guard let panels = store.home?.panels else { return nil }
		for panel in panels {
			for day in panel.days {
				if let event = day.events.first(where: { $0.id == id }) { return event }
			}
		}
		return nil
	}
}

// MARK: – Detail-Sheet

/// Detail-Sheet (iPhone): bettet `EventDetailView` (sonst Popover-Inhalt am
/// Pad) in einen eigenen NavigationStack mit „Fertig“-Button, dazu eigenes
/// Bearbeiten-Sheet und Löschbestätigung – Aufruf-Signatur des DetailViews
/// bleibt unverändert.
fileprivate struct EventDetailSheet: View {
	let event: EventItem

	@Environment(AppStore.self) private var store
	@Environment(\.dismiss) private var dismiss
	@State private var editingEvent: EventItem?
	@State private var deleteCandidate: EventItem?

	var body: some View {
		NavigationStack {
			ScrollView {
				EventDetailView(
					event: event,
					onToggle: { await store.toggleTask(event) },
					onEdit: { editingEvent = $0 },
					onRequestDelete: { deleteCandidate = $0 })
					.fixedSize(horizontal: false, vertical: true)
					.frame(maxWidth: .infinity)
					.padding(DS.Space.lg)
			}
			.background(DS.background)
			.navigationTitle("Details")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .confirmationAction) {
					Button("Fertig") { dismiss() }
				}
			}
			.sheet(item: $editingEvent) { event in
				EditItemView(event: event)
			}
			.confirmationDialog(
				"Wirklich löschen?",
				isPresented: Binding(
					get: { deleteCandidate != nil },
					set: { if !$0 { deleteCandidate = nil } }
				),
				titleVisibility: .visible
			) {
				Button("Löschen", role: .destructive) {
					if let event = deleteCandidate {
						deleteCandidate = nil
						Task {
							await store.deleteItem(event)
							// Sheet nur schließen, wenn der Eintrag wirklich weg ist.
							if !stillPresent(event) { dismiss() }
						}
					}
				}
				Button("Abbrechen", role: .cancel) { deleteCandidate = nil }
			} message: {
				if let event = deleteCandidate {
					Text("„\(event.summary)“ wird dauerhaft aus dem Kalender entfernt.")
				}
			}
		}
		.presentationDetents([.medium, .large])
		.presentationDragIndicator(.visible)
	}

	/// Prüft nach dem Löschen, ob der Eintrag noch in der Timeline liegt.
	private func stillPresent(_ event: EventItem) -> Bool {
		store.home?.panels.contains { panel in
			panel.days.contains { day in
				day.events.contains { $0.id == event.id }
			}
		} ?? false
	}
}
