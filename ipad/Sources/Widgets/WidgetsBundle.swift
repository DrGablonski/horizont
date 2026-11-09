import SwiftUI
import WidgetKit

/// Widget-Sammlung der iPad-App (Home-Screen + Sperrbildschirm).
@main
struct HorizontWidgets: WidgetBundle {
	var body: some Widget {
		HeuteWidget()
		HeuteAccessoryWidget()
	}
}
