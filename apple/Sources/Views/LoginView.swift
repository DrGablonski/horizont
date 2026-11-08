import SwiftUI

/// Anmelde-Maske: zentrierte Karte mit Server-, Benutzer- und Passwortfeld.
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
		VStack(spacing: 0) {
			ScrollView {
				VStack(spacing: DS.Space.xl) {
					header

					VStack(spacing: DS.Space.md) {
						FieldRow(title: "Server", systemImage: "globe") {
							TextField("http://10.10.10.1:3001", text: $server)
								.autocorrectionDisabled()
								#if os(iOS)
								.textInputAutocapitalization(.never)
								#endif
								.focused($focusedField, equals: .server)
								.onSubmit { focusedField = .user }
						}
						FieldRow(title: "Benutzername", systemImage: "person") {
							TextField("Benutzername", text: $username)
								.autocorrectionDisabled()
								#if os(iOS)
								.textInputAutocapitalization(.never)
								#endif
								.focused($focusedField, equals: .user)
								.onSubmit { focusedField = .password }
						}
						FieldRow(title: "Passwort", systemImage: "lock") {
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
					.disabled(!canSubmit)
				}
				.padding(DS.Space.xl)
				.frame(maxWidth: 380)
				.dsCard()
				.frame(maxWidth: 380)
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity)

			footnote
				.padding(.bottom, DS.Space.lg)
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.background(DS.background)
		.onAppear {
			server = auth.serverURL
			username = auth.lastUsername
		}
	}

	// MARK: – Teilstücke

	private var header: some View {
		VStack(spacing: DS.Space.sm) {
			HorizontMark(size: 64)
				.padding(.bottom, DS.Space.xs)
			Text("Horizont")
				.font(DS.Typo.pageTitle)
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
		guard canSubmit else { return }
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

/// Beschriftetes Eingabefeld mit Icon im Karten-Look (Login).
private struct FieldRow<Content: View>: View {
	let title: String
	let systemImage: String
	@ViewBuilder var content: () -> Content

	var body: some View {
		VStack(alignment: .leading, spacing: DS.Space.xs) {
			Text(title)
				.font(DS.Typo.metaStrong)
				.foregroundStyle(DS.textSecondary)
			HStack(spacing: DS.Space.sm) {
				Image(systemName: systemImage)
					.font(.system(size: 12, weight: .medium))
					.foregroundStyle(DS.textTertiary)
					.frame(width: 14)
				content()
					.textFieldStyle(.plain)
			}
			.padding(.horizontal, DS.Space.md)
			.padding(.vertical, 9)
			.background(
				RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
					.fill(DS.background)
			)
			.overlay(
				RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
					.strokeBorder(DS.border, lineWidth: 1)
			)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
	}
}

/// Dezente Wortmarke (Punkt + Horizonte), angelehnt ans Web-Logo.
struct HorizontMark: View {
	var size: CGFloat = 40

	var body: some View {
		ZStack {
			Circle()
				.fill(Color.accentColor)
				.frame(width: size * 0.34, height: size * 0.34)
				.offset(x: -size * 0.28)
			ForEach(0..<3) { i in
				Capsule()
					.fill(Color.accentColor.opacity(0.85 - Double(i) * 0.22))
					.frame(width: size * (0.9 - CGFloat(i) * 0.18), height: size * 0.08)
					.offset(x: size * 0.12, y: CGFloat(i - 1) * size * 0.16)
			}
		}
		.frame(width: size, height: size)
	}
}
