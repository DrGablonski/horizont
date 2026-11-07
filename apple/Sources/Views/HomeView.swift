import SwiftUI

/// Startseite: die drei zusammenklappbaren Zeiträume wie im Web.
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

	@ViewBuilder
	private func content(_ home: MainEventsResponse) -> some View {
		List {
			if let err = store.homeError {
				Text(err).font(.callout).foregroundStyle(.red)
			}
			if !home.configured {
				Text("CalDAV ist auf dem Server noch nicht eingerichtet.")
					.font(.callout).foregroundStyle(.secondary)
			}
			ForEach(home.panels) { panel in
				DisclosureGroup(
					isExpanded: bindingFor(panel.id, fallback: panel.defaultOpen)
				) {
					ForEach(panel.days) { day in
						Section(day.label) {
							ForEach(day.events) { event in
								EventRowView(event: event) {
									await store.toggleTask(event)
								}
							}
						}
					}
				} label: {
					HStack {
						VStack(alignment: .leading) {
							Text(panel.title).font(.headline)
							Text(panel.subtitle)
								.font(.caption)
								.foregroundStyle(.secondary)
						}
						Spacer()
						Text("\(panel.eventCount)")
							.font(.callout.monospacedDigit())
							.foregroundStyle(.secondary)
					}
				}
			}
		}
	}

	private func initOpenPanels() {
		guard let home = store.home, openPanels.isEmpty else { return }
		for panel in home.panels { openPanels[panel.id] = panel.defaultOpen }
	}

	private func bindingFor(_ id: String, fallback: Bool) -> Binding<Bool> {
		Binding(
			get: { openPanels[id] ?? fallback },
			set: { openPanels[id] = $0 }
		)
	}
}
