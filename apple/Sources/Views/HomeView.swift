import SwiftUI

/// Startseite: die drei zusammenklappbaren Zeiträume wie im Web –
/// Panels als Karten, Tage mit Kopfzeile und Trennlinie, Events als
/// klickbare Zeilen (Detail-Popover) mit Abhaken für Tasks.
struct HomeView: View {
	@Environment(AppStore.self) private var store
	@State private var openPanels: [String: Bool] = [:]
	@State private var selectedEvent: EventItem?
	@State private var showQuickAdd = false

	var body: some View {
		NavigationStack {
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
			.refreshable { await store.loadHome() }
			.toolbar {
				ToolbarItem(placement: .primaryAction) {
					Button {
						// Auswahl-Listen für den Dialog bei Bedarf vorladen.
						if !store.calendarsLoaded || store.categories.isEmpty {
							Task {
								await store.loadCalendars()
								await store.loadCategories()
							}
						}
						showQuickAdd = true
					} label: {
						Label("Neue Aufgabe", systemImage: "plus")
					}
					.keyboardShortcut("n")
					.help("Neue Aufgabe (⌘N)")
				}
			}
			.sheet(isPresented: $showQuickAdd) {
				QuickAddTaskView()
			}
		}
		.task {
			if store.home == nil { await store.loadHome() }
			initOpenPanels()
		}
	}

	// MARK: – Inhalt

	@ViewBuilder
	private func content(_ home: MainEventsResponse) -> some View {
		ScrollView {
			VStack(alignment: .leading, spacing: DS.Space.lg) {
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
		.background(DS.background)
	}

	/// Panel als Karte: klickbarer Header (Titel, Subtitle, Zähler, Chevron) + Tage.
	@ViewBuilder
	private func panelCard(_ panel: TimePanel) -> some View {
		VStack(alignment: .leading, spacing: 0) {
			Button {
				togglePanel(panel)
			} label: {
				HStack(spacing: DS.Space.sm) {
					VStack(alignment: .leading, spacing: DS.Space.xxs) {
						Text(panel.title).font(DS.Typo.cardTitle)
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
				Divider()
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
					Chip(text: "Heute", color: .accentColor)
				}
				Rectangle()
					.fill(DS.border)
					.frame(height: 1)
			}
			eventRows(day)
		}
	}

	/// Events eines Tages als klickbare Zeilen mit Detail-Popover.
	@ViewBuilder
	private func eventRows(_ day: DayGroup) -> some View {
		ForEach(day.events) { event in
			EventRowView(
				event: event,
				onToggle: { await store.toggleTask(event) },
				onSelect: { selectedEvent = event })
			.popover(item: $selectedEvent) { ev in
				EventDetailView(
					event: ev,
					onToggle: { await store.toggleTask(ev) })
			}
		}
	}

	private func dayLabelColor(_ day: DayGroup, hasOverdue: Bool) -> Color {
		if day.isToday { return DS.textPrimary }
		if hasOverdue { return DS.danger }
		return DS.textSecondary
	}

	// MARK: – Klapp-Zustand

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
