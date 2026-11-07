import SwiftUI

/// Auth-Gate: Login, Ladezustand oder Haupt-App.
struct RootView: View {
	@Environment(AuthStore.self) private var auth

	var body: some View {
		switch auth.status {
		case .checking:
			ProgressView("Verbinde …")
				.frame(maxWidth: .infinity, maxHeight: .infinity)
				.frame(minWidth: 420, minHeight: 300)
		case .guest:
			LoginView()
				.frame(minWidth: 420, minHeight: 480)
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
	@State private var store: AppStore
	@State private var section: Section = .horizont

	init(client: APIClient) {
		self.client = client
		_store = State(initialValue: AppStore(client: client))
	}

	var body: some View {
		NavigationSplitView {
			List(Section.allCases, selection: $section) { s in
				Label(s.rawValue, systemImage: s.icon)
			}
			.navigationSplitViewColumnWidth(min: 180, ideal: 200)
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
	}
}
