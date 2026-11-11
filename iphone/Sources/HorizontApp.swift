import SwiftUI

@main
struct HorizontApp: App {
	@State private var auth = AuthStore()
	@State private var theme = ThemeStore.shared

	var body: some Scene {
		WindowGroup {
			RootView()
				.environment(auth)
				.environment(theme)
				.task { theme.apply() }
		}
	}
}
