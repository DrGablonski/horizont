import Foundation

/// HTTP-Client für die Horizont-API.
/// Auth: Session-Cookie (vom Login) im gemeinsamen Cookie-Storage.
/// Bei 401 meldet sich AuthStore ab bzw. loggt still neu ein.
public final class APIClient {
	public let baseURL: URL
	private let session: URLSession

	public init(serverURL: URL) {
		self.baseURL = serverURL
		let config = URLSessionConfiguration.default
		config.httpAdditionalHeaders = ["Accept": "application/json"]
		config.timeoutIntervalForRequest = 20
		self.session = URLSession(configuration: config)
	}

	// MARK: – Kern

	@discardableResult
	public func raw(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> Data {
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

	public func login(username: String, password: String) async throws -> AppUser {
		let r: LoginResponse = try await send(
			"/api/auth/login", method: "POST",
			body: ["username": username, "password": password])
		return r.user
	}

	public func me() async throws -> AppUser {
		let r: MeResponse = try await get("/api/auth/me")
		return r.user
	}

	public func logout() async throws {
		_ = try await send(OKResponse.self, in: "/api/auth/logout")
	}

	private func send(_ type: OKResponse.Type, in path: String) async throws {
		_ = try await raw(path, method: "POST")
	}

	// MARK: – Events / Timeline

	public func mainEvents() async throws -> MainEventsResponse {
		try await get("/api/events?scope=main")
	}

	public func archiveMonth(_ monthKey: String?) async throws -> ArchiveMonth {
		if let monthKey {
			return try await get("/api/events?scope=archive&monat=\(monthKey)")
		}
		return try await get("/api/events?scope=archive")
	}

	// MARK: – Workflows

	public func workflows() async throws -> [Workflow] {
		try await get("/api/workflows")
	}

	public func updateStep(workflowId: String, stepId: String, done: Bool) async throws -> Workflow {
		try await send("/api/workflows/\(workflowId)/steps/\(stepId)",
		              method: "PATCH", body: ["done": done])
	}

	public func resetWorkflow(workflowId: String) async throws -> Workflow {
		try await send("/api/workflows/\(workflowId)/reset", method: "POST")
	}

	/// Workflow anlegen (POST /api/workflows). steps = Titel, einer pro Schritt.
	@discardableResult
	public func createWorkflow(title: String, steps: [String]) async throws -> Workflow {
		try await send("/api/workflows", method: "POST",
		              body: ["title": title, "steps": steps])
	}

	/// Titel/Notizen ändern (PATCH /api/workflows/{id}). Nil-Felder bleiben unverändert.
	@discardableResult
	public func updateWorkflow(workflowId: String, title: String? = nil,
	                    notes: String? = nil) async throws -> Workflow {
		var body: [String: Any] = [:]
		if let title { body["title"] = title }
		if let notes { body["notes"] = notes }
		return try await send("/api/workflows/\(workflowId)", method: "PATCH", body: body)
	}

	public func deleteWorkflow(workflowId: String) async throws {
		_ = try await raw("/api/workflows/\(workflowId)", method: "DELETE")
	}

	/// Schritt anhängen (POST /api/workflows/{id}/steps).
	@discardableResult
	public func addStep(workflowId: String, title: String) async throws -> Workflow {
		try await send("/api/workflows/\(workflowId)/steps", method: "POST",
		              body: ["title": title])
	}

	/// Schritt umbenennen (PATCH …/steps/{stepId}).
	@discardableResult
	public func setStepTitle(workflowId: String, stepId: String, title: String) async throws -> Workflow {
		try await send("/api/workflows/\(workflowId)/steps/\(stepId)",
		              method: "PATCH", body: ["title": title])
	}

	/// Schritt löschen (DELETE …/steps/{stepId}).
	@discardableResult
	public func deleteStep(workflowId: String, stepId: String) async throws -> Workflow {
		try await send("/api/workflows/\(workflowId)/steps/\(stepId)", method: "DELETE")
	}

	// MARK: – Tasks (abhaken, anlegen, löschen)

	public func updateTaskCompleted(calendarId: String, uid: String, completed: Bool) async throws {
		_ = try await raw("/api/tasks/\(calendarId)/\(uid)",
		                  method: "PATCH", body: ["completed": completed])
	}

	/// Task-Felder ändern (PATCH /api/tasks/{cal}/{uid}). Nil-Felder bleiben unverändert.
	@discardableResult
	public func updateTask(calendarId: String, uid: String, summary: String? = nil,
	                description: String? = nil, category: String?? = nil,
	                dueKey: String?? = nil) async throws -> OKResponse {
		var body: [String: Any] = [:]
		if let summary { body["summary"] = summary }
		if let description { body["description"] = description }
		if let category { body["category"] = category ?? NSNull() }
		if let dueKey { body["due"] = dueKey.map { ["kind": "date", "key": $0] } ?? ["kind": "none"] as Any }
		return try await send("/api/tasks/\(calendarId)/\(uid)", method: "PATCH", body: body)
	}

	/// Termin-Felder ändern (PATCH /api/events/{cal}/{uid}).
	@discardableResult
	public func updateEvent(calendarId: String, uid: String, summary: String,
	                 allDay: Bool, dayKey: String? = nil, startMs: Int? = nil,
	                 endMs: Int? = nil, location: String? = nil,
	                 description: String? = nil) async throws -> EventItem {
		var body: [String: Any] = ["summary": summary, "allDay": allDay]
		if let dayKey { body["dayKey"] = dayKey }
		if let startMs { body["startMs"] = startMs }
		if let endMs { body["endMs"] = endMs }
		if let location { body["location"] = location }
		if let description { body["description"] = description }
		return try await send("/api/events/\(calendarId)/\(uid)", method: "PATCH", body: body)
	}

	/// Task anlegen (POST /api/tasks). dueKey = 'YYYY-MM-DD' oder nil.
	@discardableResult
	public func createTask(summary: String, calendarId: String, category: String? = nil,
	                dueKey: String? = nil, description: String? = nil) async throws -> CreatedTask {
		var body: [String: Any] = ["summary": summary, "calendarId": calendarId]
		if let category { body["category"] = category }
		if let dueKey { body["due"] = ["kind": "date", "key": dueKey] }
		if let description { body["description"] = description }
		return try await send("/api/tasks", method: "POST", body: body)
	}

	public func deleteTask(calendarId: String, uid: String) async throws {
		_ = try await raw("/api/tasks/\(calendarId)/\(uid)", method: "DELETE")
	}

	public func deleteEvent(calendarId: String, uid: String) async throws {
		_ = try await raw("/api/events/\(calendarId)/\(uid)", method: "DELETE")
	}

	/// Termin anlegen (POST /api/events). dayKey = 'YYYY-MM-DD', startMs optional für Ganztags=false.
	@discardableResult
	public func createEvent(summary: String, calendarId: String, dayKey: String,
	                 allDay: Bool, startMs: Int? = nil, location: String? = nil,
	                 description: String? = nil) async throws -> EventItem {
		var body: [String: Any] = [
			"summary": summary, "calendarId": calendarId,
			"dayKey": dayKey, "allDay": allDay
		]
		if let startMs { body["startMs"] = startMs }
		if let location { body["location"] = location }
		if let description { body["description"] = description }
		return try await send("/api/events", method: "POST", body: body)
	}

	// MARK: – Kalender

	public func calendars() async throws -> CalendarsResponse {
		try await get("/api/calendars")
	}

	/// Alle Kalender inkl. verborgener und Verbindungstexte (GET /api/calendars).
	public func fetchCalendars() async throws -> CalendarsResponse {
		try await get("/api/calendars")
	}

	/// Neuen Kalender per MKCALENDAR anlegen (POST /api/calendars);
	/// Antwort = die frische View des angelegten Kalenders.
	@discardableResult
	public func createCalendar(connectionId: String, name: String, color: String? = nil,
	                    components: [String]? = nil) async throws -> CalendarView {
		var body: [String: Any] = ["connectionId": connectionId, "name": name]
		if let color { body["color"] = color }
		if let components { body["components"] = components }
		return try await send("/api/calendars", method: "POST", body: body)
	}

	/// Kalender löschen (DELETE /api/calendars/{id}); der Name ist die
	/// Löschbestätigung und muss auf dem Server exakt passen.
	public func deleteCalendar(id: String, name: String) async throws {
		_ = try await send("/api/calendars/\(id)", method: "DELETE",
		                   body: ["name": name]) as OKResponse
	}

	/// Lokale Präferenzen eines Kalenders ändern (PATCH /api/calendars/{id}),
	/// z. B. ["hidden": true] oder ["isDefault": true]; Antwort = aktualisierter Kalender.
	@discardableResult
	public func updateCalendar(id: String, patch: [String: Any]) async throws -> CalendarView {
		try await send("/api/calendars/\(id)", method: "PATCH", body: patch)
	}

	// MARK: – Einstellungen: CalDAV-Verbindungen

	public func connections() async throws -> ConnectionsResponse {
		try await get("/api/settings")
	}

	/// Verbindung anlegen (POST /api/settings); Antwort = aktualisierte Liste.
	@discardableResult
	public func createConnection(name: String, url: String, username: String,
	                      password: String) async throws -> ConnectionsResponse {
		try await send("/api/settings", method: "POST",
		              body: ["name": name, "url": url,
		                     "username": username, "password": password])
	}

	/// Verbindung ändern (PATCH /api/settings); leere Password = gespeichertes behalten.
	@discardableResult
	public func updateConnection(id: String, name: String, url: String,
	                      username: String, password: String?) async throws -> ConnectionsResponse {
		var body: [String: Any] = ["id": id, "name": name, "url": url, "username": username]
		if let password, !password.isEmpty { body["password"] = password }
		return try await send("/api/settings", method: "PATCH", body: body)
	}

	/// Verbindung löschen (DELETE /api/settings); Antwort = aktualisierte Liste.
	@discardableResult
	public func deleteConnection(id: String) async throws -> ConnectionsResponse {
		try await send("/api/settings", method: "DELETE", body: ["id": id])
	}

	/// Verbindung zur Hauptverbindung machen (PATCH /api/settings mit role:'primary';
	/// die bisherige wird automatisch herabgestuft). Antwort = aktualisierte Liste.
	@discardableResult
	public func setPrimaryConnection(id: String) async throws -> ConnectionsResponse {
		try await send("/api/settings", method: "PATCH", body: ["id": id, "role": "primary"])
	}

	/// Anbieter-Vorlagen fürs Verbindungsformular (GET /api/settings/presets).
	public func providerPresets() async throws -> [ProviderPreset] {
		let r: ProviderPresetsResponse = try await get("/api/settings/presets")
		return r.presets
	}

	/// Gespeicherte Verbindung per id testen.
	public func testConnection(id: String) async throws -> TestResult {
		try await send("/api/settings/test", method: "POST", body: ["id": id])
	}

	/// Ungespeicherte Formularwerte testen („Erst testen" vor dem Anlegen).
	public func testConnection(url: String, username: String, password: String) async throws -> TestResult {
		try await send("/api/settings/test", method: "POST",
		              body: ["url": url, "username": username, "password": password])
	}

	// MARK: – Kategorien

	public func categories() async throws -> [TaskCategory] {
		try await get(CategoriesResponse.self, from: "/api/categories").categories
	}

	/// Ganze Liste ersetzen (wie Web-App).
	public func saveCategories(_ categories: [TaskCategory]) async throws -> [TaskCategory] {
		let body = ["categories": categories.map { ["name": $0.name, "color": $0.color] }]
		return try await send(CategoriesResponse.self, from: "/api/categories",
		                      method: "POST", body: body).categories
	}

	// MARK: – Benachrichtigungen

	public func notifyConfig() async throws -> NotifyConfigView {
		try await get("/api/notify")
	}

	public func saveNotifyConfig(_ input: [String: Any]) async throws -> NotifyConfigView {
		try await send("/api/notify", method: "POST", body: input)
	}

	/// Testversand (POST /api/notify/test). Leere Werte fallen auf die gespeicherte Config zurück.
	public func sendNotifyTest(url: String = "", token: String = "",
	                    prompt: String = "") async throws -> NotifyTestResult {
		var body: [String: Any] = [:]
		if !url.isEmpty { body["url"] = url }
		if !token.isEmpty { body["token"] = token }
		if !prompt.isEmpty { body["prompt"] = prompt }
		return try await send("/api/notify/test", method: "POST", body: body)
	}

	/// „Jetzt senden" (POST /api/notify/send): echte offene Tasks nach gespeicherter Config.
	public func sendNotifyNow() async throws -> NotifySendResult {
		try await send("/api/notify/send", method: "POST")
	}

	// MARK: – API-Token (externe Zugriffe/MCP)

	public func apiToken() async throws -> ApiTokenView {
		try await get("/api/token")
	}

	/// Neuen Token erzeugen (ersetzt vorhandenen) – Klartext nur in dieser Antwort.
	public func generateApiToken() async throws -> ApiTokenGenerated {
		try await send("/api/token", method: "POST")
	}

	public func revokeApiToken() async throws {
		_ = try await raw("/api/token", method: "DELETE")
	}

	private func get<T: Decodable>(_ type: T.Type, from path: String) async throws -> T {
		try await get(path)
	}

	private func send<T: Decodable>(_ type: T.Type, from path: String,
	                                method: String, body: [String: Any]? = nil) async throws -> T {
		try await send(path, method: method, body: body)
	}
}
