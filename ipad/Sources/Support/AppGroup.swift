import Foundation

/// Gemeinsamer Speicher für iPad-App und Widget-Extension (App Group).
///
/// Widgets laufen in einem eigenen Prozess ohne Login-Session – die App legt
/// deshalb nach jedem Laden einen JSON-Snapshot in den App-Group-Container,
/// den die Widgets lesen. Theme-Einstellungen liegen in denselben Defaults.
enum AppGroup {
	/// Muss zu den Entitlements in ipad/project.yml passen.
	static let id = "group.de.hott.horizont.ipad"

	static var defaults: UserDefaults {
		UserDefaults(suiteName: id) ?? .standard
	}

	static var container: URL? {
		FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)
	}
}
