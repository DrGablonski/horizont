import SwiftUI

/// Zentrale Design-Tokens der Mac-App.
///
/// Grundregeln:
/// • Alle Flächen-/Textfarben sind dynamisch (Semantik-Farben oder Hell/Dunkel-Paare)
///   → Light- und Dark-Mode folgen automatisch dem System.
/// • 4-Pixel-Raster, Radius 12 für Karten – angelehnt ans Web-UI (shadcn, --radius 10px).
/// • Interaktion: Hover-Zustände, sanfte Animationen, deutliche Fokusringe.
enum DS {

	// MARK: – Raster

	enum Space {
		static let xxs: CGFloat = 2
		static let xs: CGFloat = 4
		static let sm: CGFloat = 8
		static let md: CGFloat = 12
		static let lg: CGFloat = 16
		static let xl: CGFloat = 24
		static let xxl: CGFloat = 32
	}

	enum Radius {
		static let sm: CGFloat = 6
		static let md: CGFloat = 8
		static let lg: CGFloat = 12
		static let xl: CGFloat = 16
		static let pill: CGFloat = 999
	}

	// MARK: – Farben (eigene Palette, nicht Systemfarben)

	/// Karten-/Popover-Fläche.
	static let card = Color.dynamic(light: 0xFFFFFF, dark: 0x1C1E25)
	/// Erhöhte Fläche (Popover, Sheet-inhalt).
	static let cardElevated = Color.dynamic(light: 0xFFFFFF, dark: 0x24272F)
	/// Fensterhintergrund (Graphite-Dark / Paper-Light).
	static let background = Color.dynamic(light: 0xF4F5F7, dark: 0x14151A)
	/// Sidebar-Fläche (eigenständig getönt, wie im Diddy-Look).
	static let sidebar = Color.dynamic(light: 0xFAFAFC, dark: 0x0E0F13)
	/// Standard-Trennlinie (Hell: Schwarz 10 %, Dunkel: Weiß 9 %).
	static let border = Color.dynamicAlpha(light: (0x000000, 0.10), dark: (0xFFFFFF, 0.09))
	/// Kräftigere Kontur (Fokus, aktive Elemente).
	static let borderStrong = Color.dynamicAlpha(light: (0x000000, 0.16), dark: (0xFFFFFF, 0.16))
	/// Primaertext.
	static let textPrimary = Color.dynamic(light: 0x1B1D22, dark: 0xEEF0F4)
	/// Sekundärtext.
	static let textSecondary = Color.dynamic(light: 0x5B606B, dark: 0xA8ACB8)
	/// Gedämpfter Text (Platzhalter, Meta).
	static let textTertiary = Color.dynamic(light: 0x8A8F9B, dark: 0x767B88)
	/// Sehr dezente Füllfläche (Chips, Zeilen-Background).
	static let fillSubtle = Color.dynamicAlpha(light: (0x000000, 0.05), dark: (0xFFFFFF, 0.06))
	/// Hover-Aufhellung für Zeilen/Buttons.
	static let rowHover = Color.dynamicAlpha(light: (0x000000, 0.045), dark: (0xFFFFFF, 0.06))

	/// Erfolgs-/Erledigt-Grün (Web: emerald-600 / emerald-400).
	static let success = Color.dynamic(light: 0x059669, dark: 0x34D399)
	/// Warn-/Überfällig-Rot (Web: red-600 / red-400).
	static let danger = Color.dynamic(light: 0xDC2626, dark: 0xF87171)
	/// Warn-Gelb für Hinweise (Web: amber-600 / amber-400).
	static let warning = Color.dynamic(light: 0xD97706, dark: 0xFBBF24)

	/// Akzentfarbe aus dem gewählten Design.
	static var accent: Color { ThemeStore.shared.accent }
	/// Akzent-Tönung für aktive Elemente.
	static var tintSoft: Color { accent.opacity(0.16) }
	static var tintMedium: Color { accent.opacity(0.30) }

	/// Ambient-Glows für den Fensterhintergrund (warm in Akzentfarbe, kühl gegenüber).
	static var glowWarm: Color {
		Color.dynamicAlpha(light: (ThemeStore.shared.design.accentLight, 0.12),
		                   dark: (ThemeStore.shared.design.accentDark, 0.16))
	}
	static let glowCool = Color.dynamicAlpha(light: (0x3E5C76, 0.10), dark: (0x3E5C76, 0.14))

