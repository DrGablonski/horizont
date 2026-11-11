import SwiftUI

/// Einstellungen als klassische iPhone-Einstellungs-Liste: jede Gruppe führt per
/// NavigationLink auf eine eigene Unterseite (Konto, CalDAV-Verbindungen, Kalender,
/// Kategorien, Benachrichtigungen, Design). Alle Formulare nutzen `.formStyle(.grouped)`,
/// Bearbeitung erfolgt in Sheets (`.presentationDetents([.medium, .large])`),
/// Bestätigungen als `.alert`/`.confirmationDialog`.
struct SettingsView: View {
	@Environment(AppStore.self) private var store

	private var appVersion: String {
		let info = Bundle.main.infoDictionary
		let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
		let build = info?["CFBundleVersion"] as? String ?? "1"
		return "\(short) (\(build))"
	}

	var body: some View {
		List {
			Section {
				NavigationLink {
					AccountPage()
				} label: {
					SettingsRowIcon(systemImage: "person.crop.circle", color: .gray)
					Text("Konto")
				}
			}

			Section("CalDAV") {
				NavigationLink {
					ConnectionsPage()
				} label: {
					SettingsRowIcon(systemImage: "cable.connector", color: .blue)
					Text("Verbindungen")
					Spacer(minLength: DS.Space.sm)
					Text("\(store.connections.count)")
						.font(DS.Typo.meta)
						.foregroundStyle(DS.textTertiary)
				}
				NavigationLink {
					CalendarsPage()
				} label: {
					SettingsRowIcon(systemImage: "calendar", color: .red)
					Text("Kalender")
					Spacer(minLength: DS.Space.sm)
					Text("\(store.calendars.filter { !$0.hidden }.count)")
						.font(DS.Typo.meta)
						.foregroundStyle(DS.textTertiary)
				}
				NavigationLink {
					CategoriesPage()
				} label: {
					SettingsRowIcon(systemImage: "tag", color: .orange)
					Text("Kategorien")
					Spacer(minLength: DS.Space.sm)
					Text("\(store.categories.count)")
						.font(DS.Typo.meta)
						.foregroundStyle(DS.textTertiary)
				}
			}

			Section("App") {
				NavigationLink {
					NotifyPage()
				} label: {
					SettingsRowIcon(systemImage: "bell", color: .yellow)
					Text("Benachrichtigungen")
				}
				NavigationLink {
					AppearancePage()
				} label: {
					SettingsRowIcon(systemImage: "paintbrush", color: .mint)
					Text("Design")
				}
			}

			Section {
				LabeledContent("Version", value: appVersion)
			}
		}
		.navigationTitle("Einstellungen")
	}
}

// MARK: – Zeilen-Icon (iPhone-Einstellungen-Look)

/// Farbige Icon-Kachel wie in den iOS-Einstellungen.
private struct SettingsRowIcon: View {
	let systemImage: String
	let color: Color

	var body: some View {
		RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
			.fill(color)
			.frame(width: 28, height: 28)
			.overlay(
				Image(systemName: systemImage)
					.font(.system(size: 15, weight: .semibold))
					.foregroundStyle(.white)
			)
			.padding(.trailing, DS.Space.xs)
	}
}

// MARK: – Erfolgsmeldung

/// Grüner Hinweistext für gelungene Aktionen (Speichern, Testversand …).
private struct SuccessFlash: View {
	let text: String

	var body: some View {
		Label(text, systemImage: "checkmark.circle.fill")
			.font(.callout)
			.foregroundStyle(DS.success)
			.frame(maxWidth: .infinity, alignment: .leading)
	}
}

// MARK: – Konto

/// Konto, Server-Adresse, Version und Abmelden.
private struct AccountPage: View {
	@Environment(AuthStore.self) private var auth

	@State private var serverDraft = ""
	@State private var savedFlash = false
	@State private var confirmLogout = false

	/// Speichern lohnt nur, wenn die URL wirklich geändert wurde.
	private var canSave: Bool {
		let trimmed = trimmedDraft
		return !trimmed.isEmpty && trimmed != auth.serverURL
	}

	private var trimmedDraft: String {
		serverDraft.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	private var appVersion: String {
		let info = Bundle.main.infoDictionary
		let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
		let build = info?["CFBundleVersion"] as? String ?? "1"
		return "\(short) (\(build))"
	}

	var body: some View {
		Form {
			Section {
				HStack(spacing: DS.Space.md) {
					avatar
					VStack(alignment: .leading, spacing: DS.Space.xxs) {
						Text(auth.user?.username ?? "–")
							.font(.body)
							.foregroundStyle(DS.textPrimary)
						Text("Angemeldet als")
							.font(DS.Typo.meta)
							.foregroundStyle(DS.textSecondary)
					}
					Spacer(minLength: 0)
				}
				.padding(.vertical, DS.Space.xs)
			}

			Section {
				TextField("Server-URL", text: $serverDraft)
					.autocorrectionDisabled()
					.keyboardType(.URL)
					.textInputAutocapitalization(.never)
			} header: {
				Text("Server")
			} footer: {
				Text("Nach dem Speichern abmelden und wieder anmelden, damit die App neue Daten lädt.")
			}

			Section {
				if savedFlash {
					SuccessFlash(text: "Server-URL gespeichert.")
				}
				Button("Speichern") {
					auth.serverURL = trimmedDraft
					savedFlash = true
					Task {
						try? await Task.sleep(for: .seconds(2))
						savedFlash = false
					}
				}
				.disabled(!canSave)
			}

			Section {
				LabeledContent("Version", value: appVersion)
			}

			Section {
				Button("Abmelden", role: .destructive) {
					confirmLogout = true
				}
			}
		}
		.formStyle(.grouped)
		.navigationTitle("Konto")
		.navigationBarTitleDisplayMode(.inline)
		.onAppear { serverDraft = auth.serverURL }
		.confirmationDialog(
			"Wirklich abmelden?",
			isPresented: $confirmLogout					) {
			Button("Abmelden", role: .destructive) {
				Task { await auth.logout() }
			}
			Button("Abbrechen", role: .cancel) {}
		} message: {
			Text("Die Sitzung wird beendet; Zugangsdaten löscht die App aus der Geräte-Schlüsselbund.")
		}
	}

	/// Kreis mit Initiale des Benutzernamens.
	private var avatar: some View {
		let initial = String((auth.user?.username ?? "?").prefix(1)).uppercased()
		return ZStack {
			Circle()
				.fill(DS.tintSoft)
			Text(initial)
				.font(.headline)
				.foregroundStyle(DS.accent)
		}
		.frame(width: 40, height: 40)
	}
}

// MARK: – CalDAV-Verbindungen

/// Verbindungsliste mit Testen, Hauptverbindung setzen, Bearbeiten und Löschen;
/// darunter die Anbieter-Vorlagen als Anlege-Vorlage.
private struct ConnectionsPage: View {
	@Environment(AppStore.self) private var store
	@Environment(AuthStore.self) private var auth

