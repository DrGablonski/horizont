import SwiftUI

/// Farben & Formatierung, passend zum Web-UI.

extension Color {
	/// #rrggbb (wie CalDAV-Kalenderfarben), sonst neutral.
	init(hex: String?) {
		guard let hex else { self = Color(nsColor: .secondaryLabel); return }
		var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
		if s.hasPrefix("#") { s.removeFirst() }
		guard s.count == 6, let v = Int(s, radix: 16) else {
			self = Color(nsColor: .secondaryLabel)
			return
		}
		self = Color(
			red: Double((v >> 16) & 0xFF) / 255,
			green: Double((v >> 8) & 0xFF) / 255,
			blue: Double(v & 0xFF) / 255)
	}
}

enum Fmt {
	/// Epoch-ms → "HH:mm" (lokal).
	static func time(_ ms: Int) -> String {
		timeFormatter.string(from: Date(timeIntervalSince1970: Double(ms) / 1000))
	}

	/// YYYY-MM-DD → Date (Mitternacht lokal), nil bei ungültig.
	static func dayKey(_ key: String) -> Date? {
		dayKeyFormatter.date(from: key)
	}

	static func monthKey(_ date: Date) -> String {
		monthKeyFormatter.string(from: date)
	}

	static func shiftMonth(_ monthKey: String, by months: Int) -> String? {
		guard let d = monthKeyFormatter.date(from: monthKey),
		      let shifted = Calendar.current.date(byAdding: .month, value: months, to: d)
		else { return nil }
		return monthKeyFormatter.string(from: shifted)
	}

	private static let timeFormatter: DateFormatter = {
		let f = DateFormatter()
		f.locale = Locale(identifier: "de_DE")
		f.dateFormat = "HH:mm"
		return f
	}()

	static let dayKeyFormatter: DateFormatter = {
		let f = DateFormatter()
		f.locale = Locale(identifier: "de_DE")
		f.timeZone = .current
		f.dateFormat = "yyyy-MM-dd"
		return f
	}()

	static let monthKeyFormatter: DateFormatter = {
		let f = DateFormatter()
		f.locale = Locale(identifier: "de_DE")
		f.timeZone = .current
		f.dateFormat = "yyyy-MM"
		return f
	}()

	/// Mo–So-Wochentag-Header.
	static let weekdayHeaders = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]
}
