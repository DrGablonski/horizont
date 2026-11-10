import SwiftUI

/// Einstellungen: Sidebar-Navigation wie die Systemeinstellungen –
/// Darstellung, Konto, CalDAV, Kategorien, Mitteilungen, API-Zugang
/// (je eine Seite, kein Gesamt-Scroll). Volle Parität zur Server-API:
/// CalDAV-CRUD, Kategorien, Webhook inkl. Token, API-Token-Verwaltung.
struct SettingsView: View {
	/// Bereiche der Einstellungs-Sidebar.
	enum Area: String, CaseIterable, Identifiable {
		case appearance = "Darstellung"
		case account = "Konto"
		case caldav = "CalDAV"
		case kategorien = "Kategorien"
		case notify = "Mitteilungen"
		case token = "API-Zugang"

		var id: String { rawValue }

		var icon: String {
			switch self {
			case .appearance: return "paintpalette"
			case .account: return "person.crop.circle"
			case .caldav: return "calendar"
			case .kategorien: return "tag"
			case .notify: return "bell"
			case .token: return "key"
			}
		}

		/// Subtitle im Bereichskopf.
		var subtitle: String {
			switch self {
			case .appearance: return "Feste Designs – Helligkeit & Akzent"
			case .account: return "Profil, Server & Abmelden"
			case .caldav: return "CalDAV-Verbindungen & Kalender"
			case .kategorien: return "Namen & Farben für Aufgaben"
			case .notify: return "Aufgaben-Zusammenfassung per Webhook"
			case .token: return "Zugriff für MCP & externe Tools"
			}
		}
	}

	static let areaKey = "hz.settingsArea"   // Snapshot-QA setzt den Bereich vorab

	@State private var area: Area

	init() {
		let raw = UserDefaults.standard.string(forKey: Self.areaKey) ?? Area.appearance.rawValue
		_area = State(initialValue: Area(rawValue: raw) ?? .appearance)
	}

	var body: some View {
		NavigationStack {
			VStack(spacing: 0) {
				SectionHeader("Einstellungen", subtitle: area.subtitle)

				HStack(spacing: 0) {
					areaSidebar
					Divider().overlay(DS.border)
					Group {
						switch area {
						case .appearance: AppearancePage()
						case .account: AccountPage()
						case .caldav: CalDAVPage()
						case .kategorien: CategoriesPage()
						case .notify: NotifyPage()
						case .token: ApiTokenPage()
						}
					}
					.frame(maxWidth: .infinity, maxHeight: .infinity)
				}
			}
		}
	}

	/// Linke Bereichsliste (Auswahl bleibt über Bereichs-/App-Wechsel erhalten).
	private var areaSidebar: some View {
		VStack(spacing: DS.Space.xs) {
			ForEach(Area.allCases) { a in
				AreaRow(area: a, isActive: area == a) { select(a) }
			}
			Spacer()
		}
		.padding(DS.Space.md)
		.frame(width: 190)
		.frame(maxHeight: .infinity, alignment: .top)
		.background(DS.sidebar)
	}

	private func select(_ a: Area) {
		area = a
		UserDefaults.standard.set(a.rawValue, forKey: Self.areaKey)
	}
}

// MARK: – Sidebar-Zeile

/// Einstellungs-Bereich in der Sidebar (Auswahl: Akzent-Pille wie NavPill).
private struct AreaRow: View {
	let area: SettingsView.Area
	let isActive: Bool
	let action: () -> Void

	@State private var hovering = false

	var body: some View {
		Button(action: action) {
			HStack(spacing: DS.Space.sm) {
				Image(systemName: area.icon)
					.font(.system(size: 12, weight: .medium))
					.foregroundStyle(isActive ? DS.accent : DS.textSecondary)
				Text(area.rawValue)
					.font(.callout.weight(isActive ? .semibold : .medium))
					.foregroundStyle(isActive ? DS.textPrimary : DS.textSecondary)
					.lineLimit(1)
				Spacer(minLength: 0)
			}
			.padding(.horizontal, DS.Space.md)
			.padding(.vertical, 8)
			.background(
				RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
					.fill(isActive ? DS.tintSoft : hovering ? DS.rowHover : Color.clear)
			)
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.onHover { hovering = $0 }
		.animation(.easeOut(duration: 0.12), value: hovering)
		.animation(.easeOut(duration: 0.12), value: isActive)
	}
}

// MARK: – Seitenrahmen

/// Einheitlicher Seitenrahmen: Karten mittig, scrollt nur wenn nötig.
private struct SettingsPage<Content: View>: View {
	@ViewBuilder var content: Content

	var body: some View {
		ScrollView {
			VStack(spacing: DS.Space.lg) {
				content
			}
			.padding(DS.Space.xl)
			.frame(maxWidth: 640)
			.frame(maxWidth: .infinity)
		}
	}
}

// MARK: – Bereich „Darstellung“

/// Feste Designs als wählbare Kacheln (je kompletter Look inkl. Hell/Dunkel).
private struct AppearancePage: View {
	@Environment(ThemeStore.self) private var theme

	var body: some View {
		SettingsPage {
			SettingsSectionCard(title: "Design") {
				Text("Vier feste Designs – sie legen Helligkeit und Akzentfarbe gemeinsam fest. Die Wahl wirkt sofort im ganzen Fenster.")
					.font(.callout)
					.foregroundStyle(DS.textSecondary)

				LazyVGrid(
					columns: [GridItem(.adaptive(minimum: 180, maximum: 240), spacing: DS.Space.md)],
					spacing: DS.Space.md
				) {
					ForEach(AppDesign.allCases) { design in
						DesignCard(design: design, isActive: theme.design == design) {
							theme.design = design
						}
					}
				}
			}
		}
	}
}

/// Design-Kachel mit Mini-Fenster-Vorschau (farben fix, unabhängig vom aktiven Design).
private struct DesignCard: View {
	let design: AppDesign
	let isActive: Bool
	let action: () -> Void

	@State private var hovering = false

