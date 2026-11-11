import SwiftUI

/// Einstellungen: Konto, CalDAV-Verbindungen, Kalender, Aufgaben-Benachrichtigungen,
/// Server, Version und Abmelden – Kartenlayout nach Web-Vorbild.
/// Kalender werden hier verwaltet (Sichtbarkeit, Schreiben, Farbe, Standard, Löschen);
/// Verbindungen anzeigen/testen plus Rollenwechsel – Anlegen bleibt in der Web-App.
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
			VStack(spacing: 0) {
				SectionHeader("Einstellungen", subtitle: "Konto, Verbindungen & Benachrichtigungen")

				ScrollView {
					VStack(spacing: DS.Space.lg) {
						AppearanceSection()

						SettingsSectionCard(title: "Konto") {
							LabeledContent {
								Text(auth.user?.username ?? "–")
							} label: {
								HStack(spacing: DS.Space.md) {
									avatar
									Text("Angemeldet als")
								}
							}
						}

						ConnectionsSection()
						CalendarsSection()
						NotifySection()

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
					.padding(DS.Space.xl)
					.frame(maxWidth: 640)
					.frame(maxWidth: .infinity)
					}
				}
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

// MARK: – Erscheinungsbild

/// Appearance-Modus (System/Hell/Dunkel) + Akzent-Presets – Bedienung wie die
/// Theme-Kacheln bei Diddy, wirkt sofort im ganzen Fenster.
private struct AppearanceSection: View {
	@Environment(ThemeStore.self) private var theme

	var body: some View {
		SettingsSectionCard(title: "Erscheinungsbild") {
			HStack(spacing: DS.Space.sm) {
				ForEach(AppearanceMode.allCases) { mode in
					ModePill(mode: mode, isActive: theme.mode == mode) {
						theme.mode = mode
					}
				}
				Spacer()
			}

			VStack(alignment: .leading, spacing: DS.Space.sm) {
				Text("Akzentfarbe")
					.font(DS.Typo.meta)
					.foregroundStyle(DS.textSecondary)
				HStack(spacing: DS.Space.sm) {
					ForEach(AccentPreset.all) { preset in
						AccentDot(preset: preset, isActive: theme.accentPreset.id == preset.id) {
							theme.accentPreset = preset
						}
					}
				}
			}
		}
	}
}

/// Umschalt-Pille für die Appearance-Modi.
private struct ModePill: View {
	let mode: AppearanceMode
	let isActive: Bool
	let action: () -> Void

	@State private var hovering = false

	var body: some View {
		Button(action: action) {
			HStack(spacing: DS.Space.xs) {
				Image(systemName: mode.icon).font(.system(size: 11, weight: .medium))
				Text(mode.label).font(.callout.weight(isActive ? .semibold : .medium))
			}
			.foregroundStyle(isActive ? DS.accent : DS.textSecondary)
			.padding(.horizontal, DS.Space.md)
			.padding(.vertical, 7)
			.background(
				Capsule().fill(isActive ? DS.tintSoft : hovering ? DS.rowHover : DS.fillSubtle)
			)
			.overlay(
				Capsule().strokeBorder(isActive ? DS.accent.opacity(0.5) : DS.border, lineWidth: 1)
			)
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.onHover { hovering = $0 }
	}
}

/// Farbpunkt mit Auswahl-Ring (Akzent-Presets).
private struct AccentDot: View {
	let preset: AccentPreset
	let isActive: Bool
	let action: () -> Void

	@State private var hovering = false

	var body: some View {
		Button(action: action) {
			ZStack {
				Circle()
					.fill(Color.dynamic(light: preset.light, dark: preset.dark))
					.frame(width: 26, height: 26)
				if isActive {
					Image(systemName: "checkmark")
						.font(.system(size: 11, weight: .bold))
						.foregroundStyle(.white)
				}
			}
			.overlay(
				Circle().strokeBorder(
					isActive ? DS.textPrimary : hovering ? DS.borderStrong : Color.clear,
					lineWidth: isActive ? 2 : 1.5)
					.padding(-4)
			)
			.help(preset.name)
			.accessibilityLabel(preset.name)
		}
		.buttonStyle(.plain)
		.onHover { hovering = $0 }
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

/// CalDAV-Verbindungen mit Test-Button, Rollen-Badge und Hauptverbindung-Umschalten;
/// darunter die Anbieter-Vorlagen als Vorlage fürs Anlegen/Bearbeiten (Web-App).
private struct ConnectionsSection: View {
	@Environment(AppStore.self) private var store

	@State private var results: [String: TestResult] = [:]
	@State private var errors: [String: String] = [:]
	@State private var testing: Set<String> = []
	@State private var settingPrimary: Set<String> = []

	var body: some View {
		SettingsSectionCard(title: "CalDAV-Verbindungen") {
			if store.connections.isEmpty {
				Text("Keine Verbindungen konfiguriert – anlegen in der Web-App.")
					.font(.callout)
					.foregroundStyle(DS.textSecondary)
			} else {
				VStack(alignment: .leading, spacing: DS.Space.sm) {
					ForEach(store.connections) { conn in
						connectionBlock(conn)
					}
				}
			}

			if !store.providerPresets.isEmpty {
				Divider().overlay(DS.border)
				presetsBlock
			}
		}
		.task {
			await store.loadConnections()
			if store.providerPresets.isEmpty { await store.loadProviderPresets() }
		}
	}

	/// Karte pro Verbindung; Fehlerbanner steht direkt unter der Karte.
	@ViewBuilder
	private func connectionBlock(_ conn: ConnectionView) -> some View {
		VStack(alignment: .leading, spacing: DS.Space.sm) {
			VStack(alignment: .leading, spacing: DS.Space.sm) {
				HStack(spacing: DS.Space.sm) {
					Text(conn.name)
						.font(DS.Typo.rowTitle)
						.foregroundStyle(DS.textPrimary)
						.lineLimit(1)
					Chip(text: conn.role == "primary" ? "Hauptverbindung" : "Zusatzverbindung",
					     color: conn.role == "primary" ? DS.accent : DS.textSecondary)
					Spacer(minLength: DS.Space.sm)
					testButton(conn)
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
				// Rollen-Umschalten: nur Zusatzverbindungen können Hauptverbindung werden.
				if conn.role != "primary" {
					HStack(spacing: DS.Space.sm) {
						Button("Als Hauptverbindung setzen") { setPrimary(conn) }
							.buttonStyle(.bordered)
							.controlSize(.small)
							.disabled(settingPrimary.contains(conn.id))
						Spacer(minLength: 0)
					}
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

	/// Rolle wechseln: diese Verbindung wird Hauptverbindung; Fehler als Banner.
	private func setPrimary(_ conn: ConnectionView) {
		guard !settingPrimary.contains(conn.id) else { return }
		settingPrimary.insert(conn.id)
		errors.removeValue(forKey: conn.id)
		Task {
			let err = await store.setPrimaryConnection(conn.id)
			settingPrimary.remove(conn.id)
			if let err {
				errors[conn.id] = err
			}
		}
	}

	/// Anbieter-Vorlagen: URL, Benutzerfeld und Hinweis fürs Anlegen/Bearbeiten
	/// einer Verbindung (Google z. B. nur als Hinweis – OAuth2 nötig).
	private var presetsBlock: some View {
		VStack(alignment: .leading, spacing: DS.Space.sm) {
			Text("Anbieter-Vorlagen")
				.font(DS.Typo.metaStrong)
				.foregroundStyle(DS.textSecondary)
			Text("URL und Zugangsdaten als Vorlage – Verbindungen anlegen/bearbeiten in der Web-App.")
				.font(.caption)
				.foregroundStyle(DS.textTertiary)
			ForEach(store.providerPresets, id: \.id) { preset in
				VStack(alignment: .leading, spacing: 2) {
					HStack(spacing: DS.Space.xs) {
						Text(preset.label)
							.font(.callout.weight(.semibold))
							.foregroundStyle(DS.textPrimary)
						if !preset.supportsCalendarCreation {
							Chip(text: "Kalender-Anlage oft abgelehnt", color: DS.danger)
						}
						Spacer(minLength: DS.Space.sm)
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
			}
		}
	}
}

// MARK: – Kalender

/// Alle Kalender, gruppiert pro Verbindung (mit Rollen-Badge), verwaltbar:
/// Sichtbarkeit, Schreibschutz, Farbe, Standardkalender, Umbenennen, Löschen
/// (Bestätigung = Name) und „Neuer Kalender“ auf einer Verbindung.
private struct CalendarsSection: View {
	@Environment(AppStore.self) private var store

	/// Ziel für das Bearbeitungs-Sheet (Kalender wird über die id im Store gesucht).
	private struct CalendarTarget: Identifiable {
		let id: String
	}

	/// Kalender einer Verbindung, in Server-Reihenfolge.
	private struct ConnectionGroup: Identifiable {
		let connectionId: String
		let title: String
		let role: String
		var calendars: [CalendarView]
		var id: String { connectionId }
	}

	@State private var renameTarget: CalendarTarget?
	@State private var colorTarget: CalendarTarget?
	@State private var deleteTarget: CalendarTarget?
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
		SettingsSectionCard(title: "Kalender") {
			if store.calendars.isEmpty {
				EmptyStateView(
					title: "Keine Kalender gefunden.",
					systemImage: "calendar",
					description: store.calendarsLoaded
						? "Verbindungen prüfen oder in der Web-App anlegen."
						: nil
				)
				.frame(height: 170)
			} else {
				VStack(alignment: .leading, spacing: DS.Space.lg) {
					ForEach(groups) { group in
						groupBlock(group)
					}
					if let err = store.calendarsError {
						ErrorBanner(message: err, retry: { Task { await store.loadCalendars() } })
					}
					Button("Neuer Kalender", systemImage: "plus") { showCreate = true }
						.buttonStyle(.bordered)
				}
			}
		}
		.task {
			if !store.calendarsLoaded { await store.loadCalendars() }
		}
		.sheet(item: $renameTarget) { target in
			RenameCalendarSheet(calendarId: target.id)
		}
		.sheet(item: $colorTarget) { target in
			CalendarColorSheet(calendarId: target.id)
		}
		.sheet(item: $deleteTarget) { target in
			DeleteCalendarSheet(calendarId: target.id)
		}
		.sheet(isPresented: $showCreate) {
			CreateCalendarSheet()
		}
	}

	/// Gruppenkopf mit Verbindungsname + Rollen-Badge, darunter die Kalenderzeilen.
	@ViewBuilder
	private func groupBlock(_ group: ConnectionGroup) -> some View {
		VStack(alignment: .leading, spacing: DS.Space.sm) {
			HStack(spacing: DS.Space.sm) {
				Text(group.title)
					.font(DS.Typo.rowTitle.weight(.semibold))
					.foregroundStyle(DS.textPrimary)
					.lineLimit(1)
				Chip(text: group.role == "primary" ? "Hauptkalender" : "Zusatzkalender",
				     color: group.role == "primary" ? DS.accent : DS.textSecondary)
				Spacer(minLength: DS.Space.sm)
			}
			ForEach(group.calendars, id: \.id) { cal in
				calendarRow(cal)
			}
		}
	}

	/// Zeile pro Kalender: Name + Badges + Menü, darunter Sichtbar-/Beschreibbar-Schalter.
	@ViewBuilder
	private func calendarRow(_ cal: CalendarView) -> some View {
		VStack(alignment: .leading, spacing: DS.Space.xs) {
			HStack(spacing: DS.Space.sm) {
				Circle()
					.fill(Color(hex: cal.color))
					.frame(width: 10, height: 10)
				Text(cal.name)
					.font(DS.Typo.rowTitle)
					.foregroundStyle(cal.hidden ? DS.textTertiary : DS.textPrimary)
					.lineLimit(1)
				if cal.isDefault {
					Chip(text: "Standard", color: DS.success, systemImage: "star.fill")
				}
				if !cal.writable {
					Chip(text: "Server: schreibgeschützt", color: DS.textSecondary,
					     systemImage: "lock.fill")
				}
				Spacer(minLength: DS.Space.sm)
				Menu {
					Button("Als Standard setzen", disabled: cal.isDefault) {
						Task { await store.setDefaultCalendar(cal.id) }
					}
					Button("Umbenennen") { renameTarget = CalendarTarget(id: cal.id) }
					Button("Farbe ändern") { colorTarget = CalendarTarget(id: cal.id) }
					Button("Löschen", role: .destructive) { deleteTarget = CalendarTarget(id: cal.id) }
				} label: {
					Image(systemName: "ellipsis.circle")
						.foregroundStyle(DS.textSecondary)
				}
			}
			HStack(spacing: DS.Space.lg) {
				Toggle("Sichtbar", isOn: Binding(
					get: { !cal.hidden },
					set: { _ in Task { await store.toggleCalendarVisibility(cal.id) } }))
					.font(DS.Typo.meta)
					.toggleStyle(.switch)
					.controlSize(.mini)
				Toggle("Beschreibbar", isOn: Binding(
					get: { cal.writable && !cal.writeDisabled },
					set: { newValue in
						Task { await store.updateCalendarEdit(cal.id, patch: ["writeDisabled": !newValue]) }
					}))
					.font(DS.Typo.meta)
					.toggleStyle(.switch)
					.controlSize(.mini)
					.disabled(!cal.writable)
				Spacer(minLength: DS.Space.sm)
			}
		}
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
		VStack(alignment: .leading, spacing: DS.Space.lg) {
			Text("Kalender umbenennen")
				.font(DS.Typo.cardTitle)
				.foregroundStyle(DS.textPrimary)

			TextField("Name", text: $name)

			if let error {
				ErrorBanner(message: error)
			}

			HStack(spacing: DS.Space.sm) {
				Button("Abbrechen") { dismiss() }
					.ghostButton()
					.keyboardShortcut(.cancelAction)
				Spacer(minLength: DS.Space.sm)
				Button("Speichern") { save() }
					.keyboardShortcut(.defaultAction)
					.primaryButton()
					.disabled(saving || !canSave)
			}
		}
		.padding(DS.Space.xl)
		.frame(width: 420)
		.background(DS.card)
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
		VStack(alignment: .leading, spacing: DS.Space.lg) {
			Text("Kalenderfarbe")
				.font(DS.Typo.cardTitle)
				.foregroundStyle(DS.textPrimary)

			ColorPicker("Farbe", selection: $color)

			if let error {
				ErrorBanner(message: error)
			}

			HStack(spacing: DS.Space.sm) {
				Button("Abbrechen") { dismiss() }
					.ghostButton()
					.keyboardShortcut(.cancelAction)
				Spacer(minLength: DS.Space.sm)
				Button("Übernehmen") { apply() }
					.keyboardShortcut(.defaultAction)
					.primaryButton()
					.disabled(saving)
			}
		}
		.padding(DS.Space.xl)
		.frame(width: 420)
		.background(DS.card)
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
		VStack(alignment: .leading, spacing: DS.Space.lg) {
			Text("Kalender löschen")
				.font(DS.Typo.cardTitle)
				.foregroundStyle(DS.textPrimary)

			Text("„\(calendarName ?? "")“ wird auf dem CalDAV-Server gelöscht. Zur Bestätigung den Namen eintippen.")
				.font(.callout)
				.foregroundStyle(DS.textSecondary)

			TextField("Name des Kalenders", text: $confirmation)
				.autocorrectionDisabled()

			if let error {
				ErrorBanner(message: error)
			}

			HStack(spacing: DS.Space.sm) {
				Button("Abbrechen") { dismiss() }
					.ghostButton()
					.keyboardShortcut(.cancelAction)
				Spacer(minLength: DS.Space.sm)
				Button(deleting ? "Wird gelöscht …" : "Löschen", role: .destructive) { delete() }
					.buttonStyle(.borderedProminent)
					.tint(DS.danger)
					.disabled(!matches || deleting)
			}
		}
		.padding(DS.Space.xl)
		.frame(width: 420)
		.background(DS.card)
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
		VStack(alignment: .leading, spacing: DS.Space.lg) {
			Text("Neuer Kalender")
				.font(DS.Typo.cardTitle)
				.foregroundStyle(DS.textPrimary)

			VStack(alignment: .leading, spacing: DS.Space.xs) {
				Text("Verbindung")
					.font(DS.Typo.metaStrong)
					.foregroundStyle(DS.textSecondary)
				if store.connections.isEmpty {
					Text("Keine Verbindungen – bitte zuerst in der Web-App einrichten.")
						.font(DS.Typo.meta)
						.foregroundStyle(DS.textSecondary)
				} else {
					Picker(selection: $connectionId) {
						ForEach(store.connections, id: \.id) { conn in
							Text(conn.name).tag(conn.id)
						}
					} label: {
						Text("Verbindung")
					}
					.labelsHidden()
				}
			}

			VStack(alignment: .leading, spacing: DS.Space.xs) {
				Text("Name")
					.font(DS.Typo.metaStrong)
					.foregroundStyle(DS.textSecondary)
				TextField("z. B. Projekte", text: $name)
			}

			ColorPicker("Farbe", selection: $color)

			if let error {
				ErrorBanner(message: error)
			}

			HStack(spacing: DS.Space.sm) {
				Button("Abbrechen") { dismiss() }
					.ghostButton()
					.keyboardShortcut(.cancelAction)
				Spacer(minLength: DS.Space.sm)
				Button(action: create) {
					if saving {
						HStack(spacing: DS.Space.xs) {
							ProgressView().controlSize(.small)
							Text("Wird angelegt …")
						}
					} else {
						Text("Erstellen")
					}
				}
				.keyboardShortcut(.defaultAction)
				.primaryButton()
				.disabled(saving || !canCreate)
			}
		}
		.padding(DS.Space.xl)
		.frame(width: 420)
		.background(DS.card)
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
		SettingsSectionCard(title: "Aufgaben-Benachrichtigungen") {
			if let notify = store.notify {
				headerRow(notify)

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
					Text("HTTPS-Endpunkt, an den die Zusammenfassung gesendet wird.")
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
				if let err = sendTestError {
					ErrorBanner(message: "Testversand: \(err)")
				}
				if savedFlash {
					Label("Gespeichert.", systemImage: "checkmark.circle.fill")
						.font(.callout)
						.foregroundStyle(DS.success)
				}
				if sendTestFlash {
					Label("Test versendet – bitte beim Empfänger prüfen.", systemImage: "paperplane.fill")
						.font(.callout)
						.foregroundStyle(DS.success)
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
							Text("Testversand")
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
				DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
					savedFlash = false
				}
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
				DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
					sendTestFlash = false
				}
			}
		}
	}
}

// MARK: – Hilfsfunktionen

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
	return Color(
		red: Double((value >> 16) & 0xFF) / 255,
		green: Double((value >> 8) & 0xFF) / 255,
		blue: Double(value & 0xFF) / 255)
}

/// Color als #rrggbb (für Kalender-Farbpatches).
private func hexString(from color: Color) -> String {
	var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
	UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
	return String(format: "#%02X%02X%02X",
	              Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
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
