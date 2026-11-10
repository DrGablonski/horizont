#if DEBUG
import SwiftUI
import AppKit

/// QA-Helfer (nur Debug): rendert die Bereiche offscreen als PNGs, damit die UI
/// ohne Bildschirm prüfbar ist.
enum SnapshotQA {
	/// Haupt-Einstieg: lädt Daten und schreibt PNGs in dir.
	@MainActor
	static func shootAll(dir: String, url: URL, auth: AuthStore) async {
		fputs("[shot] shootAll start\n", stderr)
		let client = APIClient(serverURL: url)
		let store = AppStore(client: client)
		// Daten laden
		await store.loadHome()
		fputs("[shot] home loaded=\(store.home != nil) err=\(store.homeError ?? "-")\n", stderr)
		await store.loadArchive()
		await store.loadWorkflows()
		await store.loadCalendars()
		await store.loadCategories()
		await store.loadConnections()
		await store.loadNotify()
		fputs("[shot] archive=\(store.archive != nil) wfs=\(store.workflows.count)\n", stderr)

		func render<V: View>(_ name: String, _ view: V, width: CGFloat, height: CGFloat, dark: Bool = false, pause: TimeInterval = 1.2, hasOwnBackground: Bool = false) {
			fputs("[shot] rendering \(name)\n", stderr)
			// Echtes Fenster + cacheDisplay: rendert auch NSViewRepresentables
			// (ImageRenderer kann die nicht und zeigt Platzhalter).
			let host = NSHostingView(rootView: AnyView(
				ZStack {
					// Views außerhalb der Shell haben keinen eigenen Hintergrund –
					// nur MacMainView (shell) bringt AmbientBackground selbst mit.
					if !hasOwnBackground { AmbientBackground() }
					view.environment(store).environment(auth).environment(ThemeStore.shared)
				}
				.frame(width: width, height: height)))
			let win = NSWindow(
				contentRect: NSRect(x: -4000, y: -4000, width: width, height: height),
				styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
			win.title = name
			if dark { win.appearance = NSAppearance(named: .darkAqua) }
			win.contentView = host
			win.orderFrontRegardless()
			// Runloop-Ticks: Layout + Animationen + .task Durchlauf.
			runLoop(seconds: pause)
			let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)
			if let rep {
				host.cacheDisplay(in: host.bounds, to: rep)
				if let png = rep.representation(using: .png, properties: [:]) {
					try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))
					fputs("[shot] wrote \(name).png\n", stderr)
				} else {
					fputs("[shot] FAILED \(name)\n", stderr)
				}
			} else {
				fputs("[shot] no rep \(name)\n", stderr)
			}
			win.close()
		}

		render("login", LoginView(), width: 520, height: 640, pause: 0.6, hasOwnBackground: true)
		render("login-dark", LoginView(), width: 520, height: 640, dark: true, pause: 0.6, hasOwnBackground: true)
		render("home", HomeView(), width: 900, height: 760)
		render("home-dark", HomeView(), width: 900, height: 760, dark: true)
		render("archiv", ArchiveView(), width: 900, height: 760)
		render("archiv-dark", ArchiveView(), width: 900, height: 760, dark: true)
		render("workflows", WorkflowsView(), width: 900, height: 640)
		render("workflows-dark", WorkflowsView(), width: 900, height: 640, dark: true)
		// Einstellungen: alle vier Bereiche (Design-Wechsel steuert Hell/Dunkel).
		let designBefore = ThemeStore.shared.design
		let areaBefore = UserDefaults.standard.string(forKey: SettingsView.areaKey)
		ThemeStore.shared.design = .graphite
		for a in SettingsView.Area.allCases {
			UserDefaults.standard.set(a.rawValue, forKey: SettingsView.areaKey)
			render("settings-\(a.id.lowercased())", SettingsView(), width: 900, height: 900, pause: 0.8)
		}
		UserDefaults.standard.set(SettingsView.Area.appearance.rawValue, forKey: SettingsView.areaKey)
		ThemeStore.shared.design = .paper
		render("settings-light", SettingsView(), width: 900, height: 900, pause: 0.8)
		// Ausgangszustand wiederherstellen (QA soll Einstellungen nicht verbiegen).
		ThemeStore.shared.design = designBefore
		if let areaBefore {
			UserDefaults.standard.set(areaBefore, forKey: SettingsView.areaKey)
		} else {
			UserDefaults.standard.removeObject(forKey: SettingsView.areaKey)
		}
		render("quickadd", QuickAddTaskView(), width: 460, height: 560, pause: 0.8)
		render("quickadd-dark", QuickAddTaskView(), width: 460, height: 560, dark: true, pause: 0.8)
		render("quickadd-event", QuickAddTaskView(initialEvent: true), width: 460, height: 560, pause: 0.8)

		// Workflow-Dialoge (anlegen + bearbeiten an synthetischem Workflow).
		render("workflow-create", WorkflowEditorView(), width: 460, height: 560, pause: 0.8)
		if let wfSample = try? JSONDecoder().decode(Workflow.self, from: Data("""
		{"id":"w1","title":"Projektabschluss – Woche 12","notes":"Notizen testen","createdAt":1762560000000,
		 "updatedAt":1762560000000,"completedAt":null,"activeStepId":"s1",
		 "steps":[{"id":"s1","title":"Kundenpräsentation finalisieren","done":false,"completedAt":null},
		          {"id":"s2","title":"Protokoll versenden","done":true,"completedAt":1762563600000}],
		 "progress":0.5}
		""".utf8)) {
			render("workflow-edit", WorkflowEditorView(workflow: wfSample), width: 460, height: 560, pause: 0.8)
		}

		// HZQA-TEMP: shell skipped

		// Bearbeiten-Dialog an einem synthetischen Task demonstrieren.
		if let sample = try? JSONDecoder().decode(EventItem.self, from: Data("""
		{"id":"s1","uid":"s1","calendarId":"c1","calendarName":"Privat","calendarColor":"#E15759",
		 "summary":"Router-Firmware prüfen","startMs":1762560000000,"endMs":1762563600000,
		 "allDay":false,"kind":"task","completed":false,"dueKey":"2026-11-09","category":"Technik",
		 "categoryColor":"#59A14F","overdue":false}
		""".utf8)) {
			render("edit", EditItemView(event: sample), width: 460, height: 620, pause: 0.8)
			render("edit-dark", EditItemView(event: sample), width: 460, height: 620, dark: true, pause: 0.8)
		}
	}

	private static func runLoop(seconds: TimeInterval) {
		let end = Date().addingTimeInterval(seconds)
		while Date() < end {
			autoreleasepool {
				if let event = NSApp.nextEvent(matching: .any,
				                               until: Date().addingTimeInterval(0.05),
				                               inMode: .default, dequeue: true) {
					NSApp.sendEvent(event)
				}
			}
		}
	}
}
#endif
