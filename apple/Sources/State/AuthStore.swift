import Foundation
import Observation

/// Login-Zustand der App.
/// Session-Cookie-Auth; Zugangsdaten liegen in der Keychain, damit die App
/// nach Server-Neustart (Sessions sind serverseitig In-Memory) still neu
/// einloggen kann.
@MainActor
@Observable
final class AuthStore {
	enum Status { case checking, guest, authenticated }

	private(set) var status: Status = .checking
	private(set) var user: AppUser?
	private(set) var client: APIClient?

	var serverURL: String {
		get { UserDefaults.standard.string(forKey: "serverURL") ?? "" }
		set { UserDefaults.standard.set(newValue, forKey: "serverURL") }
	}

	var lastUsername: String {
		Keychain.get("username") ?? ""
	}

	init() {
		Task { await restore() }
	}

	/// Versucht, die gespeicherte Session (Cookie) wiederzuverwenden,
	/// sonst Still-Login mit den Keychain-Zugangsdaten.
	func restore() async {
		guard !serverURL.isEmpty,
		      let url = Self.normalize(serverURL),
		      let username = Keychain.get("username"),
		      let password = Keychain.get("password") else {
			status = .guest
			return
		}
		let api = APIClient(serverURL: url)
		do {
			let me = try await api.me()
			self.client = api
			self.user = me
			self.status = .authenticated
		} catch {
			// Session abgelaufen → neu einloggen.
			do {
				let u = try await api.login(username: username, password: password)
				self.client = api
				self.user = u
				self.status = .authenticated
			} catch {
				self.status = .guest
			}
		}
	}

	func login(server: String, username: String, password: String) async throws {
		guard let url = Self.normalize(server) else {
			throw APIError.server("Bitte gültige Server-URL angeben (z. B. http://10.10.10.1:3001).")
		}
		let api = APIClient(serverURL: url)
		let u = try await api.login(username: username, password: password)
		self.serverURL = server.trimmingCharacters(in: .whitespacesAndNewlines)
		Keychain.set("username", value: username)
		Keychain.set("password", value: password)
		self.client = api
		self.user = u
		self.status = .authenticated
	}

	func logout() async {
		try? await client?.logout()
		Keychain.delete("username")
		Keychain.delete("password")
		client = nil
		user = nil
		status = .guest
	}

	/// http(s) ergänzen, Slash am Ende ab.
	static func normalize(_ raw: String) -> URL? {
		var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
		if s.isEmpty { return nil }
		if !s.hasPrefix("http://") && !s.hasPrefix("https://") { s = "https://" + s }
		while s.hasSuffix("/") { s.removeLast() }
		return URL(string: s)
	}
}
