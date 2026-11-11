import SwiftUI

// MARK: – iPad-Gesten

/// Nach rechts wischen, um eine Aufgabe zu erledigen.
/// Grün-Feedback erscheint ab ~8 pt Drag, ausgelöst ab 64 pt.
struct SwipeToComplete: ViewModifier {
	let enabled: Bool
	let completed: Bool
	let action: () async -> Void

	@State private var offset: CGFloat = 0

	func body(content: Content) -> some View {
		if enabled && !completed {
			content
				.background(alignment: .leading) {
					ZStack(alignment: .leading) {
						if offset > 8 {
							Capsule()
								.fill(DS.success.opacity(min(1, Double(offset / 96))))
								.frame(width: 56, height: 26)
							Image(systemName: "checkmark.circle.fill")
								.font(.system(size: 17, weight: .semibold))
								.foregroundStyle(.white)
								.padding(.leading, 18)
						}
					}
				}
				.offset(x: offset)
				.gesture(
					DragGesture(minimumDistance: 12)
						.onChanged { g in
							withAnimation(.easeOut(duration: 0.1)) {
								offset = max(0, min(g.translation.width, 96))
							}
						}
						.onEnded { _ in
							if offset >= 64 {
								Task { await action() }
							}
							withAnimation(.spring(duration: 0.25)) { offset = 0 }
						}
				)
		} else {
			content
		}
	}
}

extension View {
	func swipeToComplete(enabled: Bool = true, completed: Bool = false,
	                     action: @escaping () async -> Void) -> some View {
		modifier(SwipeToComplete(enabled: enabled, completed: completed, action: action))
	}
}