	var body: some View {
		Button(action: action) {
			VStack(alignment: .leading, spacing: DS.Space.sm) {
				mockup
				HStack(alignment: .top, spacing: DS.Space.xs) {
					VStack(alignment: .leading, spacing: DS.Space.xxs) {
						Text(design.name)
							.font(.callout.weight(isActive ? .semibold : .medium))
							.foregroundStyle(DS.textPrimary)
						Text(design.subtitle)
							.font(DS.Typo.meta)
							.foregroundStyle(DS.textSecondary)
					}
					Spacer(minLength: DS.Space.xs)
					if isActive {
						Image(systemName: "checkmark.circle.fill")
							.foregroundStyle(DS.accent)
					}
				}
			}
			.padding(DS.Space.md)
			.frame(maxWidth: .infinity, alignment: .leading)
			.background(
				RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
					.fill(DS.card)
			)
			.overlay(
				RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
					.strokeBorder(
						isActive ? DS.accent : hovering ? DS.borderStrong : DS.border,
						lineWidth: isActive ? 2 : 1)
			)
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.onHover { hovering = $0 }
		.accessibilityLabel("\(design.name) – \(design.subtitle)")
	}

	/// Mini-Fenster: Titelzeile mit Ampel-Punkten + Inhalt in Design-Farben.
	private var mockup: some View {
		let bg = staticRGB(design.isDark ? 0x14151A : 0xF4F5F7)
		let surface = staticRGB(design.isDark ? 0x1C1E25 : 0xFFFFFF)
		let bar = staticRGB(design.isDark ? 0x2A2D36 : 0xE4E6EC)
		let edge = staticRGB(design.isDark ? 0x2A2D36 : 0xD8DAE0)
		let accent = staticRGB(design.accentRGB)
		return VStack(spacing: 0) {
			HStack(spacing: 3) {
				ForEach(0..<3, id: \.self) { _ in
					Circle().fill(bar).frame(width: 5, height: 5)
				}
				Spacer()
			}
			.padding(6)
			VStack(alignment: .leading, spacing: 5) {
				RoundedRectangle(cornerRadius: 2).fill(accent)
					.frame(width: 44, height: 7)
				RoundedRectangle(cornerRadius: 2).fill(bar)
					.frame(width: 120, height: 5)
				RoundedRectangle(cornerRadius: 2).fill(bar)
					.frame(width: 90, height: 5)
			}
			.frame(maxWidth: .infinity, alignment: .leading)
			.padding(8)
			.background(surface)
		}
		.background(bg)
		.clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
		.overlay(
			RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
				.strokeBorder(edge, lineWidth: 1)
		)
	}
}

// MARK: – Bereich „Konto“

/// Profil, Server-URL, Version und Abmelden auf einer Seite.
private struct AccountPage: View {
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
		SettingsPage {
			SettingsSectionCard(title: "Profil") {
				LabeledContent {
					Text(auth.user?.username ?? "–")
				} label: {
					HStack(spacing: DS.Space.md) {
						avatar
						Text("Angemeldet als")
					}
				}
			}

			SettingsSectionCard(title: "Server") {
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

			SettingsSectionCard(title: "Info") {
				LabeledContent("Version", value: appVersion)
			}

			// Abmelden ohne Sektionstitel (wie bisher).
			Button("Abmelden", role: .destructive) {
				Task { await auth.logout() }
			}
			.frame(maxWidth: .infinity)
			.padding(DS.Space.md)
			.dsCard()
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
				.foregroundStyle(DS.accent)
		}
		.frame(width: 28, height: 28)
	}
}

// MARK: – Bereich „CalDAV“

/// CalDAV-Verbindungen + Kalenderübersicht untereinander.
private struct CalDAVPage: View {
	var body: some View {
		SettingsPage {
			ConnectionsSection()
			CalendarsSection()
		}
	}
}

// MARK: – Bereich „Mitteilungen“

/// Aufgaben-Benachrichtigungen (Webhook-Formular).
private struct NotifyPage: View {
	var body: some View {
		SettingsPage {
			NotifySection()
		}
	}
}

// MARK: – Bereich „Kategorien"

/// Aufgaben-Kategorien (Name + Farbe), voll verwaltbar.
private struct CategoriesPage: View {
	var body: some View {
		SettingsPage {
			CategoriesSection()
		}
	}
}

// MARK: – Bereich „API-Zugang"

/// API-Token für externe Tools (MCP).
private struct ApiTokenPage: View {
	var body: some View {
		SettingsPage {
			ApiTokenSection()
		}
	}
}

// MARK: – Sektionskarte

/// Einheitliche Sektionskarte mit Titel (dsCard-Fläche im Web-Look).
private struct SettingsSectionCard<Content: View>: View {
	let title: String
	@ViewBuilder var content: Content

	var body: some View {
		VStack(alignment: .leading, spacing: DS.Space.md) {
			Text(title)
				.font(DS.Typo.cardTitle)
				.foregroundStyle(DS.textPrimary)
			content
		}
		.padding(DS.Space.lg)
		.frame(maxWidth: .infinity, alignment: .leading)
		.dsCard()
	}
}

// MARK: – CalDAV-Verbindungen

/// CalDAV-Verbindungen mit voller Verwaltung (CRUD + Test) wie in der Web-App.
private struct ConnectionsSection: View {
	@Environment(AppStore.self) private var store

	@State private var results: [String: TestResult] = [:]
	@State private var errors: [String: String] = [:]
	@State private var testing: Set<String> = []

	// Inline-Bearbeitung (id der gerade bearbeiteten Verbindung).
	@State private var editingId: String?
	@State private var editName = ""
	@State private var editUrl = ""
	@State private var editUsername = ""
	@State private var editPassword = ""
	@State private var editSaving = false
	@State private var editError: String?

	// Löschen mit Bestätigung.
	@State private var deleteCandidate: ConnectionView?
	@State private var deleting = false

	// Neues Formular (aufklappbar).
	@State private var showNew = false
	@State private var newName = ""
	@State private var newUrl = ""
	@State private var newUsername = ""
	@State private var newPassword = ""
	@State private var newSaving = false
	@State private var newTesting = false
	@State private var newError: String?
	@State private var newFormResult: TestResult?

	var body: some View {
		SettingsSectionCard(title: "CalDAV-Verbindungen") {
			if store.connections.isEmpty && !showNew {
				Text("Noch keine CalDAV-Quelle eingerichtet.")
					.font(.callout)
					.foregroundStyle(DS.textSecondary)
			} else if !store.connections.isEmpty {
				VStack(alignment: .leading, spacing: DS.Space.sm) {
					ForEach(store.connections) { conn in
						connectionBlock(conn)
					}
				}
			}
			newSourceCard
		}
		.task { await store.loadConnections() }
		.confirmationDialog(
			"„\(deleteCandidate?.name ?? "")“ wirklich löschen?",
			isPresented: Binding(
				get: { deleteCandidate != nil },
				set: { presenting in if !presenting { deleteCandidate = nil } }
			),
			titleVisibility: .visible
		) {
			Button("Löschen", role: .destructive) { confirmDelete() }
		} message: {
			Text("Die Verbindung wird aus Horizont entfernt; in CalDAV bleiben die Daten unverändert.")
		}
	}

	// MARK: Karte pro Verbindung

