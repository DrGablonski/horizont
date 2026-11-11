import SwiftUI

/// Startseite: die drei zusammenklappbaren Zeiträume wie im Web –
/// eigener Bereichskopf mit Aktion, Panels als Karten, Tage mit Kopfzeile
/// und Trennlinie, Events als klickbare Zeilen (Detail-Popover).
struct HomeView: View {
	/// Welcher Typ wird im Quick-Add-Sheet geöffnet (nil = Sheet zu).
	private enum QuickAddKind: String, Identifiable {
		case task, event
		var id: String { rawValue }
	}

	@Environment(AppStore.self) private var store
	@State private var openPanels: [String: Bool] = [:]
	@State private var selectedEvent: EventItem?
	@State private var editingEvent: EventItem?
	@State private var deleteCandidate: EventItem?
	@State private var quickAdd: QuickAddKind?

	var body: some View {
		VStack(spacing: 0) {
			SectionHeader("Horizont", subtitle: "Vergangenheit · Jetzt · Zukunft") {
				AccentPillButton(title: "Neue Aufgabe", systemImage: "plus") {
					openQuickAdd(.task)
				}
				.keyboardShortcut("n")
				.help("Neue Aufgabe (⌘N)")
				AccentPillButton(title: "Neuer Termin", systemImage: "calendar.badge.plus") {
					openQuickAdd(.event)
				}
				.keyboardShortcut("n", modifiers: [.command, .shift])
				.help("Neuer Termin (⌘⇧N)")
			}

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
		}
		.sheet(item: $quickAdd) { kind in
			QuickAddTaskView(initialEvent: kind == .event)
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
			initOpenPanels()
		}
	}

	// MARK: – Inhalt

	@ViewBuilder
	private func content(_ home: MainEventsResponse) -> some View {
		ScrollView {
			VStack(alignment: .leading, spacing: DS.Space.lg) {
				calendarChips
				if let err = store.homeError {
					ErrorBanner(message: err, retry: { Task { await store.loadHome() } })
				}
				if !home.configured {
					Label(
						"CalDAV ist auf dem Server noch nicht eingerichtet.",
						systemImage: "exclamationmark.triangle")
						.font(.callout)
						.foregroundStyle(DS.textSecondary)
				}
				if home.panels.allSatisfy({ $0.eventCount == 0 }) {
					EmptyStateView(
						title: "Keine Einträge",
						systemImage: "calendar.day.timeline.left",
						description: "In deinem Kalender liegen aktuell keine Termine oder Aufgaben.")
				} else {
					ForEach(home.panels) { panel in
						panelCard(panel)
					}
				}
			}
			.padding(.horizontal, DS.Space.xl)
			.padding(.vertical, DS.Space.lg)
			.frame(maxWidth: 780)
			.frame(maxWidth: .infinity)
		}
		.refreshable { await store.loadHome() }
	}

	/// Schmale Kalender-Chip-Zeile über der Timeline (nur bei mehr als einem Kalender):
	/// Klick schaltet die Sichtbarkeit des Kalenders (Panels laden sich neu).
	@ViewBuilder
	private var calendarChips: some View {
		if store.calendars.count > 1 {
			ScrollView(.horizontal, showsIndicators: false) {
				HStack(spacing: DS.Space.xs) {
					ForEach(store.calendars, id: \.id) { cal in
						calendarChip(cal)
					}
				}
			}
		}
	}

