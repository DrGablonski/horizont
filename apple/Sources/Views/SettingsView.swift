import SwiftUI

/// Einstellungen: Konto, CalDAV-Verbindungen, Kalender, Aufgaben-Benachrichtigungen,
/// Server, Version und Abmelden – Kartenlayout nach Web-Vorbild.
/// Verbindungen und Kalender werden nur angezeigt (CRUD bleibt in der Web-App).
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
			ScrollView {
				VStack(spacing: DS.Space.lg) {
					SettingsSectionCard(title: "Konto") {
						LabeledContent {
							Text(auth.user?.username ?? "–")
						} label: {
							HStack(spacing: DS.Space.md) {
								avatar
								Text("Angemeldet als")
							}
						}
						LabeledContent("Rolle", value: auth.user?.role ?? "–")
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
			.navigationTitle("Einstellungen")
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
				.foregroundStyle(Color.accentColor)
		}
		.frame(width: 28, height: 28)
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

/// Anzeige der CalDAV-Verbindungen mit Test-Button (ohne CRUD – Web-App ist Source of Truth).
private struct ConnectionsSection: View {
	@Environment(AppStore.self) private var store

	@State private var results: [String: TestResult] = [:]
	@State private var errors: [String: String] = [:]
	@State private var testing: Set<String> = []

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
		}
		.task { await store.loadConnections() }
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
						? "Verbindungen prüfen oder in der Web-App anlegen."
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
		let color = dsColor(hex: cat.color) ?? Color.accentColor
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
	return Color(nsColor: NSColor(
		srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
		green: CGFloat((value >> 8) & 0xFF) / 255,
		blue: CGFloat(value & 0xFF) / 255,
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
