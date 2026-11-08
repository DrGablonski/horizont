import SwiftUI
import AppKit

/// Inhalt des MenuBarExtra-Panels (Schnellzugriff auf offene Tasks + Termine heute).
///
/// Der Panel-Store ist ein eigener AppStore, unabhängig vom Store im Fenster:
/// er wird aus `auth.client` gebaut und bei Server-/Client-Wechsel (Key =
/// baseURL) über `.task(id:)` neu erzeugt und alle 5 Minuten neu geladen.
struct MenuBarRootView: View {
	@Environment(AuthStore.self) private var auth

	@State private var store: AppStore?

	private let panelWidth: CGFloat = 340

	var body: some View {
		content
			.frame(width: panelWidth)
			.padding(DS.Space.md)
			.task(id: auth.client?.baseURL.absoluteString) {
				await syncStore()
			}
	}

	// MARK: – Zustandspaare (auth.status)

	@ViewBuilder
	private var content: some View {
		switch auth.status {
		case .checking:
			VStack(spacing: DS.Space.md) {
				ProgressView()
				Text("Prüfe Session …")
					.font(DS.Typo.meta)
					.foregroundStyle(DS.textSecondary)
			}
			.frame(maxWidth: .infinity)
			.padding(.vertical, DS.Space.xl)
		case .guest:
			guestPane
		case .authenticated:
			homePane
		}
	}

	/// Nicht angemeldet: Hinweis + Sprung ins Hauptfenster (Login).
	private var guestPane: some View {
		VStack(spacing: DS.Space.sm) {
			Text("Bitte anmelden")
				.font(DS.Typo.cardTitle)
			Text("Keine aktive Session – Horizont öffnen und einloggen.")
				.font(DS.Typo.meta)
				.foregroundStyle(DS.textSecondary)
				.multilineTextAlignment(.center)
			Button {
				openMainWindow()
			} label: {
				Label("Horizont öffnen", systemImage: "macwindow")
					.frame(maxWidth: .infinity, alignment: .leading)
			}
			.ghostButton()
			.padding(.top, DS.Space.xs)
		}
		.frame(maxWidth: .infinity)
		.padding(.vertical, DS.Space.md)
	}

	// MARK: – Inhalt (authenticated)

	private var homePane: some View {
		VStack(alignment: .leading, spacing: DS.Space.sm) {
			HStack(spacing: DS.Space.xs) {
				Text("Heute")
					.font(DS.Typo.cardTitle)
				Spacer()
				if store?.homeBusy == true {
					ProgressView()
						.controlSize(.small)
				}
				Button {
					Task { await store?.loadHome() }
				} label: {
					Image(systemName: "arrow.clockwise")
						.font(.system(size: 11, weight: .semibold))
				}
				.ghostButton()
				.disabled(store?.homeBusy == true)
			}

			if let store {
				if store.home == nil && store.homeError == nil {
					// Erster Ladevorgang: Skelett-Blöcke.
					VStack(spacing: DS.Space.sm) {
						ForEach(0..<3, id: \.self) { _ in
							SkeletonBlock(height: 13)
						}
					}
					.padding(.vertical, DS.Space.sm)
					.redacted(reason: .placeholder)
				} else {
					listSection(store)
				}
			} else {
				ProgressView()
					.frame(maxWidth: .infinity)
					.padding(.vertical, DS.Space.md)
			}

			if let err = store?.homeError {
				Text(err)
					.font(DS.Typo.meta)
					.foregroundStyle(DS.danger)
					.lineLimit(2)
			}

			Divider()

			Button {
				openMainWindow()
			} label: {
				Label("Horizont öffnen", systemImage: "macwindow")
					.frame(maxWidth: .infinity, alignment: .leading)
			}
			.ghostButton()
		}
	}

