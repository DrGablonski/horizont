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
	}
}
