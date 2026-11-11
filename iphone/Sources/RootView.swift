import SwiftUI

/// Auth-Gate: Login, Ladezustand oder Haupt-App (identisches Muster wie Mac/iPad).
struct RootView: View {
	@Environment(AuthStore.self) private var auth
	@Environment(ThemeStore.self) private var theme

	var body: some View {
		Group {
			switch auth.status {
			case .checking:
				ZStack {
					AmbientBackground()
					VStack(spacing: DS.Space.md) {
						BrandTile(size: 44)
						ProgressView()
							.tint(DS.accent)
						Text("Verbinde …")
							.font(DS.Typo.meta)
							.foregroundStyle(DS.textSecondary)
					}
				}
			case .guest:
				LoginView()
			case .authenticated:
				// Neuer AppStore pro Client (Login/Serverwechsel → frische Daten).
				PhoneMainView(client: auth.client!)
					.id(auth.client?.baseURL.absoluteString ?? "")
			}
		}
		// Theme-Wechsel → kompletter Baum neu (Farben sind statisch abgeleitet).
		.id(theme.revision)
	}
}

/// iPhone-Shell: native TabBar mit vier Bereichen, jeder Tab in einem eigenen
/// NavigationStack. Ein gemeinsamer AppStore versorgt alle Tabs (wie am Pad).
/// Die Tab-Bar bleibt bewusst nativ – nur Tönung und Hintergrundfläche folgen
/// dezent dem Design-System.
struct PhoneMainView: View {
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

	private static let sectionKey = "hz.section.iphone"

	let client: APIClient
	@State private var store: AppStore
	@AppStorage(sectionKey) private var sectionRaw: String = Section.horizont.rawValue

	init(client: APIClient) {
		self.client = client
		_store = State(initialValue: AppStore(client: client))
	}

	/// Aktive Sektion (rohwert-gesichert, überlebt App-Neustarts).
	private var section: Binding<Section> {
		Binding(
			get: { Section(rawValue: sectionRaw) ?? .horizont },
			set: { sectionRaw = $0.rawValue }
		)
	}

	var body: some View {
		TabView(selection: section) {
			NavigationStack { HomeView() }
				.tabItem { Label(Section.horizont.rawValue, systemImage: Section.horizont.icon) }
				.tag(Section.horizont)

			NavigationStack { ArchiveView() }
				.tabItem { Label(Section.archiv.rawValue, systemImage: Section.archiv.icon) }
				.tag(Section.archiv)

			NavigationStack { WorkflowsView() }
				.tabItem { Label(Section.workflows.rawValue, systemImage: Section.workflows.icon) }
				.tag(Section.workflows)

			NavigationStack { SettingsView() }
				.tabItem { Label(Section.einstellungen.rawValue, systemImage: Section.einstellungen.icon) }
				.tag(Section.einstellungen)
		}
		.environment(store)
		.tint(DS.accent)
		.background(AmbientBackground().ignoresSafeArea())
		// Tab-Bar-Fläche dezent an die Design-System-Kartenfarbe anpassen
		// (dynamisch für Hell/Dunkel); Icons/Labels bleiben iOS-Standard.
		.toolbarBackground(DS.card.opacity(0.94), for: .tabBar)
	}
}