	@State private var showAdd = false
	/// Anbieter-Vorlage, mit der das Anlege-Sheet vorausgefüllt wird.
	@State private var addPreset: ProviderPreset?
	@State private var editTarget: ConnectionView?
	@State private var deleteTarget: ConnectionView?
	@State private var primaryTarget: ConnectionView?

	@State private var testing: Set<String> = []
	@State private var results: [String: TestResult] = [:]
	@State private var errors: [String: String] = [:]

	var body: some View {
		List {
			Section {
				if store.connections.isEmpty {
					Text("Noch keine Verbindungen – oben über „+“ eine CalDAV-Verbindung anlegen.")
						.font(.callout)
						.foregroundStyle(DS.textSecondary)
				} else {
					ForEach(store.connections) { conn in
						connectionBlock(conn)
					}
				}
			} header: {
				Text("CalDAV-Verbindungen")
			}

			if !store.providerPresets.isEmpty {
				Section {
					ForEach(store.providerPresets, id: \.id) { preset in
						presetRow(preset)
					}
				} header: {
					Text("Anbieter-Vorlagen")
				} footer: {
					Text("Tippen auf eine Vorlage öffnet das Anlege-Formular mit vorausgefüllter URL.")
				}
			}
		}
		.navigationTitle("CalDAV-Verbindungen")
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			ToolbarItem(placement: .primaryAction) {
				Button {
					addPreset = nil
					showAdd = true
				} label: {
					Image(systemName: "plus")
				}
			}
		}
		.refreshable { await reload() }
		.task { await reload() }
		.sheet(isPresented: $showAdd) {
			ConnectionEditSheet(preset: addPreset)
		}
		.sheet(item: $editTarget) { conn in
			ConnectionEditSheet(connection: conn)
		}
		.alert(
			"Hauptverbindung setzen?",
			isPresented: Binding(
				get: { primaryTarget != nil },
				set: { if !$0 { primaryTarget = nil } }
			)					) {
			if let conn = primaryTarget {
				Button("Als Hauptverbindung setzen") { setPrimary(conn) }
			}
			Button("Abbrechen", role: .cancel) {}
		} message: {
			if let conn = primaryTarget {
				Text("„\(conn.name)“ wird Hauptverbindung – für neue Einträge und Workflows. Die bisherige wird Zusatzverbindung.")
			}
		}
		.alert(
			"Verbindung löschen?",
			isPresented: Binding(
				get: { deleteTarget != nil },
				set: { if !$0 { deleteTarget = nil } }
			)					) {
			if let conn = deleteTarget {
				Button("Löschen", role: .destructive) { delete(conn) }
			}
			Button("Abbrechen", role: .cancel) {}
		} message: {
			if let conn = deleteTarget {
				Text("„\(conn.name)“ wird aus den Server-Einstellungen entfernt. Kalender und Einträge bleiben auf dem CalDAV-Server.")
			}
		}
	}

	/// Verbindung anzeigen/testen plus Rollen- und Bearbeitungsmenü; Fehlerbanner darunter.
	@ViewBuilder
	private func connectionBlock(_ conn: ConnectionView) -> some View {
		VStack(alignment: .leading, spacing: DS.Space.xs) {
			HStack(spacing: DS.Space.sm) {
				VStack(alignment: .leading, spacing: 2) {
					HStack(spacing: DS.Space.xs) {
						Text(conn.name)
							.font(DS.Typo.rowTitle)
							.foregroundStyle(DS.textPrimary)
							.lineLimit(1)
						if conn.role == "primary" {
							Chip(text: "Hauptverbindung", color: DS.accent)
						}
					}
					Text(conn.url)
						.font(DS.Typo.meta)
						.foregroundStyle(DS.textSecondary)
						.lineLimit(1)
						.truncationMode(.middle)
					HStack(spacing: DS.Space.xs) {
						Chip(text: conn.provider)
						Chip(text: conn.username, systemImage: "person.fill")
						if conn.hasPassword {
							Chip(text: "Passwort gesetzt", color: DS.success, systemImage: "lock.fill")
						}
					}
					if let res = results[conn.id], res.ok {
						Chip(text: "Verbunden, \(res.calendars?.count ?? 0) Kalender",
						     color: DS.success, systemImage: "checkmark.circle.fill")
					}
				}
				Spacer(minLength: DS.Space.xs)
				testButton(conn)
				overflowMenu(conn)
			}
			if let err = errors[conn.id] {
				ErrorBanner(message: err, retry: { test(conn) })
			}
		}
		.contentShape(Rectangle())
	}

	private func testButton(_ conn: ConnectionView) -> some View {
		Button {
			test(conn)
		} label: {
			if testing.contains(conn.id) {
				ProgressView().controlSize(.small)
			} else {
				Image(systemName: "bolt")
			}
		}
		.buttonStyle(.bordered)
		.disabled(testing.contains(conn.id))
		.help("Verbindung testen")
		.accessibilityLabel("Verbindung testen")
	}

	private func overflowMenu(_ conn: ConnectionView) -> some View {
		Menu {
			if conn.role != "primary" {
				Button("Als Hauptverbindung setzen") { primaryTarget = conn }
			}
			Button("Bearbeiten") { editTarget = conn }
			Button("Löschen", role: .destructive) { deleteTarget = conn }
		} label: {
			Image(systemName: "ellipsis.circle")
		}
	}

