import SwiftUI

@main
struct HorizontApp: App {
	@State private var auth = AuthStore()

	var body: some Scene {
		WindowGroup("Horizont") {
			RootView()
				.environment(auth)
				.frame(minWidth: 860, minHeight: 560)
		}
		.defaultSize(width: 1100, height: 720)
		.commands {
			// Bereichswechsel + Reload: State gehört MacMainView → Commands
			// posten nur NavCmd-Notifications (siehe RootView.swift).
			CommandMenu("Navigation") {
				ForEach(MacMainView.Section.allCases, id: \.self) { s in
					Button(s.rawValue) {
						NotificationCenter.default.post(
							name: NavCmd.select, object: s.navIndex)
					}
					.keyboardShortcut(s.shortcutKey, modifiers: .command)
				}
				Divider()
				Button("Aktualisieren") {
					NotificationCenter.default.post(name: NavCmd.reload, object: nil)
				}
				.keyboardShortcut("r", modifiers: .command)
			}
		}

		// Menuleiste: Schnellzugriff (offene Tasks + Termine heute).
		// Läuft immer; der innere View prüft auth.status (Gast → "Bitte anmelden").
		// .window-Style ist macOS 13+.
		MenuBarExtra("Horizont", systemImage: "circle.dotted") {
			MenuBarRootView()
				.environment(auth)
		}
		.menuBarExtraStyle(.window)
	}
}
