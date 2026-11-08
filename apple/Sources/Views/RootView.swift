import AppKit
import SwiftUI

/// Notifications zwischen App-Commands (Menü/Shortcuts) und MacMainView.
/// Eigener State gehört dem View – die Commands posten nur die Absicht.
enum NavCmd {
	static let select = Notification.Name("hz.nav.select")   // object = Section-Index (Int)
	static let reload = Notification.Name("hz.nav.reload")   // object = nil
}

/// Auth-Gate: Login, Ladezustand oder Haupt-App.
struct RootView: View {
	@Environment(AuthStore.self) private var auth

	var body: some View {
		switch auth.status {
		case .checking:
			ProgressView("Verbinde …")
				.frame(maxWidth: .infinity, maxHeight: .infinity)
		case .guest:
			LoginView()
		case .authenticated:
			// Neuer AppStore pro Client (Login/Serverwechsel → frische Daten).
			MacMainView(client: auth.client!)
				.id(auth.client?.baseURL.absoluteString ?? "")
		}
	}
}

/// Mac-Shell: Sidebar mit den vier Bereichen (statt Tabs wie auf iOS).
struct MacMainView: View {
	enum Section: String, CaseIterable, Identifiable {
		case horizont = "Horizont"
		case archiv = "Archiv"
		case workflows = "Workflows"
		case einstellungen = "Einstellungen"

		var id: String { rawValue }

		var icon: String {
			switch self {
			case .horizont: return "circle.dotted"
			case .archiv: return "clock.arrow.circlepath"
			case .workflows: return "checklist"
			case .einstellungen: return "gearshape"
			}
		}

		/// Index für NavCmd.select (Reihenfolge = allCases).
		var navIndex: Int { Self.allCases.firstIndex(of: self) ?? 0 }

		/// Dezent angezeigter Shortcuts-Hinweis in der Sidebar.
		var shortcutHint: String {
			switch self {
			case .horizont: return "⌘1"
			case .archiv: return "⌘2"
			case .workflows: return "⌘3"
			case .einstellungen: return "⌘4"
			}
		}

		/// Shortcuts-Taste für das App-Menü (⌘1…⌘4).
		var shortcutKey: KeyEquivalent {
			switch self {
			case .horizont: return "1"
			case .archiv: return "2"
			case .workflows: return "3"
			case .einstellungen: return "4"
			}
		}
	}

	let client: APIClient
	@Environment(AuthStore.self) private var auth
	@State private var store: AppStore
	@State private var section: Section = .horizont

	init(client: APIClient) {
		self.client = client
		_store = State(initialValue: AppStore(client: client))
	}

	var body: some View {
		NavigationSplitView {
			VStack(spacing: 0) {
				// Explizites .tag(s): sonst taggt die List nach Section.ID (String),
				// der Binding-Typ ist aber Section → Klicks tun nichts.
				List(selection: $section) {
					SwiftUI.Section("Bereiche") {
						ForEach(Section.allCases) { s in
							HStack(spacing: DS.Space.xs) {
								Label(s.rawValue, systemImage: s.icon)
								Spacer(minLength: DS.Space.sm)
								Text(s.shortcutHint)
									.font(DS.Typo.meta)
									.foregroundStyle(DS.textSecondary)
							}
							.tag(s)
						}
					}
				}
				.listStyle(.sidebar)

				Divider()
				sidebarFooter
			}
			.navigationSplitViewColumnWidth(min: 200, ideal: 220)
		} detail: {
			Group {
				switch section {
				case .horizont: HomeView()
				case .archiv: ArchiveView()
				case .workflows: WorkflowsView()
				case .einstellungen: SettingsView()
				}
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity)
		}
		.environment(store)
		.onReceive(NotificationCenter.default.publisher(for: NavCmd.select)) { note in
			// Commands posten den Section-Index (Reihenfolge = allCases).
			if let index = note.object as? Int,
			   index >= 0, index < Section.allCases.count {
				section = Section.allCases[index]
			}
		}
		.onReceive(NotificationCenter.default.publisher(for: NavCmd.reload)) { _ in
			Task { await reloadCurrentSection() }
		}
		// Dock-Badge: Anzahl offener Aufgaben über alle Panels/Tage.
		.onChange(of: openTaskCount) { _, count in
			NSApp.dockTile.badgeLabel = count == 0 ? nil : String(count)
		}
	}

	// MARK: – Sidebar-Footer (Benutzer + Abmelden)

	private var sidebarFooter: some View {
		HStack(spacing: DS.Space.sm) {
			HorizontMark(size: 24)
			VStack(alignment: .leading, spacing: 1) {
				Text(auth.user?.username ?? "–")
					.font(DS.Typo.metaStrong)
					.foregroundStyle(DS.textPrimary)
					.lineLimit(1)
				if let role = auth.user?.role, !role.isEmpty {
					Text(role)
						.font(DS.Typo.meta)
						.foregroundStyle(DS.textSecondary)
						.lineLimit(1)
				}
			}
			Spacer(minLength: DS.Space.xs)
			Button {
				Task { await auth.logout() }
			} label: {
				Image(systemName: "rectangle.portrait.and.arrow.right")
					.foregroundStyle(DS.textSecondary)
			}
			.ghostButton()
			.help("Abmelden")
			.accessibilityLabel("Abmelden")
		}
		.padding(.horizontal, DS.Space.md)
		.padding(.vertical, DS.Space.sm)
	}

	// MARK: – Reload & Dock-Badge

	/// Lädt die Daten der aktuell angezeigten Sektion (⌘R).
	private func reloadCurrentSection() async {
		switch section {
		case .horizont:
			await store.loadHome()
		case .archiv:
			await store.loadArchive(monthKey: store.archive?.monthKey)
		case .workflows:
			await store.loadWorkflows()
		case .einstellungen:
			await store.loadConnections()
			await store.loadNotify()
			await store.loadCalendars()
			await store.loadCategories()
		}
	}

	/// Offene Aufgaben (kind == "task", nicht erledigt) in allen Panels/Tagen.
	private var openTaskCount: Int {
		store.home?.panels
			.flatMap(\.days)
			.flatMap(\.events)
			.filter { $0.kind == "task" && $0.completed != true }
			.count ?? 0
	}
}