	/// Anbieter-Vorlage: antippen → Anlege-Formular mit vorausgefüllter URL.
	@ViewBuilder
	private func presetRow(_ preset: ProviderPreset) -> some View {
		Button {
			addPreset = preset
			showAdd = true
		} label: {
			VStack(alignment: .leading, spacing: 2) {
				HStack(spacing: DS.Space.xs) {
					Text(preset.label)
						.font(.callout.weight(.semibold))
						.foregroundStyle(DS.textPrimary)
					if !preset.supportsCalendarCreation {
						Chip(text: "Kalender-Anlage oft abgelehnt", color: DS.danger)
					}
					Spacer(minLength: DS.Space.sm)
					Image(systemName: "plus.circle")
						.foregroundStyle(DS.textSecondary)
				}
				Text(preset.url)
					.font(DS.Typo.meta)
					.foregroundStyle(DS.textSecondary)
					.lineLimit(1)
					.truncationMode(.middle)
				Text(preset.hint)
					.font(.caption)
					.foregroundStyle(DS.textTertiary)
			}
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
	}

	// MARK: Aktionen

	private func reload() async {
		await store.loadConnections()
		if store.providerPresets.isEmpty { await store.loadProviderPresets() }
	}

	/// Verbindung testen; Erfolg inline als Chip, Fehler als Banner unter der Karte.
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

	/// Rolle wechseln: diese Verbindung wird Hauptverbindung.
	private func setPrimary(_ conn: ConnectionView) {
		primaryTarget = nil
		errors.removeValue(forKey: conn.id)
		Task {
			let err = await store.setPrimaryConnection(conn.id)
			if let err { errors[conn.id] = err }
		}
	}

	private func delete(_ conn: ConnectionView) {
		deleteTarget = nil
		errors.removeValue(forKey: conn.id)
		Task {
			guard let client = auth.client else { return }
			do {
				_ = try await client.deleteConnection(id: conn.id)
				await store.loadConnections()
				await store.loadCalendars()
			} catch {
				errors[conn.id] = error.localizedDescription
			}
		}
	}
}

/// Anlegen/Bearbeiten einer CalDAV-Verbindung (Anbieter-Vorlage vorauswählbar),
/// inklusive Test ungespeicherter Formularwerte.
private struct ConnectionEditSheet: View {
	/// nil = neue Verbindung anlegen.
	let connection: ConnectionView?
	/// Optional: Vorlage, mit der das Formular vorausgefüllt wird.
	let preset: ProviderPreset?

	@Environment(AppStore.self) private var store
	@Environment(AuthStore.self) private var auth
	@Environment(\.dismiss) private var dismiss

	@State private var providerId = ""
	@State private var name = ""
	@State private var url = ""
	@State private var username = ""
	@State private var password = ""
	@State private var error: String?
	@State private var testing = false
	@State private var testResult: TestResult?
	@State private var saving = false

	private var isEdit: Bool { connection != nil }

	/// Benutzerfeld der gewählten Vorlage (falls die Vorlage passend gewählt wurde).
	private var selectedPreset: ProviderPreset? {
		store.providerPresets.first { $0.id == providerId }
	}

	private var canSave: Bool {
		!name.trimmed.isEmpty && !url.trimmed.isEmpty && !username.trimmed.isEmpty
			&& (isEdit || !password.trimmed.isEmpty)
	}

	init(connection: ConnectionView? = nil, preset: ProviderPreset? = nil) {
		self.connection = connection
		self.preset = preset
	}

	var body: some View {
		NavigationStack {
			Form {
				Section {
					Picker("Anbieter", selection: $providerId) {
						Text("Eigene …").tag("")
						ForEach(store.providerPresets, id: \.id) { p in
							Text(p.label).tag(p.id)
						}
					}
					if let p = selectedPreset {
						Text(p.hint)
							.font(.caption)
							.foregroundStyle(DS.textTertiary)
					}
				} header: {
					Text("Anbieter")
				}

				Section {
					TextField("Name", text: $name)
						.textInputAutocapitalization(.never)
					TextField("CalDAV-URL", text: $url)
						.autocorrectionDisabled()
						.keyboardType(.URL)
						.textInputAutocapitalization(.never)
					TextField(selectedPreset?.usernameLabel ?? "Benutzername", text: $username)
						.autocorrectionDisabled()
						.textInputAutocapitalization(.never)
					SecureField(isEdit ? "Passwort (leer = behalten)" : "Passwort/App-Schlüssel",
					            text: $password)
				} header: {
					Text("Zugang")
				} footer: {
					if !isEdit {
						Text("Tipp: Bei iCloud und Google brauchst du einen App-Schlüssel "
							+ "(Appspezifisches Passwort), nicht das normale Konto-Passwort.")
					}
				}

				Section {
					Button {
						testDraft()
					} label: {
						if testing {
							HStack(spacing: DS.Space.xs) {
								ProgressView().controlSize(.small)
								Text("Teste …")
							}
						} else {
							Label("Erst testen", systemImage: "bolt")
						}
					}
					.disabled(testing || url.trimmed.isEmpty || username.trimmed.isEmpty
					          || (!isEdit && password.trimmed.isEmpty))

					if let res = testResult {
						if res.ok {
							SuccessFlash(text: "Verbunden – \(res.calendars?.count ?? 0) Kalender"
								+ (res.eventCount.map { ", \($0) Einträge" } ?? "") + ".")
						} else {
							ErrorBanner(message: res.error ?? "Verbindung fehlgeschlagen.")
						}
					}
					if let error {
						ErrorBanner(message: error)
					}
				} header: {
					Text("Verbindungstest")
				}
			}
			.formStyle(.grouped)
			.navigationTitle(isEdit ? "Verbindung bearbeiten" : "Neue Verbindung")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("Abbrechen") { dismiss() }
				}
				ToolbarItem(placement: .confirmationAction) {
					if saving {
						ProgressView().controlSize(.small)
					} else {
						Button(isEdit ? "Speichern" : "Anlegen") { save() }
							.disabled(!canSave)
					}
				}
			}
		}
		.presentationDetents([.medium, .large])
		.onAppear {
			if store.providerPresets.isEmpty {
				Task { await store.loadProviderPresets() }
			}
			if let conn = connection {
				providerId = conn.provider
				name = conn.name
				url = conn.url
				username = conn.username
			} else if let preset {
				providerId = preset.id
				url = preset.url
				name = preset.label
			}
		}
		.onChange(of: providerId) { _, newId in
			// Nur neue Verbindungen vorausfüllen; Bestandsdaten nicht überschreiben.
			guard connection == nil,
			      let p = store.providerPresets.first(where: { $0.id == newId }) else { return }
			url = p.url
		}
	}

	/// Testet die Formularwerte, ohne zu speichern.
	private func testDraft() {
		guard !testing, let client = auth.client else { return }
		testing = true
		error = nil
		testResult = nil
		let u = url.trimmed
		let user = username.trimmed
		let pass = password
		Task {
			let res = try? await client.testConnection(url: u, username: user, password: pass)
			testing = false
			if let res {
				testResult = res
			} else {
				error = "Test fehlgeschlagen."
			}
		}
	}

	private func save() {
		guard canSave, !saving, let client = auth.client else { return }
		saving = true
		error = nil
		let n = name.trimmed
		let u = url.trimmed
		let user = username.trimmed
		let pass = password
		Task {
			do {
				if let conn = connection {
					_ = try await client.updateConnection(
						id: conn.id, name: n, url: u, username: user, password: pass)
				} else {
					_ = try await client.createConnection(
						name: n, url: u, username: user, password: pass)
				}
				await store.loadConnections()
				await store.loadCalendars()
				dismiss()
			} catch {
				saving = false
				self.error = error.localizedDescription
			}
		}
	}
}

