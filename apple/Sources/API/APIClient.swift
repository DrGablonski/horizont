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

	// MARK: – Tasks (abhaken, anlegen, löschen)

	func updateTaskCompleted(calendarId: String, uid: String, completed: Bool) async throws {
		_ = try await raw("/api/tasks/\(calendarId)/\(uid)",
		                  method: "PATCH", body: ["completed": completed])
	}

	/// Task anlegen (POST /api/tasks). dueKey = 'YYYY-MM-DD' oder nil.
	@discardableResult
	func createTask(summary: String, calendarId: String, category: String? = nil,
	                dueKey: String? = nil, description: String? = nil) async throws -> EventItem {
		var body: [String: Any] = ["summary": summary, "calendarId": calendarId]
		if let category { body["category"] = category }
		if let dueKey { body["due"] = ["kind": "date", "key": dueKey] }
		if let description { body["description"] = description }
		return try await send("/api/tasks", method: "POST", body: body)
	}

	func deleteTask(calendarId: String, uid: String) async throws {
		_ = try await raw("/api/tasks/\(calendarId)/\(uid)", method: "DELETE")
	}

	func deleteEvent(calendarId: String, uid: String) async throws {
		_ = try await raw("/api/events/\(calendarId)/\(uid)", method: "DELETE")
	}

	// MARK: – Kalender

	func calendars() async throws -> CalendarsResponse {
		try await get("/api/calendars")
	}

	// MARK: – Einstellungen: CalDAV-Verbindungen

	func connections() async throws -> ConnectionsResponse {
		try await get("/api/settings")
	}

	/// Gespeicherte Verbindung per id testen.
	func testConnection(id: String) async throws -> TestResult {
		try await send("/api/settings/test", method: "POST", body: ["id": id])
	}

	// MARK: – Kategorien

	func categories() async throws -> [TaskCategory] {
		try await get(CategoriesResponse.self, from: "/api/categories").categories
	}

	/// Ganze Liste ersetzen (wie Web-App).
	func saveCategories(_ categories: [TaskCategory]) async throws -> [TaskCategory] {
		let body = ["categories": categories.map { ["name": $0.name, "color": $0.color] }]
		return try await send(CategoriesResponse.self, from: "/api/categories",
		                      method: "POST", body: body).categories
	}

	// MARK: – Benachrichtigungen

	func notifyConfig() async throws -> NotifyConfigView {
		try await get("/api/notify")
	}

	func saveNotifyConfig(_ input: [String: Any]) async throws -> NotifyConfigView {
		try await send("/api/notify", method: "POST", body: input)
	}

	/// Testversand (nutzt die gespeicherte Konfiguration).
	func sendNotifyTest() async throws -> OKResponse {
		try await send("/api/notify/test", method: "POST")
	}

	private func get<T: Decodable>(_ type: T.Type, from path: String) async throws -> T {
		try await get(path)
	}

	private func send<T: Decodable>(_ type: T.Type, from path: String,
	                                method: String, body: [String: Any]? = nil) async throws -> T {
		try await send(path, method: method, body: body)
	}
}