	/// Karte pro Verbindung; Bearbeiten zeigt Inline-Formular, Fehlerbanner darunter.
	@ViewBuilder
	private func connectionBlock(_ conn: ConnectionView) -> some View {
		VStack(alignment: .leading, spacing: DS.Space.sm) {
			VStack(alignment: .leading, spacing: DS.Space.sm) {
				HStack(spacing: DS.Space.sm) {
					Text(conn.name)
						.font(DS.Typo.rowTitle)
						.foregroundStyle(DS.textPrimary)
						.lineLimit(1)
					Spacer(minLength: DS.Space.sm)
					if editingId == conn.id {
						// (Formular folgt unten – Buttons hier ausblenden.)
					} else {
						testButton(conn)
						Button("Bearbeiten") { beginEdit(conn) }
							.buttonStyle(.bordered)
						Button("Löschen", role: .destructive) { deleteCandidate = conn }
							.buttonStyle(.bordered)
							.disabled(deleting)
					}
				}
				Text(conn.url)
					.font(DS.Typo.meta)
					.foregroundStyle(DS.textSecondary)
					.lineLimit(1)
					.truncationMode(.middle)
				HStack(spacing: DS.Space.sm) {
					Chip(text: conn.username, systemImage: "person.fill")
					if conn.hasPassword {
						Chip(text: "Passwort gesetzt", color: DS.success, systemImage: "lock.fill")
					}
					if let res = results[conn.id], res.ok {
						let count = res.calendars?.count ?? 0
						Chip(text: "Verbunden, \(count) Kalender",
						     color: DS.success, systemImage: "checkmark.circle.fill")
					}
				}

				if editingId == conn.id {
					editForm(for: conn)
				}
			}
			.padding(DS.Space.md)
			.frame(maxWidth: .infinity, alignment: .leading)
			.dsCard()

			if let err = errors[conn.id] {
				ErrorBanner(message: err, retry: { test(conn) })
			}
		}
	}

	// MARK: Inline-Bearbeitung

	/// Bearbeitungsformular innerhalb der Karte (leeres Passwort = gespeichertes behalten).
	@ViewBuilder
	private func editForm(for conn: ConnectionView) -> some View {
		Divider()
		VStack(alignment: .leading, spacing: DS.Space.sm) {
			settingsField("Name", text: $editName)
			settingsField("URL", text: $editUrl, placeholder: "https://…")
			settingsField("Benutzername", text: $editUsername)
			settingsField("Passwort", text: $editPassword, secure: true,
			              placeholder: "●●●● (leer lassen = behalten)")
			if let err = editError {
				Text(err).font(.caption).foregroundStyle(DS.danger)
			}
			HStack(spacing: DS.Space.sm) {
				Button("Speichern") { saveEdit(conn) }
					.disabled(editSaving || editName.trimmed.isEmpty || editUrl.trimmed.isEmpty)
					.primaryButton()
				Button("Abbrechen") { cancelEdit() }
					.buttonStyle(.bordered)
					.disabled(editSaving)
			}
		}
	}

	private func beginEdit(_ conn: ConnectionView) {
		editingId = conn.id
		editName = conn.name
		editUrl = conn.url
		editUsername = conn.username
		editPassword = ""
		editError = nil
	}

	private func cancelEdit() {
		editingId = nil
		editError = nil
	}

	private func saveEdit(_ conn: ConnectionView) {
		guard !editSaving else { return }
		editSaving = true
		editError = nil
		let name = editName.trimmed
		let urlValue = editUrl.trimmed
		let username = editUsername.trimmed
		let password = editPassword
		Task {
			let err = await store.updateConnection(
				id: conn.id, name: name, url: urlValue, username: username, password: password)
			editSaving = false
			if let err {
				editError = err
			} else {
				editingId = nil
				results.removeValue(forKey: conn.id)
			}
		}
	}

	// MARK: Löschen

	private func confirmDelete() {
		guard let conn = deleteCandidate, !deleting else { return }
		deleting = true
		Task {
			let err = await store.deleteConnection(id: conn.id)
			deleting = false
			deleteCandidate = nil
			results.removeValue(forKey: conn.id)
			errors.removeValue(forKey: conn.id)
			if let err {
				errors[conn.id] = err
			}
		}
	}

	// MARK: Neu anlegen

	/// Aufklappbare „CalDAV-Quelle anlegen"-Karte mit Feldern + „Erst testen".
	@ViewBuilder
	private var newSourceCard: some View {
		if showNew {
			VStack(alignment: .leading, spacing: DS.Space.sm) {
				HStack {
					Text("CalDAV-Quelle anlegen")
						.font(DS.Typo.rowTitle)
						.foregroundStyle(DS.textPrimary)
					Spacer()
					Button {
						showNew = false
						newError = nil
						newFormResult = nil
					} label: {
						Image(systemName: "xmark")
					}
					.buttonStyle(.borderless)
					.help("Abbrechen")
				}
				settingsField("Name", text: $newName, placeholder: "z. B. iCloud")
				settingsField("URL", text: $newUrl, placeholder: "https://caldav.icloud.com/")
				settingsField("Benutzername", text: $newUsername, placeholder: "E-Mail")
				settingsField("Passwort", text: $newPassword, secure: true,
				              placeholder: "App-spezifisches Passwort")
				if let res = newFormResult {
					ResultBanner(
						ok: res.ok,
						title: res.ok
							? "Verbindung funktioniert."
							: "Verbindungstest fehlgeschlagen.",
						detail: res.ok
							? "Gefundene Kalender: \(res.calendars?.count ?? 0)"
							: res.error)
				}
				if let err = newError {
					ErrorBanner(message: err)
				}
				HStack(spacing: DS.Space.sm) {
					Button("Speichern") { createConnection() }
						.disabled(newSaving || newTesting
						          || newName.trimmed.isEmpty || newUrl.trimmed.isEmpty
						          || newUsername.trimmed.isEmpty || newPassword.isEmpty)
						.primaryButton()
					Button {
						testNewForm()
					} label: {
						if newTesting {
							HStack(spacing: DS.Space.xs) {
								ProgressView().controlSize(.small)
								Text("Teste…")
							}
						} else {
							Text("Erst testen")
						}
					}
					.buttonStyle(.bordered)
					.disabled(newSaving || newTesting
					          || newUrl.trimmed.isEmpty || newUsername.trimmed.isEmpty
					          || newPassword.isEmpty)
				}
			}
			.padding(DS.Space.md)
			.frame(maxWidth: .infinity, alignment: .leading)
			.dsCard()
		} else {
			Button {
				showNew = true
			} label: {
				Label("CalDAV-Quelle anlegen", systemImage: "plus")
			}
			.buttonStyle(.bordered)
		}
	}