// MARK: – Kalender

/// Navigationswert zu einem Kalender (id-gekapselt, damit keine String-Kollision).
private struct CalendarRoute: Hashable {
	let id: String
}

/// Kalenderliste, gruppiert pro Verbindung; each Zeile öffnet die Kalender-Verwaltung.
private struct CalendarsPage: View {
	@Environment(AppStore.self) private var store

	/// Kalender einer Verbindung, in Server-Reihenfolge.
	private struct ConnectionGroup: Identifiable {
		let connectionId: String
		let title: String
		let role: String
		var calendars: [CalendarView]
		var id: String { connectionId }
	}

	@State private var showCreate = false

	/// Gruppiert die Kalender beim ersten Auftreten ihrer Verbindung.
	private var groups: [ConnectionGroup] {
		var result: [ConnectionGroup] = []
		for cal in store.calendars {
			if let i = result.firstIndex(where: { $0.connectionId == cal.connectionId }) {
				result[i].calendars.append(cal)
			} else {
				result.append(ConnectionGroup(connectionId: cal.connectionId,
				                              title: cal.connectionName ?? cal.connectionId,
				                              role: cal.role, calendars: [cal]))
			}
		}
		return result
	}

	var body: some View {
		List {
			if let err = store.calendarsError {
				ErrorBanner(message: err, retry: { Task { await store.loadCalendars() } })
			}

			ForEach(groups) { group in
				Section {
					ForEach(group.calendars, id: \.id) { cal in
						NavigationLink(value: CalendarRoute(id: cal.id)) {
							calendarRow(cal)
						}
					}
				} header: {
					HStack(spacing: DS.Space.xs) {
						Text(group.title)
						Chip(text: group.role == "primary" ? "Hauptverbindung" : "Zusatz",
						     color: group.role == "primary" ? DS.accent : DS.textSecondary)
					}
				}
			}

			Section {
				Button {
					showCreate = true
				} label: {
					Label("Neuer Kalender", systemImage: "plus")
				}
			}
		}
		.navigationTitle("Kalender")
		.navigationBarTitleDisplayMode(.inline)
		.navigationDestination(for: CalendarRoute.self) { route in
			CalendarSettingsPage(calendarId: route.id)
		}
		.refreshable { await store.loadCalendars() }
		.task {
			if !store.calendarsLoaded { await store.loadCalendars() }
			if store.connections.isEmpty { await store.loadConnections() }
		}
		.sheet(isPresented: $showCreate) {
			CreateCalendarSheet()
		}
		.overlay {
			if store.calendars.isEmpty && store.calendarsLoaded && store.calendarsError == nil {
				EmptyStateView(
					title: "Keine Kalender gefunden",
					systemImage: "calendar",
					description: "Verbindungen prüfen oder oben „Neuer Kalender“ nutzen.")
			}
		}
	}

	/// Zeile pro Kalender: Farbpunkt, Name, Badges; ausgeblendete abgeblendet.
	@ViewBuilder
	private func calendarRow(_ cal: CalendarView) -> some View {
		HStack(spacing: DS.Space.sm) {
			Circle()
				.fill(Color(hex: cal.color))
				.frame(width: 10, height: 10)
			VStack(alignment: .leading, spacing: 2) {
				Text(cal.name)
					.font(DS.Typo.rowTitle)
					.foregroundStyle(cal.hidden ? DS.textTertiary : DS.textPrimary)
					.lineLimit(1)
				HStack(spacing: DS.Space.xs) {
					if cal.isDefault {
						Chip(text: "Standard", color: DS.success, systemImage: "star.fill")
					}
					if !cal.writable {
						Chip(text: "schreibgeschützt", color: DS.textSecondary, systemImage: "lock.fill")
					}
					if cal.hidden {
						Chip(text: "ausgeblendet", color: DS.textTertiary, systemImage: "eye.slash")
					}
				}
			}
			Spacer(minLength: DS.Space.xs)
		}
		.padding(.vertical, DS.Space.xxs)
	}
}

/// Verwaltung eines einzelnen Kalenders: Sichtbarkeit, Schreibschutz, Standard,
/// Farbe, Umbenennen und Löschen (mit Namensbestätigung).
private struct CalendarSettingsPage: View {
	let calendarId: String

	@Environment(AppStore.self) private var store

	private enum Sheet: String, Identifiable {
		case rename, color, delete
		var id: String { rawValue }
	}

	@State private var sheet: Sheet?
	@State private var confirmDefault = false
	@State private var error: String?

	/// Der Kalender wird live im Store gesucht (@Observable → reaktiv).
	private var calendar: CalendarView? {
		store.calendars.first { $0.id == calendarId }
	}

	var body: some View {
		Group {
			if let cal = calendar {
				content(cal)
			} else {
				EmptyStateView(
					title: "Kalender nicht gefunden",
					systemImage: "calendar.badge.exclamationmark",
					description: "Er wurde möglicherweise gelöscht oder neu geladen.")
			}
		}
		.navigationTitle(calendar?.name ?? "Kalender")
		.navigationBarTitleDisplayMode(.inline)
		.task {
			if !store.calendarsLoaded { await store.loadCalendars() }
		}
		.sheet(item: $sheet) { which in
			switch which {
			case .rename: RenameCalendarSheet(calendarId: calendarId)
			case .color: CalendarColorSheet(calendarId: calendarId)
			case .delete: DeleteCalendarSheet(calendarId: calendarId)
			}
		}
		.alert(
			"Als Standard setzen?",
			isPresented: $confirmDefault					) {
			Button("Als Standard setzen") {
				Task { await store.setDefaultCalendar(calendarId) }
			}
			Button("Abbrechen", role: .cancel) {}
		} message: {
			Text("Neue Einträge landen künftig in diesem Kalender; der bisherige Standard entwertet sich.")
		}
	}

