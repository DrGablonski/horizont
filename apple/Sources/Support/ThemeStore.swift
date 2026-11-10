import AppKit
import Observation
import SwiftUI

/// Feste Designs (komplette Looks): jedes Design legt Helligkeit **und**
/// Akzentfarbe gemeinsam fest – bewusst keine freie Farbwahl mehr, sondern
/// 4 kuratierte Looks (Graphit, Tinte, Violett, Papier).
enum AppDesign: String, CaseIterable, Identifiable {
	case graphite  // Dunkel + Amber (Standard)
	case ink       // Dunkel + Blau
	case violet    // Dunkel + Violett
	case paper     // Hell + Amber

	var id: String { rawValue }

	var name: String {
		switch self {
		case .graphite: return "Graphit"
		case .ink: return "Tinte"
		case .violet: return "Violett"
		case .paper: return "Papier"
		}
	}

	/// Kurzbeschreibung unter dem Kachelnamen.
	var subtitle: String {
		switch self {
		case .graphite: return "Dunkel · Amber"
		case .ink: return "Dunkel · Blau"
		case .violet: return "Dunkel · Violett"
		case .paper: return "Hell · Amber"
		}
	}

	var isDark: Bool { self != .paper }

	/// sRGB-Akzent für die feste Helligkeit des Designs.
	var accentRGB: UInt64 { isDark ? accentDark : accentLight }

	/// Akzent-Paar (Hell/Dunkel-Zweige passen immer zum jeweiligen Design).
	var accentLight: UInt64 {
		switch self {
		case .graphite, .paper: return 0xB4761F
		case .ink: return 0x2563EB
		case .violet: return 0x7C3AED
		}
	}

	var accentDark: UInt64 {
		switch self {
		case .graphite, .paper: return 0xF0A65A
		case .ink: return 0x60A5FA
		case .violet: return 0xA78BFA
		}
	}

	/// erzwungene Fenster-Erscheinung (Design = fester Look, kein System-Follow)
	var nsAppearance: NSAppearance? {
		NSAppearance(named: isDark ? .darkAqua : .aqua)
	}
}

/// Erscheinungsbild: gewähltes Design, persistiert in UserDefaults.
///
/// Die App nutzt bewusst **eigene Paletten** (Graphite-Dark / Paper-Light) statt
/// der macOS-Systemfarben – so wirkt sie wie ein gestaltetes Produkt (Diddy-Look)
/// und nicht wie ein Default-Formular. Alle DS-Farben lesen über dynamische
/// NSColor-Provider hier mit.
@Observable
final class ThemeStore {
	static let shared = ThemeStore()

	private static let designKey = "hz.designID"
	// Alt (freie Akzentwahl + Hell/Dunkel-Pill) – nur noch für die Migration.
	private static let legacyModeKey = "hz.appearanceMode"
	private static let legacyAccentKey = "hz.accentID"

	/// Aktives Design (Graphit, Tinte, Violett, Papier).
	var design: AppDesign {
		didSet {
			UserDefaults.standard.set(design.rawValue, forKey: Self.designKey)
			apply()
		}
	}

	/// Erhöht sich bei jeder Änderung → Root-View baut die Baum-Instanz neu
	/// (.id(revision)), damit überall neu gerendert wird.
	private(set) var revision = 0

	private init() {
		if let raw = UserDefaults.standard.string(forKey: Self.designKey),
		   let saved = AppDesign(rawValue: raw) {
			design = saved
		} else {
			design = Self.migrateLegacyChoice()
		}
	}

	/// Alte freie Akzent-/Modus-Einstellung auf das nächste feste Design mappen.
	private static func migrateLegacyChoice() -> AppDesign {
		switch UserDefaults.standard.string(forKey: Self.legacyAccentKey) {
		case "blue": return .ink
		case "violet": return .violet
		default: break
		}
		// Alt-Modus "Hell" (bzw. System mit hellem System) → Papier, sonst Graphit.
		let legacyMode = UserDefaults.standard.string(forKey: Self.legacyModeKey)
		return legacyMode == "light" ? .paper : .graphite
	}

	/// Akzentfarbe des aktiven Designs.
	var accent: Color {
		Color.dynamic(light: design.accentLight, dark: design.accentDark)
	}

	/// Setzt die NSApplication-Erscheinung und triggert Re-Render (nur bei echter Änderung).
	func apply() {
		NSApp.appearance = design.nsAppearance
		if design.rawValue != appliedKey {
			appliedKey = design.rawValue
			revision += 1
		}
	}

	private var appliedKey: String = ""
}
