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

	// MARK: – Farben (systemadaptiv)

	/// Karten-/Popover-Fläche.
	static let card = Color(nsColor: .controlBackgroundColor)
	/// Fensterhintergrund.
	static let background = Color(nsColor: .windowBackgroundColor)
	/// Standard-Trennlinie.
	static let border = Color(nsColor: .separatorColor)
	/// Primaertext.
	static let textPrimary = Color(nsColor: .labelColor)
	/// Sekundärtext.
	static let textSecondary = Color(nsColor: .secondaryLabelColor)
	/// Gedämpfter Text (Platzhalter, Meta).
	static let textTertiary = Color(nsColor: .tertiaryLabelColor)
	/// Sehr dezente Füllfläche (Chips, Zeilen-Background).
	static let fillSubtle = Color(nsColor: .quaternaryLabelColor).opacity(0.45)

	/// Erfolgs-/Erledigt-Grün (Web: emerald-600 / emerald-400).
	static let success = Color.dynamic(light: 0x059669, dark: 0x34D399)
	/// Warn-/Überfällig-Rot (Web: red-600 / red-400).
	static let danger = Color.dynamic(light: 0xDC2626, dark: 0xF87171)
	/// Akzent-Tönung für aktive Elemente (nutzt die Systemakzentfarbe).
	static let tintSoft = Color.accentColor.opacity(0.14)
	static let tintMedium = Color.accentColor.opacity(0.28)

	// MARK: – Typografie

	enum Type {
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
			return NSColor.srgb(light: darkMode ? dark : light)
		})
	}

	fileprivate static func srgb(_ hex: UInt64) -> NSColor {
		NSColor(
			srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
			green: CGFloat((hex >> 8) & 0xFF) / 255,
			blue: CGFloat(hex & 0xFF) / 255,
			alpha: 1)
	}
}

// MARK: – Karten

/// Karten-Look wie im Web (`bg-card + border + rounded-xl`):
/// dezente Schwebe nur im Light-Mode, klare Kontur in beiden Modi.
struct CardStyle: ViewModifier {
	@Environment(\.colorScheme) private var scheme

	var body: some View {
		content
			.background(
				RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
					.fill(DS.card)
			)
			.overlay(
				RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
					.strokeBorder(DS.border, lineWidth: 1)
			)
			.shadow(color: .black.opacity(scheme == .light ? 0.06 : 0), radius: 8, y: 2)
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
			Text(text).font(DS.Type.chip)
		}
		.foregroundStyle(color)
		.padding(.horizontal, 7)
		.padding(.vertical, 3)
		.background(Capsule().fill(color.opacity(0.16)))
		.accessibilityElement(children: .combine)
	}
}

// MARK: – Buttons

/// Füllter Primärbutton (Anmelden, Speichern) – Kante 10px, volle Breite möglich.
struct PrimaryButtonStyle: ButtonStyle {
	@Environment(\.isEnabled) private var isEnabled

	func makeBody(configuration: Configuration) -> some View {
		configuration.label
			.font(.callout.weight(.semibold))
			.frame(maxWidth: .infinity)
			.padding(.vertical, 10)
			.background(
				RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
					.fill(Color.accentColor.opacity(isEnabled ? 1 : 0.4))
			)
			.foregroundStyle(.white)
			.scaleEffect(configuration.isPressed ? 0.985 : 1)
			.animation(.easeOut(duration: 0.12), value: configuration.isPressed)
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