	/// Ein Chip: Farb-Punkt + Name, ausgeblendete Kalender abgeblendet.
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
			.padding(.horizontal, 7)
			.padding(.vertical, 3)
			.background(Capsule().fill(DS.fillSubtle))
			.overlay(
				Capsule().strokeBorder(cal.hidden ? Color.clear : DS.border, lineWidth: 1)
			)
			.opacity(cal.hidden ? 0.5 : 1)
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.help(cal.hidden ? "Kalender einblenden" : "Kalender ausblenden")
	}

	/// Panel als Karte: klickbarer Header (Titel, Subtitle, Zähler, Chevron) + Tage.
	@ViewBuilder
	private func panelCard(_ panel: TimePanel) -> some View {
		VStack(alignment: .leading, spacing: 0) {
			Button {
				togglePanel(panel)
			} label: {
				HStack(spacing: DS.Space.sm) {
					panelIcon(panel)
					VStack(alignment: .leading, spacing: DS.Space.xxs) {
						Text(panel.title)
							.font(.system(size: 15, weight: .semibold))
							.foregroundStyle(DS.textPrimary)
						Text(panel.subtitle)
							.font(DS.Typo.meta)
							.foregroundStyle(DS.textSecondary)
					}
					Spacer(minLength: DS.Space.sm)
					if panel.eventCount > 0 {
						Chip(text: "\(panel.eventCount)", color: DS.textSecondary)
					}
					Image(systemName: "chevron.down")
						.font(.caption.weight(.semibold))
						.foregroundStyle(DS.textSecondary)
						.rotationEffect(.degrees(isOpen(panel) ? 180 : 0))
				}
				.padding(.horizontal, DS.Space.lg)
				.padding(.vertical, DS.Space.md)
				.contentShape(Rectangle())
			}
			.buttonStyle(.plain)

			if isOpen(panel) {
				Divider().overlay(DS.border)
				VStack(alignment: .leading, spacing: DS.Space.lg) {
					if panel.days.isEmpty {
						Text("Keine Einträge in diesem Zeitraum.")
							.font(.subheadline)
							.foregroundStyle(DS.textSecondary)
							.padding(.vertical, DS.Space.xs)
					}
					ForEach(panel.days) { day in
						dayBlock(day)
					}
				}
				.padding(.horizontal, DS.Space.lg)
				.padding(.vertical, DS.Space.lg)
			}
		}
		.dsCard()
	}

	/// Kleine Bereichs-Icons (Vergangenheit/Jetzt/Zukunft) im Panel-Kopf.
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

	/// Tag-Block wie im Web: Kopfzeile mit Trennlinie (heute hervorgehoben,
	/// überfällige Tage im Danger-Ton), darunter die klickbaren Events.
	@ViewBuilder
	private func dayBlock(_ day: DayGroup) -> some View {
		let hasOverdue = day.events.contains { $0.overdue == true }
		VStack(alignment: .leading, spacing: DS.Space.sm) {
			HStack(spacing: DS.Space.sm) {
				Text(day.label)
					.font(.subheadline.weight(.semibold))
					.foregroundStyle(dayLabelColor(day, hasOverdue: hasOverdue))
				if day.isToday {
					Chip(text: "Heute", color: DS.accent)
				}
				Rectangle()
					.fill(DS.border)
					.frame(height: 1)
			}
			eventRows(day)
		}
	}

	/// Events eines Tages als klickbare Zeilen mit Detail-Popover.
	/// iPad: Wisch-Geste (rechts wischen = erledigen) + Kontextmenü;
	/// auf Mac entspricht das der rechten Maustaste.
	/// Der Popover-Zustand wird pro Zeile aus dem gemeinsamen `selectedEvent`
	/// abgeleitet: nur die angeklickte Zeile präsentiert, der Pfeil sitzt
	/// direkt über ihr (ein `.popover(item:)` an jeder Zeile würde immer die
	/// letzte Zeile verankern).
	@ViewBuilder
	private func eventRows(_ day: DayGroup) -> some View {
		ForEach(day.events) { event in
			EventRowView(
				event: event,
				onToggle: { await store.toggleTask(event) },
				onSelect: { selectedEvent = event })
			.swipeToComplete(
				enabled: event.kind == "task",
				completed: event.completed == true) {
				await store.toggleTask(event)
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
			.popover(isPresented: Binding(
				get: { selectedEvent?.id == event.id },
				set: { if !$0 { selectedEvent = nil } }
			)) {
				EventDetailView(
					event: event,
					onToggle: { await store.toggleTask(event) },
					onEdit: openEditor,
					onRequestDelete: requestDelete)
			}
		}
	}

	/// Öffnet den Bearbeiten-Dialog als Sheet im Hauptfenster und schließt
	/// vorher das Popover (Sheets aus dem Popover heraus gehen unter).
	private func openEditor(_ event: EventItem) {
		selectedEvent = nil
		editingEvent = event
	}

	/// Schließt das Popover und bittet im Hauptfenster um Löschbestätigung.
	private func requestDelete(_ event: EventItem) {
		selectedEvent = nil
		deleteCandidate = event
	}

	private func dayLabelColor(_ day: DayGroup, hasOverdue: Bool) -> Color {
		if day.isToday { return DS.textPrimary }
		if hasOverdue { return DS.danger }
		return DS.textSecondary
	}

	// MARK: – Aktionen & Klapp-Zustand

	private func openQuickAdd(_ kind: QuickAddKind) {
		// Auswahl-Listen für den Dialog bei Bedarf vorladen.
		if !store.calendarsLoaded || store.categories.isEmpty {
			Task {
				await store.loadCalendars()
				await store.loadCategories()
			}
		}
		quickAdd = kind
	}

	private func isOpen(_ panel: TimePanel) -> Bool {
		openPanels[panel.id] ?? panel.defaultOpen
	}

	private func togglePanel(_ panel: TimePanel) {
		withAnimation(.easeInOut(duration: 0.2)) {
			openPanels[panel.id] = !isOpen(panel)
		}
	}

	private func initOpenPanels() {
		guard let home = store.home, openPanels.isEmpty else { return }
		for panel in home.panels { openPanels[panel.id] = panel.defaultOpen }
	}
}