	@ViewBuilder
	private func content(_ cal: CalendarView) -> some View {
		Form {
			Section("Kalender") {
				LabeledContent("Name", value: cal.name)
				if let conn = cal.connectionName {
					LabeledContent("Verbindung", value: conn)
				}
				LabeledContent(cal.writable ? "Schreibbar" : "Schreibgeschützt",
				               value: cal.writable ? "ja" : "nein")
				if !cal.supportedComponents.isEmpty {
					LabeledContent("Unterstützt", value: cal.supportedComponents.joined(separator: ", "))
				}
			}

			Section {
				Toggle("Sichtbar", isOn: Binding(
					get: { !cal.hidden },
					set: { _ in Task { await store.toggleCalendarVisibility(cal.id) } }))
				Toggle("Beschreibbar", isOn: Binding(
					get: { cal.writable && !cal.writeDisabled },
					set: { newValue in
						Task { await store.updateCalendarEdit(cal.id, patch: ["writeDisabled": !newValue]) }
					}))
				.disabled(!cal.writable)

				if !cal.isDefault {
					Button("Als Standard setzen") { confirmDefault = true }
				}
			} header: {
				Text("Optionen")
			} footer: {
				if !cal.writable {
					Text("Dieser Kalender ist serverseitig schreibgeschützt.")
				}
			}

			Section("Anpassen") {
				Button("Umbenennen") { sheet = .rename }
				Button("Farbe ändern") { sheet = .color }
			}

			Section {
				Button("Kalender löschen", role: .destructive) { sheet = .delete }
			} footer: {
				Text("Löscht den Kalender mit allen Terminen und Aufgaben auf dem CalDAV-Server.")
			}

			if let error {
				Section {
					ErrorBanner(message: error)
				}
			}
		}
		.formStyle(.grouped)
	}
}

/// Umbenennen eines Kalenders (PATCH name; Server nutzt PROPPATCH, sonst lokale Präferenz).
private struct RenameCalendarSheet: View {
	let calendarId: String

	@Environment(AppStore.self) private var store
	@Environment(\.dismiss) private var dismiss

	@State private var name = ""
	@State private var error: String?
	@State private var saving = false

	private var canSave: Bool {
		!name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
	}

	var body: some View {
		NavigationStack {
			Form {
				Section {
					TextField("Name", text: $name)
					if let error {
						ErrorBanner(message: error)
					}
				} footer: {
					Text("Der Name wird nach Möglichkeit auf dem CalDAV-Server geändert, sonst lokal gespeichert.")
				}
			}
			.formStyle(.grouped)
			.navigationTitle("Kalender umbenennen")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("Abbrechen") { dismiss() }
				}
				ToolbarItem(placement: .confirmationAction) {
					Button("Speichern") { save() }
						.disabled(saving || !canSave)
				}
			}
		}
		.presentationDetents([.medium, .large])
		.onAppear { name = store.calendars.first(where: { $0.id == calendarId })?.name ?? "" }
	}

	private func save() {
		guard canSave, !saving else { return }
		saving = true
		error = nil
		let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
		Task {
			let failure = await store.updateCalendarEdit(calendarId, patch: ["name": trimmed])
			saving = false
			if let failure {
				error = failure
			} else {
				dismiss()
			}
		}
	}
}

/// Eigene Kalenderfarbe (wird lokal als Präferenz gespeichert, nicht am Server).
private struct CalendarColorSheet: View {
	let calendarId: String

	@Environment(AppStore.self) private var store
	@Environment(\.dismiss) private var dismiss

	@State private var color: Color = DS.accent
	@State private var error: String?
	@State private var saving = false

	var body: some View {
		NavigationStack {
			Form {
				Section {
					ColorPicker("Farbe", selection: $color, supportsOpacity: false)
					if let error {
						ErrorBanner(message: error)
					}
				} footer: {
					Text("Die Farbe gilt nur für diese App – auf dem CalDAV-Server bleibt sie unverändert.")
				}
			}
			.formStyle(.grouped)
			.navigationTitle("Kalenderfarbe")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("Abbrechen") { dismiss() }
				}
				ToolbarItem(placement: .confirmationAction) {
					Button("Übernehmen") { apply() }
						.disabled(saving)
				}
			}
		}
		.presentationDetents([.medium, .large])
		.onAppear {
			if let cal = store.calendars.first(where: { $0.id == calendarId }) {
				color = Color(hex: cal.color)
			}
		}
	}

	private func apply() {
		guard !saving else { return }
		saving = true
		error = nil
		Task {
			let failure = await store.updateCalendarEdit(
				calendarId, patch: ["color": hexString(from: color)])
			saving = false
			if let failure {
				error = failure
			} else {
				dismiss()
			}
		}
	}
}

/// Löschen auf dem CalDAV-Server – Bestätigung durch exakt getippten Namen.
private struct DeleteCalendarSheet: View {
	let calendarId: String

	@Environment(AppStore.self) private var store
	@Environment(\.dismiss) private var dismiss

	@State private var confirmation = ""
	@State private var error: String?
	@State private var deleting = false

	private var calendarName: String? {
		store.calendars.first(where: { $0.id == calendarId })?.name
	}

	private var matches: Bool {
		guard let name = calendarName else { return false }
		return confirmation.trimmingCharacters(in: .whitespacesAndNewlines) == name
	}

	var body: some View {
		NavigationStack {
			Form {
				Section {
					Text("„\(calendarName ?? "")“ wird auf dem CalDAV-Server gelöscht – inklusive aller Termine und Aufgaben. Zur Bestätigung den Namen eintippen.")
						.font(.callout)
						.foregroundStyle(DS.textSecondary)
					TextField("Name des Kalenders", text: $confirmation)
						.autocorrectionDisabled()
						.textInputAutocapitalization(.never)
					if let error {
						ErrorBanner(message: error)
					}
				}
			}
			.formStyle(.grouped)
			.navigationTitle("Kalender löschen")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("Abbrechen") { dismiss() }
				}
				ToolbarItem(placement: .confirmationAction) {
					if deleting {
						ProgressView().controlSize(.small)
					} else {
						Button("Löschen", role: .destructive) { delete() }
							.disabled(!matches)
					}
				}
			}
		}
		.presentationDetents([.medium, .large])
	}

	private func delete() {
		guard matches, !deleting else { return }
		deleting = true
		error = nil
		let typed = confirmation.trimmingCharacters(in: .whitespacesAndNewlines)
		Task {
			let failure = await store.deleteCalendar(calendarId, name: typed)
			deleting = false
			if let failure {
				error = failure
			} else {
				dismiss()
			}
		}
	}
}

