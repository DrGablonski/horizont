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
				MacMainView(client: auth.client!)
					.id(auth.client?.baseURL.absoluteString ?? "")
			}
		}
		// Theme-Wechsel → kompletter Baum neu (Farben sind statisch abgeleitet).
		.id(theme.revision)
	}
}

/// Mac-Shell: eigene Sidebar (Marke, Pill-Navigation, Benutzer-Karte) statt
/// Default-List – Look wie bei Diddy, Farben aus der eigenen Palette.
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

		var subtitle: String {
			switch self {
			case .horizont: return "Vergangenheit · Jetzt · Zukunft"
			case .archiv: return "Monate mit Einträgen durchblättern"
			case .workflows: return "Schrittpläne im Fokus-Modus"
			case .einstellungen: return "Konto, Verbindungen & Benachrichtigungen"
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

	private static let sectionKey = "hz.section"

	let client: APIClient
	@Environment(AuthStore.self) private var auth
	@State private var store: AppStore
	@State private var section: Section

	init(client: APIClient, store: AppStore? = nil) {
		self.client = client
		_store = State(initialValue: store ?? AppStore(client: client))
		// Letzte Sektion wiederherstellen (überlebt Theme-Neuaufbau des Baums).
		let raw = UserDefaults.standard.string(forKey: Self.sectionKey) ?? Section.horizont.rawValue
		_section = State(initialValue: Section(rawValue: raw) ?? .horizont)
	}

	var body: some View {
		NavigationSplitView {
			sidebar
				.navigationSplitViewColumnWidth(min: 220, ideal: 240)
		} detail: {
			detail
		}
		.environment(store)
		.background(WindowChromeAccessor().frame(width: 0, height: 0))
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

	/// Marke + Wortmarke oben (Lichtschalter-Aussparung durch Padding).
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
		.padding(.top, 40)
		.padding(.bottom, DS.Space.md)
	}

	private var navList: some View {
		VStack(spacing: DS.Space.xxs) {
			ForEach(Section.allCases) { s in
				NavRow(
					section: s,
					isSelected: section == s
				) {
					section = s
					UserDefaults.standard.set(s.rawValue, forKey: Self.sectionKey)
				}
			}
		}
		.padding(.horizontal, DS.Space.sm)
	}

	/// Benutzer-Karte im Fuß (Avatar + Abmelden), wie bei Diddy.
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
			.help("Abmelden")
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

// MARK: – Sidebar-Navigationszeile

/// Pillenzeile mit Icon, Titel und Shortcut-Hinweis (ausgwählt: Akzent-Pille).
private struct NavRow: View {
	let section: MacMainView.Section
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
				Text(section.shortcutHint)
					.font(DS.Typo.meta.monospacedDigit())
					.foregroundStyle(DS.textTertiary)
			}
			.padding(.horizontal, DS.Space.sm)
			.padding(.vertical, 7)
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

// MARK: – Fenster-Chrome

/// Macht die Titelzeile transparent und die Fensterfarbe palettenkonform,
/// damit Sidebar + Ambient bis zum oberen Rand reichen (Diddy-Look).
private struct WindowChromeAccessor: NSViewRepresentable {
	func makeNSView(context: Context) -> NSView {
		let v = NSView()
		DispatchQueue.main.async {
			guard let win = v.window else { return }
			win.titleVisibility = .hidden
			win.titlebarAppearsTransparent = true
			win.styleMask.insert(.fullSizeContentView)
			win.isRestorable = false
			win.backgroundColor = NSColor(name: nil) { appearance in
				let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
				return NSColor(srgbRed: CGFloat((dark ? 0x14151A : 0xF4F5F7) >> 16 & 0xFF) / 255,
				               green: CGFloat((dark ? 0x14151A : 0xF4F5F7) >> 8 & 0xFF) / 255,
				               blue: CGFloat((dark ? 0x14151A : 0xF4F5F7) & 0xFF) / 255,
				               alpha: 1)
			}
		}
		return v
	}

	func updateNSView(_ nsView: NSView, context: Context) {}
}
