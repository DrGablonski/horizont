import SwiftUI

/// Auth-Gate: Login, Ladezustand oder Haupt-App (identisches Muster wie Mac).
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
				PadMainView(client: auth.client!)
					.id(auth.client?.baseURL.absoluteString ?? "")
			}
		}
		// Theme-Wechsel → kompletter Baum neu (Farben sind statisch abgeleitet).
		.id(theme.revision)
	}
}

/// iPad-Shell: NavigationSplitView mit eigener Sidebar (Marke, Pillen-Navigation,
/// Benutzer-Karte) – wie am Mac, aber ohne Shortcut-Hinweise und Fenster-Chrome.
/// Hochkant/Stage-Manager: Sidebar wird automatisch zur aufklappbaren Leiste.
struct PadMainView: View {
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

		var subtitle: String {
			switch self {
			case .horizont: return "Vergangenheit · Jetzt · Zukunft"
			case .archiv: return "Monate mit Einträgen durchblättern"
			case .workflows: return "Schrittpläne im Fokus-Modus"
			case .einstellungen: return "Konto, Verbindungen & Benachrichtigungen"
			}
		}
	}

	private static let sectionKey = "hz.section.ipad"

	let client: APIClient
	@Environment(AuthStore.self) private var auth
	@State private var store: AppStore
	@State private var section: Section
	@State private var columnVisibility: NavigationSplitViewVisibility = .automatic

	init(client: APIClient, store: AppStore? = nil) {
		self.client = client
		_store = State(initialValue: store ?? AppStore(client: client))
		// Letzte Sektion wiederherstellen (überlebt Theme-Neuaufbau des Baums).
		let raw = UserDefaults.standard.string(forKey: Self.sectionKey) ?? Section.horizont.rawValue
		_section = State(initialValue: Section(rawValue: raw) ?? .horizont)
	}

	var body: some View {
		NavigationSplitView(columnVisibility: $columnVisibility) {
			sidebar
				.navigationSplitViewColumnWidth(min: 230, ideal: 260, max: 320)
		} detail: {
			detail
		}
		.navigationSplitViewStyle(.balanced)
		.environment(store)
	}

	// MARK: – Sidebar

	private var sidebar: some View {
		VStack(spacing: 0) {
			brandHeader
			navList
			Spacer(minLength: 0)
			Divider().overlay(DS.border)
			userFooter
		}
		.background(SidebarBackground())
	}

	/// Marke + Wortmarke oben.
	private var brandHeader: some View {
		HStack(spacing: DS.Space.sm) {
			BrandTile(size: 30)
			VStack(alignment: .leading, spacing: 0) {
				Text("Horizont")
					.font(.system(size: 15, weight: .semibold))
					.foregroundStyle(DS.textPrimary)
				Text("Kalender")
					.font(.system(size: 11))
					.foregroundStyle(DS.textTertiary)
			}
			Spacer(minLength: 0)
		}
		.padding(.horizontal, DS.Space.md)
		.padding(.top, DS.Space.xl)
		.padding(.bottom, DS.Space.md)
	}

	private var navList: some View {
		VStack(spacing: DS.Space.xxs) {
			ForEach(Section.allCases) { s in
				NavRow(
					section: s,
					isSelected: section == s
				) {
					withAnimation(.easeOut(duration: 0.15)) {
						section = s
					}
					UserDefaults.standard.set(s.rawValue, forKey: Self.sectionKey)
				}
			}
		}
		.padding(.horizontal, DS.Space.sm)
	}

	/// Benutzer-Karte im Fuß (Avatar + Abmelden).
	private var userFooter: some View {
		HStack(spacing: DS.Space.sm) {
			ZStack {
				Circle().fill(DS.tintSoft)
				Text(String((auth.user?.username ?? "?").prefix(1)).uppercased())
					.font(DS.Typo.metaStrong)
					.foregroundStyle(DS.accent)
			}
			.frame(width: 30, height: 30)

			VStack(alignment: .leading, spacing: 1) {
				Text(auth.user?.username ?? "–")
					.font(DS.Typo.metaStrong)
					.foregroundStyle(DS.textPrimary)
					.lineLimit(1)
			}
			Spacer(minLength: DS.Space.xs)
			Button {
				Task { await auth.logout() }
			} label: {
				Image(systemName: "rectangle.portrait.and.arrow.right")
					.foregroundStyle(DS.textSecondary)
			}
			.ghostButton()
			.accessibilityLabel("Abmelden")
		}
		.padding(DS.Space.sm)
		.background(
			RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
				.fill(DS.fillSubtle)
		)
		.padding(DS.Space.sm)
	}

	// MARK: – Detail

	@ViewBuilder
	private var detail: some View {
		Group {
			switch section {
			case .horizont: HomeView()
			case .archiv: ArchiveView()
			case .workflows: WorkflowsView()
			case .einstellungen: SettingsView()
			}
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.background(AmbientBackground())
	}
}

// MARK: – Sidebar-Navigationszeile

/// Pillenzeile mit Icon und Titel (ausgewählt: Akzent-Pille).
private struct NavRow: View {
	let section: PadMainView.Section
	let isSelected: Bool
	let action: () -> Void

	@State private var hovering = false

	var body: some View {
		Button(action: action) {
			HStack(spacing: DS.Space.sm) {
				Image(systemName: section.icon)
					.font(.system(size: 13, weight: .medium))
					.foregroundStyle(isSelected ? DS.accent : DS.textSecondary)
					.frame(width: 18)
				Text(section.rawValue)
					.font(.callout.weight(isSelected ? .semibold : .medium))
					.foregroundStyle(isSelected ? DS.accent : DS.textPrimary)
					.lineLimit(1)
				Spacer(minLength: DS.Space.sm)
				if isSelected {
					Image(systemName: "circle.fill")
						.font(.system(size: 5))
						.foregroundStyle(DS.accent)
				}
			}
			.padding(.horizontal, DS.Space.sm)
			.padding(.vertical, 9)
			.background(
				RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
					.fill(isSelected ? DS.tintSoft
						: hovering ? DS.rowHover : Color.clear)
			)
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.onHover { hovering = $0 }
		.animation(.easeOut(duration: 0.12), value: hovering)
		.animation(.easeOut(duration: 0.12), value: isSelected)
	}
}