/// Neuen Kalender auf einer Verbindung anlegen (MKCALENDAR); eine abgelehnte
/// Anlage (z. B. iCloud 403) erscheint als Fehler direkt im Sheet.
private struct CreateCalendarSheet: View {
	@Environment(AppStore.self) private var store
	@Environment(\.dismiss) private var dismiss

	@State private var connectionId = ""
	@State private var name = ""
	@State private var color = Color(hex: "#4C8DF6")
	@State private var error: String?
	@State private var saving = false

	private var canCreate: Bool {
		!name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !connectionId.isEmpty
	}

	var body: some View {
		NavigationStack {
			Form {
				Section {
					if store.connections.isEmpty {
						Text("Keine Verbindungen – bitte zuerst eine CalDAV-Verbindung anlegen.")
							.font(.callout)
							.foregroundStyle(DS.textSecondary)
					} else {
						Picker("Verbindung", selection: $connectionId) {
							ForEach(store.connections, id: \.id) { conn in
								Text(conn.name).tag(conn.id)
							}
						}
					}
					TextField("Name", text: $name, prompt: Text("z. B. Projekte"))
					ColorPicker("Farbe", selection: $color, supportsOpacity: false)
					if let error {
						ErrorBanner(message: error)
					}
				} footer: {
					Text("Einige Anbieter (z. B. iCloud) lehnen das Anlegen neuer Kalender ab.")
				}
			}
			.formStyle(.grouped)
			.navigationTitle("Neuer Kalender")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("Abbrechen") { dismiss() }
				}
				ToolbarItem(placement: .confirmationAction) {
					if saving {
						ProgressView().controlSize(.small)
					} else {
						Button("Erstellen") { create() }
							.disabled(saving || !canCreate)
					}
				}
			}
		}
		.presentationDetents([.medium, .large])
		.onAppear {
			if store.connections.isEmpty {
				Task { await store.loadConnections() }
			}
			if connectionId.isEmpty {
				// Vorauswahl: Hauptverbindung, sonst erste Verbindung.
				connectionId = store.connections.first(where: { $0.role == "primary" })?.id
					?? store.connections.first?.id ?? ""
			}
		}
	}

	private func create() {
		guard canCreate, !saving else { return }
		saving = true
		error = nil
		let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
		Task {
			let failure = await store.createCalendar(
				connectionId: connectionId, name: trimmed, color: hexString(from: color))
			saving = false
			if let failure {
				error = failure
			} else {
				dismiss()
			}
		}
	}
}

// MARK: – Kategorien

/// Aufgaben-Kategorien (Name + Farbe): anlegen, bearbeiten, löschen,
/// „Standard herstellen“ – Änderungen werden sofort auf den Server geschrieben.
private struct CategoriesPage: View {
	/// String als sheet(item:)-Träger.
	private struct NameItem: Identifiable {
		let name: String
		var id: String { name }
	}

	@Environment(AppStore.self) private var store
	@Environment(AuthStore.self) private var auth

	@State private var showAdd = false
	@State private var editName: NameItem?
	@State private var deleteTarget: String?
	@State private var error: String?
	@State private var busy = false

	var body: some View {
		Form {
			Section {
				if let error {
					ErrorBanner(message: error)
				}
				if store.categories.isEmpty {
					Text("Noch keine Kategorien – oben über „+“ eine anlegen oder Standard herstellen.")
						.font(.callout)
						.foregroundStyle(DS.textSecondary)
				} else {
					ForEach(store.categories, id: \.name) { cat in
						Button {
							editName = NameItem(name: cat.name)
						} label: {
							HStack(spacing: DS.Space.sm) {
								Circle()
									.fill(Color(hex: cat.color))
									.frame(width: 12, height: 12)
								Text(cat.name)
									.font(DS.Typo.rowTitle)
									.foregroundStyle(DS.textPrimary)
								Spacer(minLength: DS.Space.xs)
								Chip(text: "\(usedCount(cat.name))")
							}
							.contentShape(Rectangle())
						}
						.buttonStyle(.plain)
						.swipeActions {
							Button(role: .destructive) { deleteTarget = cat.name } label: {
								Label("Löschen", systemImage: "trash")
							}
						}
					}
				}
			} header: {
				Text("Kategorien")
			} footer: {
				Text("Maximal 40 Zeichen ohne Komma, Semikolon und Backslash. Der Zähler zeigt offene Aufgaben je Kategorie.")
			}

			Section {
				Button("Standard herstellen") { restoreDefaults() }
					.disabled(busy)
			} footer: {
				Text("Ersetzt alle Kategorien durch Hoch · Schule · Niedrig.")
			}
		}
		.formStyle(.grouped)
		.navigationTitle("Kategorien")
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			ToolbarItem(placement: .primaryAction) {
				Button {
					showAdd = true
				} label: {
					Image(systemName: "plus")
				}
			}
		}
		.refreshable { await store.loadCategories() }
		.task { await store.loadCategories() }
		.sheet(isPresented: $showAdd) {
			CategoryEditSheet()
		}
		.sheet(item: $editName) { item in
			CategoryEditSheet(existingName: item.name)
		}
		.alert(
			"Kategorie löschen?",
			isPresented: Binding(
				get: { deleteTarget != nil },
				set: { if !$0 { deleteTarget = nil } }
			)					) {
			if let name = deleteTarget {
				Button("Löschen", role: .destructive) { delete(name) }
			}
			Button("Abbrechen", role: .cancel) {}
		} message: {
			if let name = deleteTarget {
				Text("„\(name)“ wird entfernt; bestehende Aufgaben behalten ihren Text, verlieren aber die Kategorie-Farbe.")
			}
		}
	}

	/// Anzahl sichtbarer Timeline-Einträge mit dieser Kategorie (grobe Info).
	private func usedCount(_ name: String) -> Int {
		guard let panels = store.home?.panels else { return 0 }
		return panels.flatMap(\.days).flatMap(\.events)
			.filter { $0.category == name }.count
	}

	/// Ganze Liste ersetzen (POST /api/categories) und Store neu laden.
	private func persist(_ rows: [TaskCategory]) async {
		guard let client = auth.client else { return }
		busy = true
		error = nil
		do {
			_ = try await client.saveCategories(rows)
			await store.loadCategories()
		} catch {
			self.error = error.localizedDescription
		}
		busy = false
	}

	private func restoreDefaults() {
		Task { await persist(TaskCategories.defaults) }
	}

	private func delete(_ name: String) {
		deleteTarget = nil
		let rows = store.categories.filter { $0.name != name }
		Task { await persist(rows) }
	}
}

