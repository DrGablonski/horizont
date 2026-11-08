import SwiftUI

/// Archiv: Monatsgrid (Mo–So) wie im Web; Tap auf einen Tag zeigt die Einträge.
struct ArchiveView: View {
	@Environment(AppStore.self) private var store
	@State private var selectedDay: String?

	var body: some View {
		VStack(spacing: 0) {
			SectionHeader("Archiv", subtitle: store.archive.map { monthTitle($0.monthKey) } ?? "Monate mit Einträgen durchblättern")

			ScrollView {
				VStack(alignment: .leading, spacing: DS.Space.lg) {
					if let err = store.archiveError {
						ErrorBanner(message: err, retry: {
							Task { await store.loadArchive(monthKey: store.archive?.monthKey) }
						})
					}

					if store.archiveBusy && store.archive == nil {
						TimelineSkeleton()
					} else if let archive = store.archive {
						monthCard(archive)
						if let dayKey = selectedDay {
							dayCard(archive: archive, dayKey: dayKey)
						}
					} else if !store.archiveBusy {
						EmptyStateView(
							title: "Archiv nicht verfügbar",
							systemImage: "tray.and.arrow.down",
							description: store.archiveError ?? "Server nicht erreichbar.")
							.frame(minHeight: 320)
							.frame(maxWidth: .infinity)
					}
				}
				.padding(DS.Space.xl)
				.frame(maxWidth: 720, alignment: .leading)
				.frame(maxWidth: .infinity, alignment: .top)
			}
			.refreshable { await store.loadArchive(monthKey: store.archive?.monthKey) }
		}
		.task {
			if store.archive == nil { await store.loadArchive() }
		}
	}

	// MARK: – Monatskarte

	@ViewBuilder
	private func monthCard(_ archive: ArchiveMonth) -> some View {
		VStack(spacing: DS.Space.md) {
			// Zähler rechts oben
			HStack {
				Spacer(minLength: 0)
				Chip(text: "\(archive.eventCount) Einträge", color: DS.textSecondary)
			}

			// Monatsnavigation: Pfeile links/rechts, Titel Mitte
			HStack(spacing: DS.Space.sm) {
				Button {
					if let prev = Fmt.shiftMonth(archive.monthKey, by: -1) {
						selectedDay = nil
						Task { await store.loadArchive(monthKey: prev) }
					}
				} label: {
					Image(systemName: "chevron.left")
				}
				.ghostButton()
				.disabled(!archive.canPrev)

				Spacer(minLength: DS.Space.sm)
				Text(monthTitle(archive.monthKey))
					.font(.title3.weight(.semibold))
					.foregroundStyle(DS.textPrimary)
					.contentTransition(.numericText())
				Spacer(minLength: DS.Space.sm)

				Button {
					if let next = Fmt.shiftMonth(archive.monthKey, by: 1) {
						selectedDay = nil
						Task { await store.loadArchive(monthKey: next) }
					}
				} label: {
					Image(systemName: "chevron.right")
				}
				.ghostButton()
				.disabled(!archive.canNext)
			}

			// Monatsraster (Mo–So)
			let lookup = archive.days.reduce(into: [String: DayGroup]()) { $0[$1.dayKey] = $1 }
			let todayKey = Fmt.dayKeyFormatter.string(from: .now)
			LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: DS.Space.xs) {
				ForEach(Fmt.weekdayHeaders, id: \.self) { h in
					Text(h)
						.font(DS.Typo.metaStrong)
						.foregroundStyle(DS.textSecondary)
						.frame(maxWidth: .infinity)
				}
				ForEach(gridCells(archive.monthKey), id: \.self) { cell in
					if let dayKey = cell {
						DayCellView(
							dayText: dayOfMonth(dayKey),
							isToday: dayKey == todayKey,
							hasEvents: (lookup[dayKey]?.events.count ?? 0) > 0,
							isSelected: selectedDay == dayKey
						) {
							selectedDay = (selectedDay == dayKey) ? nil : dayKey
						}
					} else {
						Color.clear.frame(height: 42)
					}
				}
			}
			.animation(.easeInOut, value: archive.monthKey)
		}
		.padding(DS.Space.lg)
		.dsCard()
	}

	// MARK: – Tagesdetail

	@ViewBuilder
	private func dayCard(archive: ArchiveMonth, dayKey: String) -> some View {
		let day = archive.days.first { $0.dayKey == dayKey }
		VStack(alignment: .leading, spacing: DS.Space.md) {
			Text(day?.label ?? dayLabel(dayKey))
				.font(DS.Typo.cardTitle)
				.foregroundStyle(DS.textPrimary)

			if let events = day?.events, !events.isEmpty {
				VStack(spacing: DS.Space.xs) {
					ForEach(events) { event in
						HoverableEventRow(event: event)
					}
				}
			} else {
				Text("Keine Einträge an diesem Tag.")
					.font(DS.Typo.meta)
					.foregroundStyle(DS.textTertiary)
			}
		}
		.padding(DS.Space.lg)
		.frame(maxWidth: .infinity, alignment: .leading)
		.dsCard()
	}

	// MARK: – Raster-Helfer

	/// Zellen des Monats: nil = leer (Versatz vor Monatsbeginn).
	private func gridCells(_ monthKey: String) -> [String?] {
		guard let first = Fmt.monthKeyFormatter.date(from: monthKey) else { return [] }
		let cal = Calendar(identifier: .gregorian)
		let comps = cal.dateComponents([.year, .month], from: first)
		guard let range = cal.range(of: .day, in: .month, for: first) else { return [] }
		// Versatz: Mo=0 … So=6
		let weekday = cal.component(.weekday, from: first)   // So=1 … Sa=7
		let leading = (weekday + 5) % 7
		var cells: [String?] = Array(repeating: nil, count: leading)
		for day in range {
			let d = cal.date(byAdding: .day, value: day - 1, to: cal.date(from: comps) ?? first)
			cells.append(d.map { Fmt.dayKeyFormatter.string(from: $0) })
		}
		return cells
	}

	private func dayOfMonth(_ dayKey: String) -> String {
		String(dayKey.suffix(2))
	}

	private func monthTitle(_ monthKey: String) -> String {
		guard let d = Fmt.monthKeyFormatter.date(from: monthKey) else { return monthKey }
		let f = DateFormatter()
		f.locale = Locale(identifier: "de_DE")
		f.dateFormat = "MMMM yyyy"
		return f.string(from: d)
	}

	private func dayLabel(_ dayKey: String) -> String {
		guard let d = Fmt.dayKey(dayKey) else { return dayKey }
		let f = DateFormatter()
		f.locale = Locale(identifier: "de_DE")
		f.dateFormat = "EEEE, d. MMMM yyyy"
		return f.string(from: d)
	}
}