	private func createConnection() {
		guard !newSaving else { return }
		newSaving = true
		newError = nil
		newFormResult = nil
		let name = newName.trimmed
		let urlValue = newUrl.trimmed
		let username = newUsername.trimmed
		let password = newPassword
		Task {
			let err = await store.createConnection(
				name: name, url: urlValue, username: username, password: password)
			newSaving = false
			if let err {
				newError = err
			} else {
				showNew = false
				newName = ""
				newUrl = ""
				newUsername = ""
				newPassword = ""
				newFormResult = nil
			}
		}
	}

	/// Testet die Formularwerte, ohne sie zu speichern.
	private func testNewForm() {
		guard !newTesting else { return }
		newTesting = true
		newError = nil
		newFormResult = nil
		let urlValue = newUrl.trimmed
		let username = newUsername.trimmed
		let password = newPassword
		Task {
			newFormResult = await store.testConnection(
				url: urlValue, username: username, password: password)
			newTesting = false
		}
	}

	// MARK: Testen (bestehend)

	private func testButton(_ conn: ConnectionView) -> some View {
		Button {
			test(conn)
		} label: {
			if testing.contains(conn.id) {
				HStack(spacing: DS.Space.xs) {
					ProgressView().controlSize(.small)
					Text("Teste…")
				}
			} else {
				Text("Testen")
			}
		}
		.buttonStyle(.bordered)
		.disabled(testing.contains(conn.id))
	}

	/// Verbindung testen; Erfolg inline, Fehler als Banner unter der Karte.
	private func test(_ conn: ConnectionView) {
		guard !testing.contains(conn.id) else { return }
		testing.insert(conn.id)
		errors.removeValue(forKey: conn.id)
		results.removeValue(forKey: conn.id)
		Task {
			let res = await store.testConnection(id: conn.id)
			testing.remove(conn.id)
			if let res, res.ok {
				results[conn.id] = res
				await store.loadCalendars()
			} else {
				errors[conn.id] = res?.error ?? "Verbindung fehlgeschlagen."
			}
		}
	}
}

/// Beschriftiertes Formularfeld (Label über Eingabe) für Settings-Formulare.
@ViewBuilder
private func settingsField(_ label: String, text: Binding<String>,
                           secure: Bool = false, placeholder: String = "") -> some View {
	VStack(alignment: .leading, spacing: DS.Space.xs) {
		Text(label)
			.font(DS.Typo.metaStrong)
			.foregroundStyle(DS.textSecondary)
		if secure {
			SecureField(placeholder, text: text)
				.autocorrectionDisabled()
		} else {
			TextField(placeholder, text: text)
				.autocorrectionDisabled()
		}
	}
}

// MARK: – Kalender

/// Übersicht aller CalDAV-Kalender (Farbpunkt + Name + Verbindung).
private struct CalendarsSection: View {
	@Environment(AppStore.self) private var store

	var body: some View {
		SettingsSectionCard(title: "Kalender") {
			if store.calendars.isEmpty {
				EmptyStateView(
					title: "Keine Kalender gefunden.",
					systemImage: "calendar",
					description: store.calendarsLoaded
						? "Verbindungen prüfen oder eine neue Quelle anlegen."
						: nil
				)
				.frame(height: 170)
			} else {
				VStack(spacing: DS.Space.sm) {
					ForEach(store.calendars) { cal in
						HStack(spacing: DS.Space.sm) {
							Circle()
								.fill(dsColor(hex: cal.color) ?? DS.textTertiary)
								.frame(width: 10, height: 10)
							Text(cal.name)
								.font(DS.Typo.rowTitle)
								.foregroundStyle(DS.textPrimary)
								.lineLimit(1)
							if let connName = cal.connectionName {
								Chip(text: connName)
							}
							Spacer(minLength: DS.Space.sm)
						}
					}
				}
			}
		}
		.task {
			if !store.calendarsLoaded { await store.loadCalendars() }
		}
	}
}

// MARK: – Aufgaben-Benachrichtigungen

/// Webhook-Konfiguration für die Aufgaben-Zusammenfassung (Parität zur Web-App).
private struct NotifySection: View {
	@Environment(AppStore.self) private var store

	// Arbeitskopie der Konfiguration (wird aus store.notify initialisiert).
	@State private var frequency: NotifyFrequency = .manual
	@State private var time = "08:00"
	@State private var weekday = 0
	@State private var intervalHours = 3
	@State private var url = ""
	@State private var token = ""
	@State private var prompt = ""
	@State private var selectedCategories: Set<String> = []
	@State private var seeded = false

	// „Komplette Webhook-URL einfügen" → URL + Token aufteilen.
	@State private var importUrl = ""
	@State private var importError: String?

	@State private var saving = false
	@State private var saveError: String?
	@State private var savedFlash = false
	@State private var testingSend = false
	@State private var testResult: NotifyTestResult?
	@State private var sendingNow = false
	@State private var sendResult: NotifySendResult?

	private let weekdayNames = ["Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag"]

	/// Zeitfeld wird nur für tägliche/wöchentliche Läufe benötigt.
	private var showsTime: Bool { frequency == .daily || frequency == .weekly }

