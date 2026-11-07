import SwiftUI

struct SettingsView: View {
	@Environment(AuthStore.self) private var auth
	@State private var serverDraft = ""

	var body: some View {
		NavigationStack {
			Form {
				Section {
					LabeledContent("Angemeldet als", value: auth.user?.username ?? "–")
					LabeledContent("Rolle", value: auth.user?.role ?? "–")
				}

				Section("Server") {
					TextField("Server-URL", text: $serverDraft)
						.autocorrectionDisabled()
					Text("Änderungen wirken erst nach Abmelden/Anmelden.")
						.font(.caption)
						.foregroundStyle(.secondary)
				}

				Section {
					Button("Abmelden", role: .destructive) {
						Task { await auth.logout() }
					}
				}
			}
			.formStyle(.grouped)
			.navigationTitle("Einstellungen")
		}
		.onAppear { serverDraft = auth.serverURL }
		.onChange(of: serverDraft) { _, new in
			auth.serverURL = new
		}
	}
}