	/// Offene Tasks + Termine des heutigen Tages, scrollbar begrenzt.
	@ViewBuilder
	private func listSection(_ store: AppStore) -> some View {
		let tasks = openTasks(in: store)
		let events = todaysEvents(in: store)

		if tasks.isEmpty && events.isEmpty {
			Text("Nichts offen 🎉")
				.font(DS.Typo.meta)
				.foregroundStyle(DS.textSecondary)
				.frame(maxWidth: .infinity, alignment: .center)
				.padding(.vertical, DS.Space.lg)
		} else {
			ScrollView {
				VStack(alignment: .leading, spacing: 0) {
					ForEach(tasks) { event in
						MenuBarTaskRow(event: event) {
							await store.toggleTask(event)
						}
					}

					if !tasks.isEmpty && !events.isEmpty {
						Text("Termine heute")
							.font(DS.Typo.metaStrong)
							.foregroundStyle(DS.textTertiary)
							.padding(.top, DS.Space.sm)
							.padding(.bottom, DS.Space.xxs)
					}

					ForEach(events) { event in
						MenuBarEventRow(event: event)
					}
				}
			}
			.frame(maxHeight: 340)
		}
	}

	// MARK: – Daten

	/// Alle offenen Tasks aus allen Panels/Tagen.
	private func openTasks(in store: AppStore) -> [EventItem] {
		guard let panels = store.home?.panels else { return [] }
		return panels
			.flatMap { $0.days.flatMap(\.events) }
			.filter { $0.kind == "task" && $0.completed != true }
	}

	/// Nicht-Task-Termine des heutigen Tages (Tag = home.todayKey).
	private func todaysEvents(in store: AppStore) -> [EventItem] {
		guard let home = store.home else { return [] }
		return home.panels
			.flatMap(\.days)
			.filter { $0.dayKey == home.todayKey }
			.flatMap { $0.events }
			.filter { $0.kind != "task" }
	}

	// MARK: – Store-Lebensdauer

	/// Baut den Panel-Store aus auth.client und lädt alle 5 Minuten nach.
	/// Start/Neustart über `.task(id:)` bei Client- bzw. Server-Wechsel.
	private func syncStore() async {
		guard let client = auth.client else {
			store = nil
			return
		}
		let local = AppStore(client: client)
		store = local
		while !Task.isCancelled {
			await local.loadHome()
			try? await Task.sleep(for: .seconds(300))
		}
	}

	/// Hauptfenster in den Vordergrund holen (Login bzw. App-Inhalt).
	private func openMainWindow() {
		NSApp.activate(ignoringOtherApps: true)
		NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
	}
}

// MARK: – Zeilen

/// Kompakte Task-Zeile mit Kreis-Schalter zum Abhaken.
private struct MenuBarTaskRow: View {
	let event: EventItem
	let onToggle: () async -> Void

	@State private var toggling = false

	private var isOverdue: Bool { event.overdue == true }

	var body: some View {
		HStack(spacing: DS.Space.sm) {
			Button {
				guard !toggling else { return }
				toggling = true
				Task {
					await onToggle()
					toggling = false
				}
			} label: {
				Image(systemName: (event.completed ?? false) ? "checkmark.circle.fill" : "circle")
					.font(.system(size: 14, weight: .regular))
					.foregroundStyle(isOverdue ? DS.danger : Color(hex: event.calendarColor))
					.scaleEffect(toggling ? 0.8 : 1)
			}
			.buttonStyle(.plain)
			.disabled(toggling)

			Text(event.summary)
				.font(.callout)
				.strikethrough(event.completed ?? false)
				.foregroundStyle(isOverdue ? DS.danger : (event.completed ?? false) ? DS.textSecondary : DS.textPrimary)
				.lineLimit(1)

			Spacer(minLength: DS.Space.xs)
		}
		.padding(.vertical, DS.Space.xs)
	}
}

/// Kompakte Termin-Zeile (nur farbiges Pünktchen + Uhrzeit, nicht abhakbar).
private struct MenuBarEventRow: View {
	let event: EventItem

	var body: some View {
		HStack(spacing: DS.Space.sm) {
			Circle()
				.fill(Color(hex: event.calendarColor))
				.frame(width: 8, height: 8)

			Text(event.summary)
				.font(.callout)
				.foregroundStyle(DS.textPrimary)
				.lineLimit(1)

			Spacer(minLength: DS.Space.xs)

			if !event.allDay {
				Text(Fmt.time(event.startMs))
					.font(DS.Typo.meta.monospacedDigit())
					.foregroundStyle(DS.textSecondary)
			}
		}
		.padding(.vertical, DS.Space.xs)
	}
}