	var body: some View {
		SettingsSectionCard(title: "Aufgaben-Benachrichtigungen") {
			if let notify = store.notify {
				headerRow(notify)

				VStack(alignment: .leading, spacing: DS.Space.xs) {
					Text("Komplette Webhook-URL einfügen")
						.font(DS.Typo.metaStrong)
						.foregroundStyle(DS.textSecondary)
					HStack(spacing: DS.Space.sm) {
						TextField("https://…/webhook/a1b2c3d4", text: $importUrl)
							.autocorrectionDisabled()
						Button("Aufteilen") { splitWebhookURL() }
							.buttonStyle(.bordered)
							.disabled(importUrl.trimmed.isEmpty)
					}
					Text("Am einfachsten: die ganze URL vom Dienst einfügen — Horizont trennt sie automatisch in Adresse und Zugriffsschlüssel.")
						.font(.caption)
						.foregroundStyle(DS.textSecondary)
					if let err = importError {
						Text(err).font(.caption).foregroundStyle(DS.danger)
					}
				}

				Picker("Frequenz", selection: $frequency) {
					Text("Aus").tag(NotifyFrequency.manual)
					Text("Täglich").tag(NotifyFrequency.daily)
					Text("Wöchentlich").tag(NotifyFrequency.weekly)
					Text("Intervall").tag(NotifyFrequency.interval)
				}
				.pickerStyle(.segmented)
				.labelsHidden()

				if showsTime {
					VStack(alignment: .leading, spacing: DS.Space.xs) {
						Text("Sendezeit")
							.font(DS.Typo.metaStrong)
							.foregroundStyle(DS.textSecondary)
						TextField("Zeit (HH:MM)", text: $time)
							.frame(maxWidth: 140)
							.autocorrectionDisabled()
						if !isValidTime(time) {
							Text("Format: HH:MM (z. B. 07:30)")
								.font(.caption)
								.foregroundStyle(DS.danger)
						}
					}
				}

				if frequency == .weekly {
					Picker("Wochentag", selection: $weekday) {
						ForEach(0..<7, id: \.self) { idx in
							Text(weekdayNames[idx]).tag(idx)
						}
					}
				}

				if frequency == .interval {
					Stepper("\(intervalHours) Stunden", value: $intervalHours, in: 1...23)
				}

				VStack(alignment: .leading, spacing: DS.Space.xs) {
					Text("Webhook-URL")
						.font(DS.Typo.metaStrong)
						.foregroundStyle(DS.textSecondary)
					TextField("https://…", text: $url)
						.autocorrectionDisabled()
					Text("Adresse des Dienstes, der die Nachrichten empfängt — alles direkt vor dem Zugriffsschlüssel.")
						.font(.caption)
						.foregroundStyle(DS.textSecondary)
				}

				VStack(alignment: .leading, spacing: DS.Space.xs) {
					Text("Zugriffsschlüssel (Token)")
						.font(DS.Typo.metaStrong)
						.foregroundStyle(DS.textSecondary)
					SecureField(notify.hasToken
					            ? "Gespeichert — leer lassen, um ihn zu behalten"
					            : "Der geheime Teil am Ende der Webhook-URL",
					            text: $token)
						.autocorrectionDisabled()
					Text(notify.hasToken
					      ? "Ein Zugriffsschlüssel ist gespeichert — neu ausfüllen, um ihn zu ersetzen."
					      : "Noch kein Zugriffsschlüssel — du bekommst ihn zusammen mit der Webhook-URL.")
						.font(.caption)
						.foregroundStyle(DS.textSecondary)
				}

				VStack(alignment: .leading, spacing: DS.Space.xs) {
					Text("Nachricht ({{body}} = Aufgaben, {{stand}} = Stand)")
						.font(DS.Typo.metaStrong)
						.foregroundStyle(DS.textSecondary)
					TextField("Prompt", text: $prompt, axis: .vertical)
						.lineLimit(3)
						.autocorrectionDisabled()
				}

				VStack(alignment: .leading, spacing: DS.Space.sm) {
					Text("Kategorien")
						.font(DS.Typo.metaStrong)
						.foregroundStyle(DS.textSecondary)
					FlowLayout(spacing: DS.Space.sm) {
						ForEach(store.categories, id: \.name) { cat in
							categoryChip(cat)
						}
					}
				}

				if let err = saveError {
					ErrorBanner(message: err)
				}
				if savedFlash {
					ResultBanner(ok: true, title: "Benachrichtigung gespeichert.", detail: nil)
				}
				if let res = testResult {
					ResultBanner(
						ok: res.ok,
						title: res.ok ? "Webhook angenommen." : "Webhook-Test fehlgeschlagen.",
						detail: res.ok
							? Self.detail(forStatus: res.status, outcome: res.outcome,
							              fallback: "Die Nachricht sollte jetzt beim Empfänger angekommen sein.")
							: res.error)
				}
				if let res = sendResult {
					ResultBanner(
						ok: res.ok,
						title: res.ok
							? "Nachricht gesendet."
							: (res.skipped == true ? "Nichts gesendet." : "Senden fehlgeschlagen."),
						detail: res.ok
							? Self.detail(forStatus: res.status, outcome: res.outcome, fallback: nil)
							: (res.error ?? res.outcome))
				}

				if let run = notify.lastRun {
					Text("Letzter Lauf: \(run.date) · \(run.status)")
						.font(DS.Typo.meta)
						.foregroundStyle(DS.textTertiary)
				}

				HStack(spacing: DS.Space.sm) {
					Button("Speichern") { save() }
						.disabled(saving || (showsTime && !isValidTime(time)))
						.primaryButton()
					// Verschickt die echten offenen Tasks (unabhängig von der Automatik).
					Button {
						sendNow()
					} label: {
						if sendingNow {
							HStack(spacing: DS.Space.xs) {
								ProgressView().controlSize(.small)
								Text("Sende…")
							}
						} else {
							Text("Jetzt senden")
						}
					}
					.buttonStyle(.bordered)
					.disabled(sendingNow || notify.url == nil || !notify.hasToken)
					// Testet den Webhook mit den Werten aus dem Formular.
					Button {
						sendTest()
					} label: {
						if testingSend {
							HStack(spacing: DS.Space.xs) {
								ProgressView().controlSize(.small)
								Text("Sende…")
							}
						} else {
							Text("Testnachricht senden")
						}
					}
					.buttonStyle(.bordered)
					.disabled(testingSend)
				}
			} else {
				// Dezenter Ladezustand, bis store.notify vorhanden ist.
				HStack(spacing: DS.Space.sm) {
					ProgressView().controlSize(.small)
					Text("Lädt Konfiguration…")
						.font(.callout)
						.foregroundStyle(DS.textSecondary)
				}
			}
		}
		.task {
			// Erst seeden (Werte sofort sichtbar), dann Kategorien nachladen.
			if store.notify == nil { await store.loadNotify() }
			if let notify = store.notify, !seeded {
				seed(from: notify)
			}
			await store.loadCategories()
		}
	}

	/// Token-Status und Frequenz-Kurzinfo über dem Formular.
	private func headerRow(_ notify: NotifyConfigView) -> some View {
		HStack(spacing: DS.Space.sm) {
			Chip(text: notify.hasToken ? "Token gesetzt" : "Kein Token",
			     color: notify.hasToken ? DS.success : DS.textSecondary,
			     systemImage: "key.fill")
			Spacer(minLength: DS.Space.sm)
		}
	}