/// Kategorie anlegen bzw. umbenennen (Name + Farbe); Änderungen sofort gespeichert.
private struct CategoryEditSheet: View {
	/// nil = neue Kategorie.
	let existingName: String?

	@Environment(AppStore.self) private var store
	@Environment(AuthStore.self) private var auth
	@Environment(\.dismiss) private var dismiss

	@State private var name = ""
	@State private var color: Color = DS.accent
	@State private var error: String?
	@State private var saving = false

	private var isEdit: Bool { existingName != nil }

	init(existingName: String? = nil) {
		self.existingName = existingName
	}

	var body: some View {
		NavigationStack {
			Form {
				Section {
					TextField("Name", text: $name)
					ColorPicker("Farbe", selection: $color, supportsOpacity: false)
					if let error {
						ErrorBanner(message: error)
					}
				} footer: {
					Text("Erlaubt sind 1–40 Zeichen ohne Komma, Semikolon und Backslash.")
				}
			}
			.formStyle(.grouped)
			.navigationTitle(isEdit ? "Kategorie bearbeiten" : "Neue Kategorie")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("Abbrechen") { dismiss() }
				}
				ToolbarItem(placement: .confirmationAction) {
					if saving {
						ProgressView().controlSize(.small)
					} else {
						Button("Speichern") { save() }
							.disabled(saving)
					}
				}
			}
		}
		.presentationDetents([.medium, .large])
		.onAppear {
			if let existingName,
			   let cat = store.categories.first(where: { $0.name == existingName }) {
				name = cat.name
				color = Color(hex: cat.color)
			}
		}
	}

	private func save() {
		guard !saving, let client = auth.client else { return }
		error = nil
		// Namen nach Regeln der Web-App normalisieren (nil = ungültig).
		guard let trimmed = TaskCategories.normalize(name) else {
			error = "Ungültiger Name (leer, zu lang oder Sonderzeichen , ; \\)."
			return
		}
		let hex = hexString(from: color)
		var rows = store.categories
		if let old = existingName {
			guard let i = rows.firstIndex(where: { $0.name == old }) else {
				dismiss()
				return
			}
			rows[i] = TaskCategory(name: trimmed, color: hex)
		} else {
			guard !rows.contains(where: { $0.name.lowercased() == trimmed.lowercased() }) else {
				error = "Diese Kategorie gibt es schon."
				return
			}
			rows.append(TaskCategory(name: trimmed, color: hex))
		}
		saving = true
		Task {
			do {
				_ = try await client.saveCategories(rows)
				await store.loadCategories()
				dismiss()
			} catch {
				saving = false
				self.error = error.localizedDescription
			}
		}
	}
}

// MARK: – Aufgaben-Benachrichtigungen

/// Webhook-Konfiguration für die Aufgaben-Zusammenfassung (Parität zur Web-App):
/// Frequenz, Zeit, Webhook-URL, Nachrichtentext, Kategorien, Testversand.
private struct NotifyPage: View {
	@Environment(AppStore.self) private var store

	// Arbeitskopie der Konfiguration (wird aus store.notify initialisiert).
	@State private var frequency: NotifyFrequency = .manual
	@State private var time = "08:00"
	@State private var weekday = 0
	@State private var intervalHours = 3
	@State private var url = ""
	@State private var prompt = ""
	@State private var selectedCategories: Set<String> = []
	@State private var seeded = false

	@State private var saving = false
	@State private var saveError: String?
	@State private var savedFlash = false
	@State private var testingSend = false
	@State private var sendTestError: String?
	@State private var sendTestFlash = false

	private let weekdayNames = ["Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag"]

	/// Zeitfeld wird nur für tägliche/wöchentliche Läufe benötigt.
	private var showsTime: Bool { frequency == .daily || frequency == .weekly }

	var body: some View {
		Group {
			if let notify = store.notify {
				form(notify)
			} else {
				ProgressView("Lädt Konfiguration …")
					.foregroundStyle(DS.textSecondary)
			}
		}
		.navigationTitle("Benachrichtigungen")
		.navigationBarTitleDisplayMode(.inline)
		.task {
			// Erst seeden (Werte sofort sichtbar), dann Kategorien nachladen.
			if store.notify == nil { await store.loadNotify() }
			if let notify = store.notify, !seeded {
				seed(from: notify)
			}
			await store.loadCategories()
		}
	}

