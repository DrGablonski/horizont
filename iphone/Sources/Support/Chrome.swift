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

// MARK: – Seitenfläche hinter Listen

extension View {
	/// Flächige Seitenfarbe (`DS.page`) hinter den Karten einer `List`.
	///
	/// Warum das nötig ist: `.scrollContentBackground(.hidden)` allein lässt die
	/// Systemfläche der Liste verschwinden, sichtbar wird dann aber die Fensterfarbe
	/// (Systemweiß bzw. Pureschwarz) – `DS.background`/`DS.page` bleibt unsichtbar,
	/// weil der Shell-Hintergrund noch tiefer liegt und nicht durchkommt. Ohne eine
	/// eigene Fläche stehen die weißen Karten im Light-Mode auf ebenfalls weißem
	/// Grund und sind als Kästchen nicht zu erkennen, also muss die Flächenfarbe
	/// direkt hinter die Liste.
	func dsPageBackground() -> some View {
		self
			.scrollContentBackground(.hidden)
			.background(DS.page.ignoresSafeArea())
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
					.fill(DS.field)
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

/// Platzhalter für Eingabefelder: immer gedämpftes Grau (nie Akzentfarbe),
/// damit er nicht wie bereits eingetippter Text aussieht.
func dsPrompt(_ text: String) -> Text {
	Text(verbatim: text).foregroundStyle(DS.textTertiary)
}

// MARK: – Tastatur durch Tipp außerhalb schließen

/// Tippen außerhalb des aktiven Eingabefeldes schließt die Tastatur. In einer
/// `List` wird durch einen Tipp ins Leere nichts abgewählt – die Tastatur bliebe
/// stehen und verdeckte die Tab-Bar, womit die anderen Bereiche unerreichbar
/// wären (Startseite mit dem Schnell-Eingabefeld ganz oben).
///
/// Der Tipp-Erkenner sitzt auf dem Fenster und gibt jede Berührung sofort weiter
/// (`cancelsTouchesInView = false` plus gleichzeitige Anerkennung): Knöpfe,
/// Zeilen-Auswahl und Wisch-Aktionen bleiben unverändert bedienbar. Tipps ins
/// Feld selbst werden verworfen – dort setzt man die Schreibmarke, die Tastatur
/// bleibt oben.
struct KeyboardTapDismiss: ViewModifier {
	func body(content: Content) -> some View {
		content.background(TapCatcher())
	}
}

extension View {
	func dismissKeyboardOnTap() -> some View {
		modifier(KeyboardTapDismiss())
	}
}

/// Unauffälliger 0-×-0-Helfer, der seinen Erkenner dem Fenster hinzufügt.
private struct TapCatcher: UIViewRepresentable {
	func makeUIView(context: Context) -> UIView { KeyboardTapView() }
	func updateUIView(_ uiView: UIView, context: Context) {}
}

private final class KeyboardTapView: UIView, UIGestureRecognizerDelegate {
	private var tap: UITapGestureRecognizer?

	override init(frame: CGRect) {
		super.init(frame: frame)
		isUserInteractionEnabled = false
	}
	required init?(coder: NSCoder) { fatalError("init(coder:) wird nicht verwendet") }

	deinit {
		if let tap { tap.view?.removeGestureRecognizer(tap) }
	}

	override func didMoveToWindow() {
		super.didMoveToWindow()
		// Umzug in ein anderes Fenster (Tab-Wechsel, Blatt): ersten Anhang lösen …
		if let tap, tap.view !== window {
			tap.view?.removeGestureRecognizer(tap)
			self.tap = nil
		}
		// … und den Erkenner einmal ans aktuelle Fenster anhängen.
		guard let window, tap == nil else { return }
		let recognizer = UITapGestureRecognizer(
			target: self, action: #selector(closeKeyboard(_:)))
		recognizer.cancelsTouchesInView = false
		recognizer.delegate = self
		window.addGestureRecognizer(recognizer)
		tap = recognizer
	}

	@objc private func closeKeyboard(_ recognizer: UITapGestureRecognizer) {
		recognizer.view?.endEditing(true)
	}

	/// Nur Tipps neben das aktive Feld schließen die Tastatur; ohne aktives Feld
	/// (also ohne Tastatur) meldet sich der Erkenner gar nicht.
	func gestureRecognizer(_ recognizer: UIGestureRecognizer,
	                       shouldReceive touch: UITouch) -> Bool {
		guard let field = touch.window?.activeFirstResponder as? UIView,
		      let hit = touch.view else { return false }
		return hit !== field && !hit.isDescendant(of: field)
	}

	/// Nie auf andere Erkenner warten: nichts verzögern oder blockieren.
	func gestureRecognizer(_ recognizer: UIGestureRecognizer,
	                       shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
		true
	}
}

extension UIResponder {
	/// Tiefster gerade aktiver Erstantwortender (das Eingabefeld mit Tastatur).
	fileprivate var activeFirstResponder: UIResponder? {
		if isFirstResponder { return self }
		guard let view = self as? UIView else { return nil }
		for subview in view.subviews {
			if let responder = subview.activeFirstResponder { return responder }
		}
		return nil
	}
}