	/// Togglebarer Kategorien-Chip im Chip-Look des Design-Systems.
	private func categoryChip(_ cat: TaskCategory) -> some View {
		let color = dsColor(hex: cat.color) ?? DS.accent
		let on = selectedCategories.contains(cat.name)
		return Button {
			if on {
				selectedCategories.remove(cat.name)
			} else {
				selectedCategories.insert(cat.name)
			}
		} label: {
			HStack(spacing: DS.Space.xs) {
				if on {
					Image(systemName: "checkmark").font(.system(size: 9, weight: .semibold))
				}
				Text(cat.name).font(DS.Typo.chip)
			}
			.foregroundStyle(on ? color : DS.textSecondary)
			.padding(.horizontal, 7)
			.padding(.vertical, 3)
			.background(Capsule().fill(on ? color.opacity(0.16) : DS.fillSubtle))
			.overlay(
				Capsule().strokeBorder(on ? color.opacity(0.5) : Color.clear, lineWidth: 1)
			)
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
	}

	/// Arbeitskopie aus der geladenen Konfiguration füllen (nur einmal).
	private func seed(from notify: NotifyConfigView) {
		frequency = notify.frequency
		time = notify.time
		weekday = notify.weekday
		intervalHours = notify.intervalHours
		url = notify.url ?? ""
		token = ""          // Klartext-Token gibt der Server nie zurück
		prompt = notify.prompt
		selectedCategories = Set(notify.categories)
		seeded = true
	}

	/// Speichern über store.saveNotify; Erfolg = grüner Hinweistext, Fehler = Banner.
	private func save() {
		guard !saving else { return }
		let cats = store.categories
			.filter { selectedCategories.contains($0.name) }
			.map(\.name)
		guard !cats.isEmpty else {
			saveError = "Bitte mindestens eine Kategorie auswählen."
			return
		}
		saving = true
		saveError = nil
		savedFlash = false
		testResult = nil
		sendResult = nil
		Task {
			let err = await store.saveNotify(
				frequency: frequency,
				time: time,
				weekday: weekday,
				intervalHours: intervalHours,
				url: url.trimmed,
				token: token.trimmed,
				prompt: prompt,
				categories: cats
			)
			saving = false
			if let err {
				saveError = err
			} else {
				token = ""
				savedFlash = true
				DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
					savedFlash = false
				}
			}
		}
	}

	/// Testversand mit den aktuellen Formularwerten (leere Werte: gespeicherte Config).
	private func sendTest() {
		guard !testingSend else { return }
		if token.trimmed.isEmpty, store.notify?.hasToken != true {
			testResult = NotifyTestResult(ok: false, error: "Bitte zuerst einen Token angeben.")
			return
		}
		testingSend = true
		savedFlash = false
		testResult = nil
		let u = url.trimmed
		let tk = token.trimmed
		let pr = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
		Task {
			testResult = await store.sendNotifyTest(url: u, token: tk, prompt: pr)
			testingSend = false
		}
	}

	/// „Jetzt senden": echte offene Tasks über die gespeicherte Config verschicken.
	private func sendNow() {
		guard !sendingNow else { return }
		sendingNow = true
		sendResult = nil
		Task {
			sendResult = await store.sendNotifyNow()
			sendingNow = false
		}
	}

	/// Komplette Webhook-URL in Adresse + Token am letzten Pfad-Segment aufteilen.
	private func splitWebhookURL() {
		importError = nil
		var s = importUrl.trimmingCharacters(in: .whitespacesAndNewlines)
		while s.hasSuffix("/") { s.removeLast() }
		guard let slash = s.lastIndex(of: "/"), slash != s.startIndex else {
			importError = "Bitte die vollständige Webhook-URL einfügen."
			return
		}
		let head = String(s[..<slash])
		let tail = String(s[s.index(after: slash)...])
		guard head.hasPrefix("http"), !tail.isEmpty else {
			importError = "Bitte die vollständige Webhook-URL einfügen."
			return
		}
		url = head
		token = tail
		importUrl = ""
	}

	/// Detailzeile für Ergebnis-Banner: „HTTP 200 · Ergebnis: accepted".
	private static func detail(forStatus status: Int?, outcome: String?,
	                           fallback: String?) -> String? {
		var parts: [String] = []
		if let status { parts.append("HTTP \(status)") }
		if let outcome, !outcome.isEmpty { parts.append("Ergebnis: \(outcome)") }
		if parts.isEmpty { return fallback }
		return parts.joined(separator: " · ")
	}
}

// MARK: – Aufgaben-Kategorien

/// Task-Kategorien (Name + Farbe): umbenennen, einfärben, anlegen, löschen.
/// Farbänderungen werden entprellt automatisch gespeichert.
private struct CategoriesSection: View {
	@Environment(AppStore.self) private var store

	/// Arbeitskopie (identifiziert über den aktuellen Namen).
	@State private var rows: [TaskCategory] = []
	@State private var seeded = false

	/// Entprellter Speicher-Task pro Kategorie (Farbänderungen).
	@State private var colorSaves: [String: Task<Void, Never>] = [:]

	/// Umbenennen-Draft + Fehler pro Kategorie.
	@State private var renameDrafts: [String: String] = [:]
	@State private var rowErrors: [String: String] = [:]

	// Neue Kategorie.
	@State private var newName = ""
	@State private var newColor = Color(nsColor: .systemTeal)
	@State private var addError: String?

	@State private var saveError: String?
	@State private var showResetConfirm = false

	var body: some View {
		SettingsSectionCard(title: "Aufgaben-Kategorien") {
			Text("Hier benennst und einfärbst du die Kategorien, die du deinen Aufgaben geben kannst — z. B. „Schule“, „Privat“ oder „Garten“. Die Kategorie wird direkt in der Aufgabe gespeichert.")
				.font(.callout)
				.foregroundStyle(DS.textSecondary)

			if rows.isEmpty {
				Text("Keine Kategorien — lege unten eine an.")
					.font(.callout)
					.foregroundStyle(DS.textSecondary)
			} else {
				VStack(spacing: DS.Space.sm) {
					ForEach(rows, id: \.name) { cat in
						categoryRow(cat)
					}
				}
			}

			Divider()

			HStack(spacing: DS.Space.sm) {
				ColorPicker("", selection: $newColor)
					.labelsHidden()
				TextField("Neue Kategorie (z. B. Garten)", text: $newName)
					.onSubmit { addCategory() }
				Button("Hinzufügen") { addCategory() }
					.buttonStyle(.bordered)
					.disabled(TaskCategories.normalize(newName) == nil)
			}
			if let err = addError {
				Text(err).font(.caption).foregroundStyle(DS.danger)
			}
			if let err = saveError {
				ErrorBanner(message: err)
			}

			HStack {
				Spacer()
				Button("Standard herstellen") { showResetConfirm = true }
					.buttonStyle(.bordered)
			}
		}
		.task {
			guard !seeded else { return }
			await store.loadCategories()
			rows = store.categories
			seeded = true
		}
		.onDisappear {
			colorSaves.values.forEach { $0.cancel() }
		}
		.confirmationDialog(
			"Standard-Kategorien wiederherstellen?",
			isPresented: $showResetConfirm,
			titleVisibility: .visible
		) {
			Button("Standard herstellen") { restoreDefaults() }
		} message: {
			Text("Alle eigenen Kategorien werden durch Hoch, Schule und Niedrig ersetzt.")
		}
	}

	// MARK: Zeile

