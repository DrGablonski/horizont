import UIKit
import Observation
import SwiftUI

/// Erscheinungsbild: Appearance-Modus + Akzentfarbe, persistiert in UserDefaults.
///
/// Die App nutzt bewusst **eigene Paletten** (Graphite-Dark / Paper-Light) statt
/// der Systemfarben – so wirkt sie wie ein gestaltetes Produkt (Diddy-Look)
/// und nicht wie ein Default-Formular. Alle DS-Farben lesen über dynamische
/// UIColor-Provider hier mit.
///
/// Die Einstellung liegt in den App-Group-Defaults, damit auch die
/// Widget-Extension (eigener Prozess) dieselbe Akzentfarbe sieht.
@Observable
final class ThemeStore {
	static let shared = ThemeStore()

	private static let modeKey = "hz.appearanceMode"
	private static let accentKey = "hz.accentID"

	/// Speicherort: App Group (Widgets lesen mit).
	private static let defaults: UserDefaults = AppGroup.defaults

	/// System / Dunkel / Hell.
	var mode: AppearanceMode {
		didSet {
			Self.defaults.set(mode.rawValue, forKey: Self.modeKey)
			apply()
		}
	}

	/// Akzent-Preset (Amber, Blau, …).
	var accentPreset: AccentPreset {
		didSet {
			Self.defaults.set(accentPreset.id, forKey: Self.accentKey)
			apply()
		}
	}

	/// Erhöht sich bei jeder Änderung → Root-View baut die Baum-Instanz neu
	/// (.id(revision)), damit überall neu gerendert wird.
	private(set) var revision = 0

	private init() {
		let raw = Self.defaults.string(forKey: Self.modeKey) ?? AppearanceMode.system.rawValue
		mode = AppearanceMode(rawValue: raw) ?? .system
		let aid = Self.defaults.string(forKey: Self.accentKey) ?? AccentPreset.amberID
		accentPreset = AccentPreset.byId(aid)
	}

	/// Akzentfarbe (Hell/Dunkel-Paar des Presets).
	var accent: Color {
		Color.dynamic(light: accentPreset.light, dark: accentPreset.dark)
	}

	/// Setzt die Appearance (alle Fenster) und triggert Re-Render (nur bei echter Änderung).
	func apply() {
		let key = "\(mode.rawValue)|\(accentPreset.id)"
		let style = mode.uiUserInterfaceStyle
		#if !WIDGET_EXTENSION
		for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
			for window in scene.windows { window.overrideUserInterfaceStyle = style }
		}
		#endif
		if key != appliedKey {
			appliedKey = key
			revision += 1
		}
	}

	private var appliedKey: String = ""
}

// MARK: – Appearance-Modus

enum AppearanceMode: String, CaseIterable, Identifiable {
	case system, light, dark

	var id: String { rawValue }

	var label: String {
		switch self {
		case .system: return "System"
		case .light: return "Hell"
		case .dark: return "Dunkel"
		}
	}

	var icon: String {
		switch self {
		case .system: return "circle.lefthalf.filled"
		case .light: return "sun.max"
		case .dark: return "moon"
		}
	}

	var uiUserInterfaceStyle: UIUserInterfaceStyle {
		switch self {
		case .system: return .unspecified
		case .light: return .light
		case .dark: return .dark
		}
	}
}

// MARK: – Akzent-Presets

struct AccentPreset: Identifiable, Hashable {
	let id: String
	let name: String
	/// sRGB-Werte für Hell- und Dunkel-Palette.
	let light: UInt64
	let dark: UInt64

	static let amberID = "amber"
	static let blueID = "blue"
	static let violetID = "violet"
	static let pinkID = "pink"
	static let greenID = "green"
	static let redID = "red"

	static let all: [AccentPreset] = [
		AccentPreset(id: amberID, name: "Amber", light: 0xB4761F, dark: 0xF0A65A),
		AccentPreset(id: blueID, name: "Blau", light: 0x2563EB, dark: 0x60A5FA),
		AccentPreset(id: violetID, name: "Violett", light: 0x7C3AED, dark: 0xA78BFA),
		AccentPreset(id: pinkID, name: "Rosa", light: 0xDB2777, dark: 0xF472B6),
		AccentPreset(id: greenID, name: "Grün", light: 0x15803D, dark: 0x4ADE80),
		AccentPreset(id: redID, name: "Rot", light: 0xDC2626, dark: 0xF87171),
	]

	static func byId(_ id: String) -> AccentPreset {
		all.first { $0.id == id } ?? all[0]
	}

	static var amber: AccentPreset { byId(amberID) }
}
