import SwiftUI

/// Archiv: Monatsgrid (Mo–So) wie im Web; Tap auf einen Tag zeigt die Einträge.
struct ArchiveView: View {
	@Environment(AppStore.self) private var store
	@State private var selectedDay: String?

	var body: some View {
		NavigationStack {
			Group {
				if store.archiveBusy && store.archive == nil {
					ProgressView("Lade Archiv …")
						.frame(maxWidth: .infinity, maxHeight: .infinity)
				} else if let archive = store.archive {
					content(archive)
				} else {
					ContentUnavailableView(
						"Archiv nicht verfügbar",
						systemImage: "tray.and.arrow.down",
						description: Text(store.archiveError ?? "Server nicht erreichbar."))
				}
			}
			.navigationTitle("Archiv")
			.task {
				if store.archive == nil { await store.loadArchive() }
			}
		}
	}

	@ViewBuilder
	private func content(_ archive: ArchiveMonth) -> some View {
		VStack(alignment: .leading, spacing: 14) {
			// Monat kopple + Blättern
			HStack {
				Button {
					if let prev = Fmt.shiftMonth(archive.monthKey, by: -1) {
						selectedDay = nil
						Task { await store.loadArchive(monthKey: prev) }
					}
				} label: { Image(systemName: "chevron.left") }
				.disabled(!archive.canPrev)

				Text(monthTitle(archive.monthKey))
					.font(.title3.weight(.semibold))

				Button {
					if let next = Fmt.shiftMonth(archive.monthKey, by: 1) {
						selectedDay = nil
						Task { await store.loadArchive(monthKey: next) }
					}
				} label: { Image(systemName: "chevron.right") }
				.disabled(!archive.canNext)

				Spacer()
				Text("\(archive.eventCount) Einträge")
					.font(.callout)
					.foregroundStyle(.secondary)
			}

			// Monatsraster
			let lookup = Dictionary(uniqueKeysWithValues: archive.days.map { ($0.dayKey, $0) })
			LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
				ForEach(Fmt.weekdayHeaders, id: \.self) { h in
					Text(h)
						.font(.caption.weight(.semibold))
						.foregroundStyle(.secondary)
				}
				ForEach(gridCells(archive.monthKey), id: \.self) { cell in
					if let dayKey = cell {
						let day = lookup[dayKey]
						let count = day?.events.count ?? 0
						Button {
							selectedDay = (selectedDay == dayKey && count > 0) ? nil : (count > 0 ? dayKey : nil)
						} label: {
							VStack(spacing: 3) {
								Text("\(dayOfMonth(dayKey))")
									.font(.callout.monospacedDigit())
								Circle()
									.fill(count > 0 ? Color.accentColor : Color.clear)
									.frame(width: 5, height: 5)
							}
							.padding(6)
							.frame(maxWidth: .infinity)
							.background(
								RoundedRectangle(cornerRadius: 8)
									.fill(selectedDay == dayKey ? Color.accentColor.opacity(0.22) : Color.clear)
							)
						}
						.buttonStyle(.plain)
					} else {
						Color.clear.frame(height: 34)
					}
				}
			}

			// Tagesdetails
			if let dayKey = selectedDay, let day = lookup[dayKey] {
				Divider()
				Text(day.label).font(.headline)
				List(day.events) { event in
					EventRowView(event: event) {}
				}
			}

			if let err = store.archiveError {
				Text(err).font(.callout).foregroundStyle(.red)
			}
			Spacer()
		}
		.padding()
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
}