	// MARK: – Typografie

	enum Typo {
		static let pageTitle = Font.title2.weight(.semibold)      // Bereichs-Titel
		static let cardTitle = Font.headline                       // Panel-/Workflow-Titel
		static let rowTitle = Font.body                            // Event-/Schritt-Titel
		static let meta = Font.caption                             // Uhrzeit, Zähler
		static let metaStrong = Font.caption.weight(.semibold)
		static let chip = Font.caption2.weight(.medium)
	}
}

// MARK: – Dynamische Hell/Dunkel-Farben

extension Color {
	/// Hell/Dunkel-Paar aus sRGB-Werten (0xRRGGBB), passt sich der Systemeinstellung an.
	static func dynamic(light: UInt64, dark: UInt64) -> Color {
		Color(nsColor: NSColor(name: nil) { appearance in
			let darkMode = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
			return NSColor.dsSRGB(darkMode ? dark : light)
		})
	}

	/// Hell/Dunkel-Paar mit Alpha (Konturen, Füllflächen).
	static func dynamicAlpha(light: (UInt64, CGFloat), dark: (UInt64, CGFloat)) -> Color {
		Color(nsColor: NSColor(name: nil) { appearance in
			let darkMode = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
			let (hex, alpha) = darkMode ? dark : light
			return NSColor.dsSRGB(hex).withAlphaComponent(alpha)
		})
	}

}

extension NSColor {
	fileprivate static func dsSRGB(_ hex: UInt64) -> NSColor {
		NSColor(
			srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
			green: CGFloat((hex >> 8) & 0xFF) / 255,
			blue: CGFloat(hex & 0xFF) / 255,
			alpha: 1)
	}
}

// MARK: – Karten

/// Karten-Look wie im Web / Diddy: eigene Fläche, feine Kontur in beiden Modi,
/// sanfte Schwebe (stärker im Dark-Mode).
struct CardStyle: ViewModifier {
	@Environment(\.colorScheme) private var scheme

	func body(content: Content) -> some View {
		content
			.background(
				RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
					.fill(DS.card)
			)
			.overlay(
				RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
					.strokeBorder(DS.border, lineWidth: 1)
			)
			.shadow(color: .black.opacity(scheme == .light ? 0.05 : 0.28),
			        radius: scheme == .light ? 6 : 10, y: scheme == .light ? 2 : 4)
	}
}

extension View {
	/// Karte im Web-Look (ersetzt den alten cardStyle aus Theme.swift).
	func dsCard() -> some View { modifier(CardStyle()) }
}

// MARK: – Chips & Badges

/// Kleines Pillen-Label (Kategorie, Zähler, Status).
struct Chip: View {
	let text: String
	var color: Color = DS.textSecondary
	var systemImage: String? = nil

	var body: some View {
		HStack(spacing: DS.Space.xs) {
			if let systemImage {
				Image(systemName: systemImage).font(.system(size: 9, weight: .semibold))
			}
			Text(text).font(DS.Typo.chip)
		}
		.foregroundStyle(color)
		.padding(.horizontal, 7)
		.padding(.vertical, 3)
		.background(Capsule().fill(color.opacity(0.16)))
		.accessibilityElement(children: .combine)
	}
}

// MARK: – Buttons

/// Gefüllter Primärbutton (Anmelden, Speichern) in der Akzentfarbe des Themes.
struct PrimaryButtonStyle: ButtonStyle {
	@Environment(\.isEnabled) private var isEnabled
	@State private var hovering = false

	func makeBody(configuration: Configuration) -> some View {
		configuration.label
			.font(.callout.weight(.semibold))
			.frame(maxWidth: .infinity)
			.padding(.vertical, 10)
			.background(
				ZStack {
					RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
						.fill(DS.accent.opacity(isEnabled ? 1 : 0.4))
					RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
						.fill(Color.white.opacity(isEnabled && hovering ? 0.10 : 0))
				}
			)
			.foregroundStyle(.white)
			.scaleEffect(configuration.isPressed ? 0.985 : 1)
			.animation(.easeOut(duration: 0.12), value: configuration.isPressed)
			.animation(.easeOut(duration: 0.12), value: hovering)
			.onHover { hovering = $0 }
	}
}

