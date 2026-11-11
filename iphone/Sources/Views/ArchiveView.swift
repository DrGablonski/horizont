import SwiftUI

/// Archiv (iPhone): Monats-Blättern über Chevron-Buttons in der Toolbar
/// (Titel = Monat, Untertitel = Eintragszähler), die Einträge des Monats als
/// nach Tagen gruppierte, scrollbare Liste. Statt das breite Monatsraster des
/// Pads auf kleiner Breite nachzubauen, zeigt das iPhone kompakt nur die Tage
/// mit Einträgen – „kann nicht alles auf einmal zeigen“ löst die Liste.
struct ArchiveView: View {
	@Environment(AppStore.self) private var store

	var body: some View {
		Group {
			if store.archiveBusy && store.archive == nil {
				TimelineSkeleton()
			} else if let archive = store.archive {
				content(archive)
			} else if !store.archiveBusy {
				EmptyStateView(
					title: "Archiv nicht verfügbar",
					systemImage: "tray.and.arrow.down",
					description: store.archiveError ?? "Server nicht erreichbar.",
					actionTitle: "Erneut versuchen",
					action: { Task { await store.loadArchive() } })
			}
		}
		.navigationTitle(monthTitle(currentMonthKey))
		.navigationBarTitleDisplayMode(.large)
		.toolbar {
			// Monats-Blättern: Pfeile rechts in der Toolbar (wie systemüblich).
			ToolbarItemGroup(placement: .primaryAction) {
				Button {
					shiftMonth(by: -1)
				} label: {
					Image(systemName: "chevron.left")
				}
				.disabled(!(store.archive?.canPrev ?? false))
				.accessibilityLabel("Voriger Monat")

				Button {
					shiftMonth(by: 1)
				} label: {
					Image(systemName: "chevron.right")
				}
				.disabled(!(store.archive?.canNext ?? false))
				.accessibilityLabel("Nächster Monat")
			}
		}
		.task {
			if store.archive == nil { await store.loadArchive() }
		}
	}

	// MARK: – Inhalt

	@ViewBuilder
	private func content(_ archive: ArchiveMonth) -> some View {
		if archive.days.isEmpty {
			EmptyStateView(
				title: "Keine Einträge",
				systemImage: "calendar",
				description: "Im \(monthTitle(archive.monthKey)) liegen keine archivierten Einträge.")
		} else {
			List {
				// Unterzeile (statt navigationSubtitle, das erst iOS 26 ist):
				// Eintragszahl des Monats dezent über der Liste.
				Section {
					Text(subtitle)
						.font(DS.Typo.meta)
						.foregroundStyle(DS.textTertiary)
						.listRowBackground(Color.clear)
				}

				if let err = store.archiveError {
					Section {
						ErrorBanner(message: err, retry: {
							Task { await store.loadArchive(monthKey: archive.monthKey) }
						})
						.listRowBackground(DS.card)
					}
				}

				if !archive.configured {
					Section {
						Label(
							"CalDAV ist auf dem Server noch nicht eingerichtet.",
							systemImage: "exclamationmark.triangle")
							.font(DS.Typo.meta)
							.foregroundStyle(DS.textSecondary)
							.listRowBackground(DS.card)
					}
				}

				// Tage mit Einträgen, je Tag eine Sektion mit Kopfzeile.
				ForEach(archive.days) { day in
					Section {
						ForEach(day.events) { event in
							// Archiv-Zeilen sind rein anschau-/abhakbar (kein Detail-Screen).
							EventRowView(event: event) {
								await store.toggleTask(event)
							}
							.listRowBackground(DS.card)
						}
					} header: {
						dayHeader(day)
					}
				}
			}
			.listStyle(.insetGrouped)
			.scrollContentBackground(.hidden)   // Ambient-Hintergrund der Shell scheinen durch
			.refreshable { await store.loadArchive(monthKey: archive.monthKey) }
		}
	}

	/// Tages-Kopf der Sektion: Datum, „Heute“-Pille (überfällig im Danger-Ton), Zähler.
	@ViewBuilder
	private func dayHeader(_ day: DayGroup) -> some View {
		let hasOverdue = day.events.contains { $0.overdue == true }
		HStack(spacing: DS.Space.sm) {
			Text(day.label)
				.font(DS.Typo.metaStrong)
				.foregroundStyle(hasOverdue ? DS.danger : (day.isToday ? DS.textPrimary : DS.textSecondary))
			if day.isToday {
				Chip(text: "Heute", color: DS.accent)
			}
			Spacer(minLength: 0)
			Chip(text: "\(day.events.count)", color: DS.textTertiary)
		}
		.textCase(nil)   // Section-Header sonst großgeschrieben – DatumsLabels bleiben gemischt
	}

	// MARK: – Monatswechsel & Titel

	/// Blättert zum vorigen/nächsten Monat (Button-Disabled folgt aus canPrev/canNext).
	private func shiftMonth(by delta: Int) {
		guard let key = store.archive?.monthKey,
		      let next = Fmt.shiftMonth(key, by: delta) else { return }
		Task { await store.loadArchive(monthKey: next) }
	}

	/// Monat für den (vorläufigen) Titel, solange noch kein Archiv geladen ist.
	private var currentMonthKey: String {
		store.archive?.monthKey ?? Fmt.monthKey(.now)
	}

	private var subtitle: String {
		if let archive = store.archive {
			return "\(archive.eventCount) Einträge"
		}
		return "Monate mit Einträgen durchblättern"
	}

	private func monthTitle(_ monthKey: String) -> String {
		guard let d = Fmt.monthKeyFormatter.date(from: monthKey) else { return monthKey }
		let f = DateFormatter()
		f.locale = Locale(identifier: "de_DE")
		f.dateFormat = "MMMM yyyy"
		return f.string(from: d)
	}
}