// MARK: – Tageszelle

/// Kreiszelle im Kalender: Zahl, Eintrag-Punkt, Heute-Ring, Auswahl-Füllung, Hover.
private struct DayCellView: View {
	let dayText: String
	let isToday: Bool
	let hasEvents: Bool
	let isSelected: Bool
	let onSelect: () -> Void

	@State private var hovering = false

	var body: some View {
		Button(action: onSelect) {
			VStack(spacing: 3) {
				Text(dayText)
					.font(.callout.weight(isToday ? .semibold : .regular).monospacedDigit())
					.foregroundStyle(isSelected ? .white : DS.textPrimary)
					.frame(height: 17)
				Circle()
					.fill(isSelected ? AnyShapeStyle(.white)
						: hasEvents ? AnyShapeStyle(DS.accent)
						: AnyShapeStyle(Color.clear))
					.frame(width: 5, height: 5)
			}
			.frame(width: 42, height: 42)
			.background(
				Circle().fill(isSelected
				              ? AnyShapeStyle(DS.accent)
				              : AnyShapeStyle(Color.primary.opacity(hovering ? 0.07 : 0)))
			)
			.overlay(
				Circle().strokeBorder(
					isToday && !isSelected ? DS.accent : Color.clear,
					lineWidth: 1.5)
			)
			.contentShape(Circle())
			.onHover { hovering = $0 }
		}
		.buttonStyle(.plain)
		.animation(.easeOut(duration: 0.12), value: hovering)
	}
}

// MARK: – Event-Zeile mit Hover-Aufhellung

/// Archiv-Event mit dezenter Hover-Aufhellung; Abhaken von Aufgaben wie in der Timeline.
private struct HoverableEventRow: View {
	let event: EventItem

	@Environment(AppStore.self) private var store
	@State private var hovering = false

	var body: some View {
		EventRowView(event: event) {
			await store.toggleTask(event)
		}
		.padding(.horizontal, DS.Space.sm)
		.padding(.vertical, DS.Space.xs)
		.background(
			RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
				.fill(Color.primary.opacity(hovering ? 0.05 : 0))
		)
		.contentShape(Rectangle())
		.onHover { hovering = $0 }
		.animation(.easeOut(duration: 0.12), value: hovering)
	}
}
