import SwiftUI

/// Anmelde-Maske: Ambient-Hintergrund + zentrierte Marke-Karte mit
/// Server-, Benutzer- und Passwortfeld (Fokusringe in Akzentfarbe).
struct LoginView: View {
	@Environment(AuthStore.self) private var auth

	@State private var server: String = ""
	@State private var username: String = ""
	@State private var password: String = ""
	@State private var busy = false
	@State private var errorText: String?
	@FocusState private var focusedField: Field?

	private enum Field {
		case server, user, password
	}

	private var canSubmit: Bool {
		!busy && !server.isEmpty && !username.isEmpty && !password.isEmpty
	}

	var body: some View {
		ZStack {
			AmbientBackground()

			VStack(spacing: 0) {
				ScrollView {
					VStack(spacing: DS.Space.xl) {
						header

						VStack(spacing: DS.Space.md) {
							FieldRow(title: "Server", systemImage: "globe",
							         focused: focusedField == .server) {
								TextField("http://10.10.10.1:3001", text: $server)
									.autocorrectionDisabled()
									.keyboardType(.URL)
									#if os(iOS)
									.textInputAutocapitalization(.never)
									#endif
									.focused($focusedField, equals: .server)
									.onSubmit { focusedField = .user }
							}
							FieldRow(title: "Benutzername", systemImage: "person",
							         focused: focusedField == .user) {
								TextField("Benutzername", text: $username)
									.autocorrectionDisabled()
									#if os(iOS)
									.textInputAutocapitalization(.never)
									#endif
									.focused($focusedField, equals: .user)
									.onSubmit { focusedField = .password }
							}
							FieldRow(title: "Passwort", systemImage: "lock",
							         focused: focusedField == .password) {
								SecureField("Passwort", text: $password)
									.focused($focusedField, equals: .password)
									.onSubmit { submit() }
							}
						}

						if let errorText {
							ErrorBanner(message: errorText)
						}

						Button {
							submit()
						} label: {
							if busy {
								ProgressView()
									.controlSize(.regular)
									.tint(.white)
									.frame(maxWidth: .infinity, minHeight: 20)
							} else {
								Text("Anmelden")
							}
						}
						.primaryButton()
						.opacity(canSubmit ? 1 : 0.55)
					}
					.padding(DS.Space.xxl)
					.padding(.top, DS.Space.lg)
					.frame(maxWidth: 380)
					.dsCard()
					.frame(maxWidth: 380)
					.padding(.vertical, DS.Space.xl)
				}
				.frame(maxWidth: .infinity, maxHeight: .infinity)
				.scrollDismissesKeyboard(.interactively)
				// Tastatur-Leiste: „Anmelden“ ist auch erreichbar, wenn die
				// Tastatur den großen Button auf kleinen Displays verdeckt.
				.toolbar {
					ToolbarItemGroup(placement: .keyboard) {
						Spacer()
						Button("Fertig") { focusedField = nil }
						Spacer()
						Button("Anmelden") { submit() }
							.font(.callout.weight(.semibold))
					}
				}

				footnote
					.padding(.bottom, DS.Space.lg)
			}
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.onAppear {
			server = auth.serverURL
			username = auth.lastUsername
		}
	}

	// MARK: – Teilstücke

	private var header: some View {
		VStack(spacing: DS.Space.sm) {
			BrandTile(size: 60)
				.padding(.bottom, DS.Space.sm)
			Text("Horizont")
				.font(.system(size: 26, weight: .bold))
				.foregroundStyle(DS.textPrimary)
			Text("Vergangenheit · Jetzt · Zukunft")
				.font(DS.Typo.meta)
				.foregroundStyle(DS.textSecondary)
		}
	}

	private var footnote: some View {
		Text("Selbst gehosteter CalDAV-Kalender")
			.font(DS.Typo.chip)
			.foregroundStyle(DS.textTertiary)
			.accessibilityHidden(true)
	}

	// MARK: – Aktionen

	private func submit() {
		guard !busy else { return }
		let s = server.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !s.isEmpty, !username.isEmpty, !password.isEmpty else {
			errorText = "Bitte Server-URL, Benutzername und Passwort ausfüllen."
			return
		}
		focusedField = nil
		busy = true
		errorText = nil
		Task {
			do {
				try await auth.login(server: server, username: username, password: password)
			} catch {
				errorText = error.localizedDescription
			}
			busy = false
		}
	}
}

/// Beschriftetes Eingabefeld mit Icon und Akzent-Fokusring (Login).
private struct FieldRow<Content: View>: View {
	let title: String
	let systemImage: String
	var focused: Bool = false
	@ViewBuilder var content: () -> Content

	var body: some View {
		VStack(alignment: .leading, spacing: DS.Space.xs) {
			Text(title)
				.font(DS.Typo.metaStrong)
				.foregroundStyle(DS.textSecondary)
			HStack(spacing: DS.Space.sm) {
				Image(systemName: systemImage)
					.font(.system(size: 12, weight: .medium))
					.foregroundStyle(focused ? DS.accent : DS.textTertiary)
					.frame(width: 14)
				content()
					.textFieldStyle(.plain)
			}
			.fieldChrome(focused: focused)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
	}
}