	/// Eine Kategorie: Farbe, Name (oder Umbenennen-Formular), Löschen.
	@ViewBuilder
	private func categoryRow(_ cat: TaskCategory) -> some View {
		VStack(alignment: .leading, spacing: DS.Space.xs) {
			HStack(spacing: DS.Space.sm) {
				ColorPicker("", selection: colorBinding(for: cat))
					.labelsHidden()
				if renameDrafts[cat.name] != nil {
					TextField("Neuer Name", text: Binding(
						get: { renameDrafts[cat.name] ?? "" },
						set: { renameDrafts[cat.name] = $0 }
					))
					.frame(maxWidth: 260)
					.onSubmit { commitRename(of: cat) }
					Button("Umbenennen") { commitRename(of: cat) }
						.buttonStyle(.bordered)
					Button("Abbrechen") {
						renameDrafts[cat.name] = nil
						rowErrors[cat.name] = nil
					}
					.buttonStyle(.borderless)
				} else {
					Text(cat.name)
						.font(DS.Typo.rowTitle)
						.foregroundStyle(DS.textPrimary)
					Spacer(minLength: DS.Space.sm)
					Button("Umbenennen") { renameDrafts[cat.name] = cat.name }
						.buttonStyle(.bordered)
					Button {
						deleteCategory(cat)
					} label: {
						Image(systemName: "trash")
					}
					.buttonStyle(.borderless)
					.foregroundStyle(DS.danger)
					.help("Kategorie löschen")
				}
			}
			if let err = rowErrors[cat.name] {
				Text(err).font(.caption).foregroundStyle(DS.danger)
			}
		}
		.padding(DS.Space.sm)
		.background(
			RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
				.fill(DS.fillSubtle)
		)
	}

	// MARK: Aktionen

	/// Farbbindung mit entprelltem Auto-Speichern (~400 ms nach der letzten Änderung).
	private func colorBinding(for cat: TaskCategory) -> Binding<Color> {
		Binding(
			get: {
				guard let row = rows.first(where: { $0.name == cat.name }) else { return .gray }
				return dsColor(hex: row.color) ?? .gray
			},
			set: { newValue in
				guard let i = rows.firstIndex(where: { $0.name == cat.name }) else { return }
				let hex = hexString(from: newValue) ?? rows[i].color
				rows[i] = TaskCategory(name: rows[i].name, color: hex)
				scheduleColorSave()
			}
		)
	}

	private func scheduleColorSave() {
		colorSaves["_"]?.cancel()
		colorSaves["_"] = Task {
			do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
			guard !Task.isCancelled else { return }
			if let err = await store.saveCategories(rows) { saveError = err }
			colorSaves["_"] = nil
		}
	}

	private func commitRename(of cat: TaskCategory) {
		guard let draft = renameDrafts[cat.name] else { return }
		guard let normalized = TaskCategories.normalize(draft) else {
			rowErrors[cat.name] = "Ungültiger Kategoriename (1–40 Zeichen, ohne Komma/Semikolon)."
			return
		}
		if rows.contains(where: {
			$0.name.lowercased() == normalized.lowercased() && $0.name != cat.name
		}) {
			rowErrors[cat.name] = "Diese Kategorie gibt es schon."
			return
		}
		guard let i = rows.firstIndex(where: { $0.name == cat.name }) else { return }
		let color = rows[i].color
		rows[i] = TaskCategory(name: normalized, color: color)
		renameDrafts[cat.name] = nil
		rowErrors[cat.name] = nil
		saveAll()
	}

	private func addCategory() {
		guard let normalized = TaskCategories.normalize(newName) else {
			addError = "Ungültiger Kategoriename (1–40 Zeichen, ohne Komma/Semikolon)."
			return
		}
		if rows.contains(where: { $0.name.lowercased() == normalized.lowercased() }) {
			addError = "Diese Kategorie gibt es schon."
			return
		}
		guard let hex = hexString(from: newColor) else { return }
		rows.append(TaskCategory(name: normalized, color: hex))
		newName = ""
		addError = nil
		saveAll()
	}

	/// Kategorie löschen; bestehende Aufgaben behalten ihren Kategorienamen (ohne Farbe).
	private func deleteCategory(_ cat: TaskCategory) {
		colorSaves.values.forEach { $0.cancel() }
		rows.removeAll { $0.name == cat.name }
		renameDrafts[cat.name] = nil
		rowErrors[cat.name] = nil
		saveAll()
	}

	private func restoreDefaults() {
		colorSaves.values.forEach { $0.cancel() }
		rows = TaskCategories.defaults
		renameDrafts = [:]
		rowErrors = [:]
		saveAll()
	}

	private func saveAll() {
		Task {
			if let err = await store.saveCategories(rows) { saveError = err }
		}
	}
}

// MARK: – API-Token

/// API-Token für externe Programme (MCP): erzeugen, einmalig anzeigen, ablehnen.
private struct ApiTokenSection: View {
	@Environment(AppStore.self) private var store

	@State private var busy = false
	@State private var actionError: String?
	@State private var showGenerateConfirm = false
	@State private var showRevokeConfirm = false
	@State private var copiedFlash = false

	var body: some View {
		SettingsSectionCard(title: "API-Token (für externe Zugriffe)") {
			Text("Mit diesem Token können externe Programme — z. B. ein Assistenz-/Automatisierungs-Tool über den mitgelieferten MCP-Server — auf deine Termine und Aufgaben zugreifen. Der Token funktioniert wie ein Passwort (Header „Authorization: Bearer <token>“).")
				.font(.callout)
				.foregroundStyle(DS.textSecondary)

			if let info = store.apiToken {
				if info.hasToken {
					Text(statusLine(info))
						.font(.caption)
						.foregroundStyle(DS.textSecondary)
				} else {
					Text("Noch kein Token erstellt.")
						.font(.caption)
						.foregroundStyle(DS.textSecondary)
				}
			}

			// Klartext gibt es nur einmal — direkt nach dem Erzeugen.
			if let token = store.newApiToken {
				VStack(alignment: .leading, spacing: DS.Space.sm) {
					Text("Neuer Token — wird nur einmal angezeigt, jetzt kopieren:")
						.font(.caption)
						.foregroundStyle(DS.textSecondary)
					HStack(alignment: .top, spacing: DS.Space.sm) {
						Text(token)
							.font(.system(.caption, design: .monospaced))
							.textSelection(.enabled)
							.frame(maxWidth: .infinity, alignment: .leading)
							.padding(DS.Space.sm)
							.background(
								RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
									.fill(DS.fillSubtle)
							)
						VStack(spacing: DS.Space.xs) {
							Button("Kopieren") { copyToken(token) }
								.buttonStyle(.bordered)
							if copiedFlash {
								Text("Kopiert.").font(.caption).foregroundStyle(DS.success)
							}
						}
					}
				}
				.padding(DS.Space.md)
				.background(
					RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
						.fill(DS.success.opacity(0.08))
				)
				.overlay(
					RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
						.strokeBorder(DS.success.opacity(0.3), lineWidth: 1)
				)
			}

			if let err = actionError {
				ErrorBanner(message: err)
			}

			HStack(spacing: DS.Space.sm) {
				Button {
					if store.apiToken?.hasToken == true {
						showGenerateConfirm = true
					} else {
						generateToken()
					}
				} label: {
					generateLabel
				}
				.disabled(busy)
				if store.apiToken?.hasToken == true {
					Button("Token ablehnen", role: .destructive) { showRevokeConfirm = true }
						.buttonStyle(.bordered)
						.disabled(busy)
				}
			}
		}
		.task {
			if store.apiToken == nil { await store.loadApiToken() }
		}
		.confirmationDialog(
			"Den aktuellen Token ersetzen? Er ist danach ungültig.",
			isPresented: $showGenerateConfirm,
			titleVisibility: .visible
		) {
			Button("Neuen Token erzeugen") { generateToken() }
		}
		.confirmationDialog(
			"API-Token ablehnen? Externe Tools verlieren sofort den Zugriff.",
			isPresented: $showRevokeConfirm,
			titleVisibility: .visible
		) {
			Button("Token ablehnen", role: .destructive) { revokeToken() }
		}
	}

