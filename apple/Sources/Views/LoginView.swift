import SwiftUI

struct LoginView: View {
	@Environment(AuthStore.self) private var auth

	@State private var server: String = ""
	@State private var username: String = ""
	@State private var password: String = ""
	@State private var busy = false
	@State private var errorText: String?

	var body: some View {
		ScrollView {
			VStack(spacing: 20) {
				Spacer().frame(height: 60)

				HorizontMark(size: 72)
				Text("Horizont")
					.font(.largeTitle.weight(.semibold))
				Text("Vergangenheit · Jetzt · Zukunft")
					.font(.subheadline)
					.foregroundStyle(.secondary)

				VStack(spacing: 12) {
					TextField("Server-URL (z. B. http://10.10.10.1:3001)", text: $server)
						.autocorrectionDisabled()
#if os(iOS)
						.textInputAutocapitalization(.never)
#endif
					TextField("Benutzername", text: $username)
						.autocorrectionDisabled()
#if os(iOS)
						.textInputAutocapitalization(.never)
#endif
					SecureField("Passwort", text: $password)
				}
				.padding(.horizontal)

				if let errorText {
					Text(errorText)
						.font(.callout)
						.foregroundStyle(.red)
						.multilineTextAlignment(.center)
				}

				Button {
					submit()
				} label: {
					if busy {
						ProgressView().frame(maxWidth: .infinity)
					} else {
						Text("Anmelden").frame(maxWidth: .infinity)
					}
				}
				.buttonStyle(.borderedProminent)
				.controlSize(.large)
				.disabled(busy || server.isEmpty || username.isEmpty || password.isEmpty)
				.padding(.horizontal)

				Spacer()
			}
			.padding()
		}
		.onAppear {
			server = auth.serverURL
			username = auth.lastUsername
		}
	}

	private func submit() {
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
