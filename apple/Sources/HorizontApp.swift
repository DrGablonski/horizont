import SwiftUI

@main
struct HorizontApp: App {
	@State private var auth = AuthStore()
	@State private var theme = ThemeStore.shared
	#if DEBUG
	/// QA: `…/Horizont.app/Contents/MacOS/Horizont -HZShot <dir>` rendert PNGs
	/// und beendet sich danach (nutzt gespeicherte Login-Daten).
	@State private var shotDir: String?
	#endif

	init() {
		#if DEBUG
		let args = CommandLine.arguments
		if let i = args.firstIndex(of: "-HZShot"), i + 1 < args.count {
			_shotDir = State(initialValue: args[i + 1])
		}
		#endif
	}

	var body: some Scene {
		WindowGroup("Horizont") {
			RootView()
				.environment(auth)
				.environment(theme)
				.frame(minWidth: 860, minHeight: 560)
				.task { theme.apply() }
				.task(id: auth.status) { await runShotsIfNeeded() }
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
				.environment(theme)
				.id(theme.revision)
		}
		.menuBarExtraStyle(.window)
	}

	#if DEBUG
	private func runShotsIfNeeded() async {
		guard let dir = shotDir, auth.status != .checking else { return }
		guard auth.status == .authenticated,
		      let url = AuthStore.normalize(auth.serverURL) else {
			fputs("[shot] not authenticated – Abbruch\n", stderr)
			// Login-Screens trotzdem zeigen.
			await SnapshotQA.shootAll(dir: dir, url: URL(string: "http://127.0.0.1:1")!, auth: auth)
			NSApp.terminate(nil)
			return
		}
		await SnapshotQA.shootAll(dir: dir, url: url, auth: auth)
		NSApp.terminate(nil)
	}
	#endif
}