/// Randloser Icon-/Textbutton mit Hover-Hintergrund (Toolbar, Reihenaktionen).
struct GhostButtonStyle: ButtonStyle {
	@State private var hovering = false

	func makeBody(configuration: Configuration) -> some View {
		configuration.label
			.padding(.horizontal, DS.Space.sm)
			.padding(.vertical, DS.Space.xs + 2)
			.background(
				RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
					.fill(Color.primary.opacity(hovering && configuration.isPressed == false ? 0.08 :
						configuration.isPressed ? 0.12 : 0))
			)
			.contentShape(Rectangle())
			.onHover { hovering = $0 }
	}
}

/// Klickbare Karte/Zeile mit Hover-Aufhellung und sanfter Press-Skalierung.
struct HoverableRowStyle: ButtonStyle {
	@State private var hovering = false

	func makeBody(configuration: Configuration) -> some View {
		configuration.label
			.background(
				Color.primary.opacity(hovering ? 0.045 : 0),
				in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
			)
			.scaleEffect(configuration.isPressed ? 0.99 : 1)
			.animation(.easeOut(duration: 0.12), value: configuration.isPressed)
			.onHover { hovering = $0 }
	}
}

extension View {
	func primaryButton() -> some View { buttonStyle(PrimaryButtonStyle()) }
	func ghostButton() -> some View { buttonStyle(GhostButtonStyle()) }
}

// MARK: – Zustände

/// Einheitlicher Leerzustand (Icon, Titel, Text, optionale Aktion).
struct EmptyStateView: View {
	let title: String
	let systemImage: String
	var description: String? = nil
	var actionTitle: String? = nil
	var action: (() -> Void)? = nil

	var body: some View {
		VStack(spacing: DS.Space.md) {
			Image(systemName: systemImage)
				.font(.system(size: 44, weight: .light))
				.foregroundStyle(DS.textTertiary)
			Text(title).font(.title3.weight(.semibold))
			if let description {
				Text(description)
					.font(.callout)
					.foregroundStyle(DS.textSecondary)
					.multilineTextAlignment(.center)
					.frame(maxWidth: 360)
			}
			if let actionTitle, let action {
				Button(actionTitle, action: action)
					.controlSize(.large)
					.padding(.top, DS.Space.xs)
			}
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.padding(DS.Space.xl)
	}
}

/// Platzhalter-Skelett während dem Laden (rotierte Blöcke wie im Web).
struct SkeletonBlock: View {
	var width: CGFloat? = nil
	var height: CGFloat = 14

	var body: some View {
		RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
			.fill(DS.fillSubtle)
			.frame(width: width, height: height)
	}
}

struct TimelineSkeleton: View {
	var body: some View {
		VStack(spacing: DS.Space.md) {
			ForEach(0..<3, id: \.self) { _ in
				VStack(alignment: .leading, spacing: DS.Space.sm) {
					SkeletonBlock(width: 160, height: 16)
					SkeletonBlock(height: 12)
					SkeletonBlock(width: 280, height: 12)
				}
				.padding(DS.Space.md)
				.frame(maxWidth: .infinity, alignment: .leading)
				.dsCard()
			}
		}
		.padding(.horizontal, DS.Space.xl)
		.padding(.vertical, DS.Space.lg)
		.redacted(reason: .placeholder)
		.allowsHitTesting(false)
	}
}

// MARK: – Fehler-Banner

struct ErrorBanner: View {
	let message: String
	var retry: (() -> Void)? = nil

	var body: some View {
		HStack(spacing: DS.Space.sm) {
			Image(systemName: "exclamationmark.triangle.fill")
				.foregroundStyle(DS.danger)
			Text(message)
				.font(.callout)
				.foregroundStyle(DS.textPrimary)
			Spacer(minLength: DS.Space.sm)
			if let retry {
				Button("Erneut versuchen", action: retry).controlSize(.small)
			}
		}
		.padding(DS.Space.md)
		.background(
			RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
				.fill(DS.danger.opacity(0.10))
		)
		.overlay(
			RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
				.strokeBorder(DS.danger.opacity(0.35), lineWidth: 1)
		)
	}
}
