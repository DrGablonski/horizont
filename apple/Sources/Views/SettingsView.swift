import SwiftUI

/// Einstellungen: Konto, Server, Version und Abmelden.
struct SettingsView: View {
	@Environment(AuthStore.self) private var auth
	@State private var serverDraft = ""

	private var trimmedDraft: String {
		serverDraft.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	/// Speichern lohnt nur, wenn die URL wirklich geändert wurde.
	private var canSave: Bool {
		!trimmedDraft.isEmpty && trimmedDraft != auth.serverURL
	}

	private var appVersion: String {
		let info = Bundle.main.infoDictionary
		let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
		let build = info?["CFBundleVersion"] as? String ?? "1"
		return "\(short) (\(build))"
	}

	var body: some View {
		NavigationStack {
			Form {
				Section("Konto") {
					LabeledContent {
						Text(auth.user?.username ?? "–")
					} label: {
						HStack(spacing: DS.Space.md) {
							avatar
							Text("Angemeldet als")
						}
					}
					LabeledContent("Rolle", value: auth.user?.role ?? "–")
				}

				Section("Server") {
					TextField("Server-URL", text: $serverDraft)
						.autocorrectionDisabled()
					Text("Nach dem Speichern abmelden und wieder anmelden, damit die App neue Daten lädt.")
						.font(.caption)
						.foregroundStyle(DS.textSecondary)
					Button("Speichern") {
						auth.serverURL = trimmedDraft
					}
					.disabled(!canSave)
					.primaryButton()
				}

				Section("Info") {
					LabeledContent("Version", value: appVersion)
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
	}

	/// Kreis mit Initiale des Benutzernamens.
	private var avatar: some View {
		let initial = String((auth.user?.username ?? "?").prefix(1)).uppercased()
		return ZStack {
			Circle()
				.fill(DS.tintSoft)
			Text(initial)
				.font(DS.Typo.metaStrong)
				.foregroundStyle(Color.accentColor)
		}
		.frame(width: 28, height: 28)
	}
}