	@ViewBuilder
	private func form(_ notify: NotifyConfigView) -> some View {
		Form {
			Section {
				HStack(spacing: DS.Space.xs) {
					Chip(text: notify.hasToken ? "Token gesetzt" : "Kein Token",
					     color: notify.hasToken ? DS.success : DS.textSecondary,
					     systemImage: "key.fill")
					Spacer()
				}
			} footer: {
				Text("Der Zugriffsschlüssel wird in der Web-App verwaltet.")
			}

			Section("Zeitplan") {
				Picker("Wiederholung", selection: $frequency) {
					Text("Aus").tag(NotifyFrequency.manual)
					Text("Täglich").tag(NotifyFrequency.daily)
					Text("Wöchentlich").tag(NotifyFrequency.weekly)
					Text("Intervall").tag(NotifyFrequency.interval)
				}
				.pickerStyle(.menu)

				if showsTime {
					HStack {
						Text("Sendezeit")
						Spacer()
						TextField("HH:MM", text: $time)
							.frame(maxWidth: 90)
							.multilineTextAlignment(.trailing)
							.keyboardType(.numberPad)
							.autocorrectionDisabled()
					}
					if !isValidTime(time) {
						Text("Format: HH:MM (z. B. 07:30)")
							.font(.caption)
							.foregroundStyle(DS.danger)
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
			}

			Section {
				TextField("https://…", text: $url)
					.autocorrectionDisabled()
					.keyboardType(.URL)
					.textInputAutocapitalization(.never)
			} header: {
				Text("Webhook-URL")
			} footer: {
				Text("HTTPS-Endpunkt, an den die Zusammenfassung gesendet wird.")
			}

			Section {
				TextField("Prompt", text: $prompt, axis: .vertical)
					.lineLimit(3...6)
					.autocorrectionDisabled()
			} header: {
				Text("Nachricht")
			} footer: {
				Text("Platzhalter: {{body}} = Aufgabenliste, {{stand}} = Zeitpunkt.")
			}

			Section {
				if store.categories.isEmpty {
					Text("Keine Kategorien vorhanden – es werden alle Aufgaben gesendet.")
						.font(.callout)
						.foregroundStyle(DS.textSecondary)
				} else {
					ForEach(store.categories, id: \.name) { cat in
						Toggle(isOn: Binding(
							get: { selectedCategories.contains(cat.name) },
							set: { on in
								if on { selectedCategories.insert(cat.name) }
								else { selectedCategories.remove(cat.name) }
							})) {
							HStack(spacing: DS.Space.sm) {
								Circle()
									.fill(Color(hex: cat.color))
									.frame(width: 10, height: 10)
								Text(cat.name)
							}
						}
					}
				}
			} header: {
				Text("Nur diese Kategorien")
			} footer: {
				Text("Nichts ausgewählt heißt: alle Kategorien.")
			}

			Section {
				if saving {
					Label("Speichern läuft …", systemImage: "hourglass")
						.foregroundStyle(DS.textSecondary)
				}
				if savedFlash {
					SuccessFlash(text: "Gespeichert.")
				}
				if sendTestFlash {
					SuccessFlash(text: "Test versendet – bitte beim Empfänger prüfen.")
				}
				if let err = saveError {
					ErrorBanner(message: err)
				}
				if let err = sendTestError {
					ErrorBanner(message: "Testversand: \(err)")
				}

				Button {
					save()
				} label: {
					Text(saving ? "Wird gespeichert …" : "Speichern")
						.frame(maxWidth: .infinity, minHeight: 36)
						.contentShape(Rectangle())
				}
				.disabled(saving || (showsTime && !isValidTime(time)))

				Button {
					sendTest()
				} label: {
					Text(testingSend ? "Sende Test …" : "Testversand")
						.frame(maxWidth: .infinity, minHeight: 36)
						.contentShape(Rectangle())
				}
				.disabled(testingSend)
			} footer: {
				if let run = notify.lastRun {
					Text("Letzter Lauf: \(run.date) · \(run.status)")
				}
			}
		}
		.formStyle(.grouped)
	}

	/// Arbeitskopie aus der geladenen Konfiguration füllen (nur einmal).
	private func seed(from notify: NotifyConfigView) {
		frequency = notify.frequency
		time = notify.time
		weekday = notify.weekday
		intervalHours = notify.intervalHours
		url = notify.url ?? ""
		prompt = notify.prompt
		selectedCategories = Set(notify.categories)
		seeded = true
	}

	/// Speichern über store.saveNotify; Erfolg = grüner Hinweistext, Fehler = Banner.
	private func save() {
		guard !saving else { return }
		saving = true
		saveError = nil
		savedFlash = false
		let cats = store.categories
			.filter { selectedCategories.contains($0.name) }
			.map(\.name)
		Task {
			let err = await store.saveNotify(
				frequency: frequency,
				time: time,
				weekday: weekday,
				intervalHours: intervalHours,
				url: url.trimmingCharacters(in: .whitespacesAndNewlines),
				prompt: prompt,
				categories: cats
			)
			saving = false
			if let err {
				saveError = err
			} else {
				sendTestFlash = false
				savedFlash = true
				try? await Task.sleep(for: .seconds(2))
				savedFlash = false
			}
		}
	}

	/// Testversand mit den aktuellen Formularwerten (leere Werte: gespeicherte Config).
	private func sendTest() {
		guard !testingSend else { return }
		testingSend = true
		sendTestError = nil
		savedFlash = false
		let u = url.trimmingCharacters(in: .whitespacesAndNewlines)
		let pr = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
		Task {
			let err = await store.sendNotifyTest(url: u, prompt: pr)
			testingSend = false
			if let err {
				sendTestError = err
			} else {
				sendTestFlash = true
				try? await Task.sleep(for: .seconds(3))
				sendTestFlash = false
			}
		}
	}
}

// MARK: – Design

/// Appearance-Modus (System/Hell/Dunkel) und Akzentfarbe – wirkt sofort überall.
private struct AppearancePage: View {
	@Environment(ThemeStore.self) private var theme

	var body: some View {
		Form {
			Section("Darstellung") {
				Picker("Farbmodus", selection: Binding(
					get: { theme.mode },
					set: { theme.mode = $0 })) {
					ForEach(AppearanceMode.allCases) { mode in
						Label(mode.label, systemImage: mode.icon).tag(mode)
					}
				}
				.pickerStyle(.menu)
			}

			Section {
				HStack(spacing: DS.Space.lg) {
					ForEach(AccentPreset.all) { preset in
						AccentDot(preset: preset, isActive: theme.accentPreset.id == preset.id) {
							theme.accentPreset = preset
						}
					}
					Spacer(minLength: 0)
				}
				.padding(.vertical, DS.Space.xs)
			} header: {
				Text("Akzentfarbe")
			} footer: {
				Text("Die Akzentfarbe gilt auch für die Home-Screen-Widgets.")
			}
		}
		.formStyle(.grouped)
		.navigationTitle("Design")
		.navigationBarTitleDisplayMode(.inline)
	}
}

/// Farbpunkt mit Auswahl-Ring (Akzent-Presets), für Touch etwas größer.
private struct AccentDot: View {
	let preset: AccentPreset
	let isActive: Bool
	let action: () -> Void

	var body: some View {
		Button(action: action) {
			ZStack {
				Circle()
					.fill(Color.dynamic(light: preset.light, dark: preset.dark))
					.frame(width: 32, height: 32)
				if isActive {
					Image(systemName: "checkmark")
						.font(.system(size: 12, weight: .bold))
						.foregroundStyle(.white)
				}
			}
			.overlay(
				Circle().strokeBorder(
					isActive ? DS.textPrimary : Color.clear,
					lineWidth: 2)
					.padding(-4)
			)
			.frame(width: 40, height: 40)
			.contentShape(Circle())
		}
		.buttonStyle(.plain)
		.accessibilityLabel(preset.name)
	}
}

// MARK: – Hilfsfunktionen

extension String {
	/// Um Weißraum beschnittener Text (Formularfelder).
	fileprivate var trimmed: String {
		trimmingCharacters(in: .whitespacesAndNewlines)
	}
}

/// Prüft das Zeitformat HH:MM (0–23 Uhr, 0–59 Minuten).
private func isValidTime(_ s: String) -> Bool {
	let parts = s.split(separator: ":", omittingEmptySubsequences: false)
	guard parts.count == 2, parts[0].count == 2, parts[1].count == 2,
	      let hour = Int(parts[0]), let minute = Int(parts[1]) else { return false }
	return (0...23).contains(hour) && (0...59).contains(minute)
}

/// Color als #rrggbb (für Kalender- und Kategorien-Farbpatches).
private func hexString(from color: Color) -> String {
	var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
	UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
	return String(format: "#%02X%02X%02X",
	              Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
}