	@ViewBuilder
	private var generateLabel: some View {
		if busy {
			HStack(spacing: DS.Space.xs) {
				ProgressView().controlSize(.small)
				Text("Arbeite…")
			}
		} else {
			Text(store.apiToken?.hasToken == true ? "Neuen Token erzeugen" : "Token erzeugen")
		}
	}

	/// „Token erstellt am 12.03.2026 · zuletzt genutzt 09.05.2026“.
	private func statusLine(_ info: ApiTokenView) -> String {
		var line = "Token erstellt am \(Self.date(info.createdAt) ?? "–")"
		if let last = info.lastUsedAt {
			line += " · zuletzt genutzt \(Self.date(last))"
		} else {
			line += " · noch nie genutzt"
		}
		return line
	}

	private static func date(_ epochMs: Int?) -> String? {
		guard let epochMs else { return nil }
		let f = DateFormatter()
		f.locale = Locale(identifier: "de_DE")
		f.dateStyle = .medium
		return f.string(from: Date(timeIntervalSince1970: Double(epochMs) / 1000))
	}

	private func copyToken(_ token: String) {
		NSPasteboard.general.clearContents()
		NSPasteboard.general.setString(token, forType: .string)
		copiedFlash = true
		Task {
			try? await Task.sleep(for: .seconds(2))
			copiedFlash = false
		}
	}

	private func generateToken() {
		guard !busy else { return }
		busy = true
		actionError = nil
		Task {
			let err = await store.generateApiToken()
			busy = false
			if let err { actionError = err }
		}
	}

	private func revokeToken() {
		guard !busy else { return }
		busy = true
		actionError = nil
		Task {
			let err = await store.revokeApiToken()
			busy = false
			if let err { actionError = err }
		}
	}
}

// MARK: – Hilfsfunktionen

private extension String {
	/// Whitespace am Anfang/Ende entfernt (Kurzform für Formulareingaben).
	var trimmed: String {
		trimmingCharacters(in: .whitespacesAndNewlines)
	}
}

/// Grün/rotes Ergebnis-Banner (Test/Versand) mit optionaler Detailzeile.
private struct ResultBanner: View {
	let ok: Bool
	let title: String
	var detail: String?

	var body: some View {
		VStack(alignment: .leading, spacing: 2) {
			Label(title, systemImage: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
				.font(.callout.weight(.medium))
			if let detail, !detail.isEmpty {
				Text(detail)
					.font(.caption)
					.textSelection(.enabled)
			}
		}
		.foregroundStyle(ok ? DS.success : DS.danger)
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(DS.Space.sm)
		.background(
			RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
				.fill((ok ? DS.success : DS.danger).opacity(0.10))
		)
		.accessibilityElement(children: .combine)
	}
}

/// Color als Hex-String (#rrggbb) für die Kategorie-Farben; nil wenn nicht konvertierbar.
private func hexString(from color: Color) -> String? {
	guard let ns = NSColor(color).usingColorSpace(.sRGB) else { return nil }
	let r = Int((ns.redComponent * 255).rounded())
	let g = Int((ns.greenComponent * 255).rounded())
	let b = Int((ns.blueComponent * 255).rounded())
	return String(format: "#%02x%02x%02x", r, g, b)
}

/// Prüft das Zeitformat HH:MM (0–23 Uhr, 0–59 Minuten).
private func isValidTime(_ s: String) -> Bool {
	let parts = s.split(separator: ":", omittingEmptySubsequences: false)
	guard parts.count == 2, parts[0].count == 2, parts[1].count == 2,
	      let hour = Int(parts[0]), let minute = Int(parts[1]) else { return false }
	return (0...23).contains(hour) && (0...59).contains(minute)
}

/// Hex-Farbe (#RRGGBB oder RRGGBB) als Color, nil bei ungültigem Wert.
private func dsColor(hex: String) -> Color? {
	var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
	if s.hasPrefix("#") { s.removeFirst() }
	guard s.count == 6, let value = UInt64(s, radix: 16) else { return nil }
	return Color(nsColor: NSColor(
		srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
		green: CGFloat((value >> 8) & 0xFF) / 255,
		blue: CGFloat(value & 0xFF) / 255,
		alpha: 1))
}

/// Feste sRGB-Farbe (Design-Vorschau – folgt bewusst nicht der aktuellen Erscheinung).
private func staticRGB(_ hex: UInt64) -> Color {
	Color(nsColor: NSColor(
		srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
		green: CGFloat((hex >> 8) & 0xFF) / 255,
		blue: CGFloat(hex & 0xFF) / 255,
		alpha: 1))
}

/// Einfacher Fluss-Layout für Chip-Listen (Layout-Protokoll, macOS 13+).
private struct FlowLayout: Layout {
	var spacing: CGFloat = DS.Space.sm

	func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
		let width = proposal.width ?? .infinity
		var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
		for sub in subviews {
			let size = sub.sizeThatFits(.unspecified)
			if x > 0 && x + size.width > width {
				x = 0
				y += rowHeight + spacing
				rowHeight = 0
			}
			x += size.width + spacing
			rowHeight = max(rowHeight, size.height)
		}
		return CGSize(width: width, height: y + rowHeight)
	}

	func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
		var x: CGFloat = bounds.minX, y: CGFloat = bounds.minY, rowHeight: CGFloat = 0
		for sub in subviews {
			let size = sub.sizeThatFits(.unspecified)
			if x > bounds.minX && x + size.width > bounds.maxX {
				x = bounds.minX
				y += rowHeight + spacing
				rowHeight = 0
			}
			sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
			x += size.width + spacing
			rowHeight = max(rowHeight, size.height)
		}
	}
}
