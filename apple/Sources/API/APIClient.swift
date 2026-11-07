import Foundation

/// HTTP-Client für die Horizont-API.
/// Auth: Session-Cookie (vom Login) im gemeinsamen Cookie-Storage.
/// Bei 401 meldet sich AuthStore ab bzw. loggt still neu ein.
final class APIClient {
	let baseURL: URL
	private let session: URLSession

	init(serverURL: URL) {
		self.baseURL = serverURL
		let config = URLSessionConfiguration.default
		config.httpAdditionalHeaders = ["Accept": "application/json"]
		config.timeoutIntervalForRequest = 20
		self.session = URLSession(configuration: config)
	}

	// MARK: – Kern

	@discardableResult
	func raw(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> Data {
		guard let url = URL(string: path, relativeTo: baseURL) else {
			throw APIError.server("Ungültige Server-URL.")
		}
		var req = URLRequest(url: url)
		req.httpMethod = method
		if let body {
			req.httpBody = try JSONSerialization.data(withJSONObject: body)
			req.setValue("application/json", forHTTPHeaderField: "Content-Type")
		}
		let data: Data
		let response: URLResponse
		do {
			(data, response) = try await session.data(for: req)
		} catch {
			throw APIError.network(error.localizedDescription)
		}
		guard let http = response as? HTTPURLResponse else {
			throw APIError.network("Ungültige Antwort.")
		}
		guard (200...299).contains(http.statusCode) else {
			var msg = "HTTP \(http.statusCode)"
			if http.statusCode == 401 {
				throw APIError.unauthorized
			}
			if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
			   let err = obj["error"] as? String {
				msg = err
			}
			throw APIError.server(msg)
		}
		return data
	}

	private func get<T: Decodable>(_ path: String) async throws -> T {
		let data = try await raw(path)
		do { return try JSONDecoder().decode(T.self, from: data) }
		catch { throw APIError.decoding }
	}

	private func send<T: Decodable>(_ path: String, method: String, body: [String: Any]? = nil) async throws -> T {
		let data = try await raw(path, method: method, body: body)
		do { return try JSONDecoder().decode(T.self, from: data) }
		catch { throw APIError.decoding }
	}

	// MARK: – Auth

	func login(username: String, password: String) async throws -> AppUser {
		let r: LoginResponse = try await send(
			"/api/auth/login", method: "POST",
			body: ["username": username, "password": password])
		return r.user
	}

	func me() async throws -> AppUser {
		let r: MeResponse = try await get("/api/auth/me")
		return r.user
	}

	func logout() async throws {
		_ = try await send(OKResponse.self, in: "/api/auth/logout")
	}

	private func send(_ type: OKResponse.Type, in path: String) async throws {
		_ = try await raw(path, method: "POST")
	}

	// MARK: – Events / Timeline

	func mainEvents() async throws -> MainEventsResponse {
		try await get("/api/events?scope=main")
	}

	func archiveMonth(_ monthKey: String?) async throws -> ArchiveMonth {
		if let monthKey {
			return try await get("/api/events?scope=archive&monat=\(monthKey)")
		}
		return try await get("/api/events?scope=archive")
	}

	// MARK: – Workflows

	func workflows() async throws -> [Workflow] {
		try await get("/api/workflows")
	}

	func updateStep(workflowId: String, stepId: String, done: Bool) async throws -> Workflow {
		try await send("/api/workflows/\(workflowId)/steps/\(stepId)",
		              method: "PATCH", body: ["done": done])
	}

	func resetWorkflow(workflowId: String) async throws -> Workflow {
		try await send("/api/workflows/\(workflowId)/reset", method: "POST")
	}

	// MARK: – Tasks (abhaken)

	func updateTaskCompleted(calendarId: String, uid: String, completed: Bool) async throws {
		_ = try await raw("/api/tasks/\(calendarId)/\(uid)",
		                  method: "PATCH", body: ["completed": completed])
	}

	// MARK: – Kalender

	func calendars() async throws -> CalendarsResponse {
		try await get("/api/calendars")
	}
}
