import SwiftUI

// MARK: – Ambient-Hintergrund

/// Fenster-Hintergrund wie bei Diddy: Grundfläche + zwei weiche Farb-Glows
/// (kühl oben links, warm in Akzentfarbe unten rechts).
/// WICHTIG: startRadiusFraction muss 0 sein – ab >0 füllt EllipticalGradient
/// den Bereich innerhalb des Radius transparent und wird nach außen solide
/// (ergibt sonst harte Ringe/Bänder am Fensterrand).
struct AmbientBackground: View {
	var body: some View {
		ZStack {
			DS.background
			EllipticalGradient(
				colors: [DS.glowCool, DS.glowCool.opacity(0)],
				center: UnitPoint(x: 0.0, y: 0.0),
				startRadiusFraction: 0, endRadiusFraction: 0.62
			)
			.ignoresSafeArea()
			EllipticalGradient(
				colors: [DS.glowWarm, DS.glowWarm.opacity(0)],
				center: UnitPoint(x: 1.0, y: 1.0),
				startRadiusFraction: 0, endRadiusFraction: 0.68
			)
			.ignoresSafeArea()
		}
	}
}

/// Sidebar-Fläche: unten minimal dunkler als oben (tieferer Raum-Eindruck).
struct SidebarBackground: View {
	var body: some View {
		LinearGradient(
			colors: [DS.sidebar, DS.sidebar.opacity(0.92)],
			startPoint: .top, endPoint: .bottom
		)
	}
}

// MARK: – Wortmarke

/// Marke: das App-Icon (Mondfinsternis über Bergen) als Kachel
/// (Sidebar-Kopf, Login).
struct BrandTile: View {
	var size: CGFloat = 32

	var body: some View {
		Image("BrandIcon")
			.resizable()
			.interpolation(.high)
			.aspectRatio(contentMode: .fit)
			.frame(width: size, height: size)
			.shadow(color: .black.opacity(0.35), radius: size * 0.18, y: 1)
	}
}

// MARK: – Bereichs-Kopf (statt Default-Toolbar-Titel)

/// Großer Titel + Subtitle links, Aktionen rechts – oben in jedem Bereich.
struct SectionHeader<Actions: View>: View {
	let title: String
	var subtitle: String? = nil
	@ViewBuilder var actions: () -> Actions

	init(_ title: String, subtitle: String? = nil, @ViewBuilder actions: @escaping () -> Actions) {
		self.title = title
		self.subtitle = subtitle
		self.actions = actions
	}

	var body: some View {
		HStack(alignment: .center, spacing: DS.Space.md) {
			VStack(alignment: .leading, spacing: DS.Space.xxs) {
				Text(title)
					.font(.system(size: 26, weight: .bold))
					.foregroundStyle(DS.textPrimary)
				if let subtitle {
					Text(subtitle)
						.font(.callout)
						.foregroundStyle(DS.textSecondary)
				}
			}
			Spacer(minLength: DS.Space.md)
			actions()
		}
		.padding(.horizontal, DS.Space.xl)
		.padding(.top, DS.Space.lg)
		.padding(.bottom, DS.Space.sm)
	}
}

extension SectionHeader where Actions == EmptyView {
	init(_ title: String, subtitle: String? = nil) {
		self.init(title, subtitle: subtitle, actions: { EmptyView() })
	}
}

// MARK: – Pill-Button (Header-Aktionen)

/// Akzent-Pille für Primäraktionen im Bereichskopf („+ Aufgabe“).
struct AccentPillButton: View {
	let title: String
	let systemImage: String
	var action: () -> Void

	@State private var hovering = false

	var body: some View {
		Button(action: action) {
			HStack(spacing: DS.Space.xs) {
				Image(systemName: systemImage).font(.system(size: 11, weight: .semibold))
				Text(title).font(.callout.weight(.semibold))
			}
			.foregroundStyle(.white)
			.padding(.horizontal, DS.Space.md)
			.padding(.vertical, 8)
			.background(
				Capsule().fill(DS.accent.opacity(hovering ? 0.88 : 1))
			)
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.onHover { hovering = $0 }
		.animation(.easeOut(duration: 0.12), value: hovering)
	}
}

// MARK: – Eingabefelder

/// Feld-Rahmen mit Akzent-Fokusring (Login, Einstellungen).
struct FieldChrome: ViewModifier {
	var focused: Bool = false

	func body(content: Content) -> some View {
		content
			.padding(.horizontal, DS.Space.md)
			.padding(.vertical, 9)
			.background(
				RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
					.fill(DS.background.opacity(0.6))
			)
			.overlay(
				RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
					.strokeBorder(focused ? DS.accent : DS.border, lineWidth: focused ? 1.5 : 1)
			)
			.animation(.easeOut(duration: 0.12), value: focused)
	}
}

extension View {
	func fieldChrome(focused: Bool = false) -> some View {
		modifier(FieldChrome(focused: focused))
	}
}
