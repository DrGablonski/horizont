import SwiftUI

/// Startseite: die drei zusammenklappbaren Zeiträume wie im Web –
/// Panels als Karten (bg-card + border), Tage mit Header, Events als Zeilen.
struct HomeView: View {
	@Environment(AppStore.self) private var store
	@State private var openPanels: [String: Bool] = [:]

	var body: some View {
		NavigationStack {
			Group {
				if store.homeBusy && store.home == nil {
					ProgressView("Lade Horizonte …")
						.frame(maxWidth: .infinity, maxHeight: .infinity)
				} else if let home = store.home {
					content(home)
				} else {
					ContentUnavailableView(
						"Keine Verbindung",
						systemImage: "wifi.exclamationmark",
						description: Text(store.homeError ?? "Server nicht erreichbar."))
				}
			}
			.navigationTitle("Horizont")
			.refreshable { await store.loadHome() }
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
			VStack(alignment: .leading, spacing: 12) {
				if let err = store.homeError {
					Label(err, systemImage: "exclamationmark.triangle")
						.font(.callout).foregroundStyle(.red)
				}
				if !home.configured {
					Text("CalDAV ist auf dem Server noch nicht eingerichtet.")
						.font(.callout).foregroundStyle(.secondary)
				}
				ForEach(home.panels) { panel in
					panelCard(panel)
				}
			}
			.padding(.horizontal, 20)
			.padding(.vertical, 16)
			.frame(maxWidth: 780)
			.frame(maxWidth: .infinity)
		}
		.background(Color(nsColor: .windowBackgroundColor))
	}

	/// Panel als Karte: Klickbarer Header (Titel, Subtitle, Zähler, Chevron) + Tage.
	@ViewBuilder
	private func panelCard(_ panel: TimePanel) -> some View {
		VStack(alignment: .leading, spacing: 0) {
			Button {
				togglePanel(panel)
			} label: {
				HStack(spacing: 10) {
					VStack(alignment: .leading, spacing: 2) {
						Text(panel.title).font(.headline)
						Text(panel.subtitle)
							.font(.caption)
							.foregroundStyle(.secondary)
					}
					Spacer(minLength: 8)
					if panel.eventCount > 0 {
						Text("\(panel.eventCount)")
							.font(.caption.weight(.medium).monospacedDigit())
							.foregroundStyle(.secondary)
							.padding(.horizontal, 8)
							.padding(.vertical, 3)
							.background(
								Capsule().fill(Color(nsColor: .quaternaryLabelColor).opacity(0.6)))
					}
					Image(systemName: "chevron.down")
						.font(.caption.weight(.semibold))
						.foregroundStyle(.secondary)
						.rotationEffect(.degrees(isOpen(panel) ? 180 : 0))
				}
				.padding(.horizontal, 14)
				.padding(.vertical, 11)
				.contentShape(Rectangle())
			}
			.buttonStyle(.plain)
			.animation(.easeOut(duration: 0.18), value: isOpen(panel))

			if isOpen(panel) {
				Divider()
				VStack(alignment: .leading, spacing: 18) {
					if panel.days.isEmpty {
						Text("Keine Einträge in diesem Zeitraum.")
							.font(.subheadline)
							.foregroundStyle(.secondary)
					}
					ForEach(panel.days) { day in
						dayBlock(day)
					}
				}
				.padding(.horizontal, 14)
				.padding(.vertical, 14)
			}
		}
		.cardStyle()
	}

	/// Tag-Block wie im Web: Header (heute hervorgehoben), darunter die Events.
	@ViewBuilder
	private func dayBlock(_ day: DayGroup) -> some View {
		VStack(alignment: .leading, spacing: 8) {
			Text(day.label)
				.font(.subheadline.weight(.semibold))
				.foregroundStyle(day.isToday
				                 ? Color(nsColor: .labelColor)
				                 : Color(nsColor: .secondaryLabelColor))
			ForEach(day.events) { event in
				EventRowView(event: event) {
					await store.toggleTask(event)
				}
			}
		}
	}

	// MARK: – Klapp-Zustand

	private func isOpen(_ panel: TimePanel) -> Bool {
		openPanels[panel.id] ?? panel.defaultOpen
	}

	private func togglePanel(_ panel: TimePanel) {
		openPanels[panel.id] = !isOpen(panel)
	}

	private func initOpenPanels() {
		guard let home = store.home, openPanels.isEmpty else { return }
		for panel in home.panels { openPanels[panel.id] = panel.defaultOpen }
	}
}
