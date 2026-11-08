import SwiftUI

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
							Label(s.rawValue, systemImage: s.icon)
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
		.background(sectionShortcuts)
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

	// MARK: – Bereichs-Shortcuts (⌘1…⌘4)

	/// Versteckte Buttons, die ⌘1…⌘4 an den Bereichswechsel binden.
	/// (opacity 0 statt .hidden(): versteckte Views registrieren keine Shortcuts.)
	private var sectionShortcuts: some View {
		VStack(spacing: 0) {
			Button("") { section = .horizont }
				.keyboardShortcut("1", modifiers: .command)
			Button("") { section = .archiv }
				.keyboardShortcut("2", modifiers: .command)
			Button("") { section = .workflows }
				.keyboardShortcut("3", modifiers: .command)
			Button("") { section = .einstellungen }
				.keyboardShortcut("4", modifiers: .command)
		}
		.buttonStyle(.plain)
		.frame(width: 0, height: 0)
		.opacity(0)
		.accessibilityHidden(true)
		.allowsHitTesting(false)
	}
}
