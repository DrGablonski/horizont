import Foundation
import CryptoKit

/// Hält die zuletzt geladenen Antworten als JSON-Dateien im App-Ordner
/// (Application Support/Horizont/Snapshots). Beim nächsten Start sind sie
/// sofort da, noch bevor die erste Netzwerkantwort eintrifft — die App wirkt
/// damit augenblicklich geladen und aktualisiert sich im Hintergrund still.
/// Pro Server-URL eigene Dateien, damit ein Serverwechsel keine fremden
/// Daten anzeigt.
enum SnapshotStore {
	private static let encoder: JSONEncoder = {
		let e = JSONEncoder()
		e.dateEncodingStrategy = .iso8601
		return e
	}()

	private static let decoder: JSONDecoder = {
		let d = JSONDecoder()
		d.dateDecodingStrategy = .iso8601
		return d
	}()

	/// Erlaubt das Speichern im Sandbox-Ordner auch in Debug-Builds ohne
	/// Sandbox-Profil (plist nicht vorhanden) und in Release-Builds mit.
	/// `generation` (optional) hängt einen Fingerabdruck an den Dateinamen an —
	/// z. B. die Kalender-Sichtbarkeit, damit ein veralteter Snapshot nach dem
	/// Ein-/Ausblenden von Kalendern nicht mehr als aktuell gilt.
	private static func fileURL(named name: String, serverBase: String, generation: String) -> URL? {
		let fm = FileManager.default
		guard let base = try? fm.url(
			for: .applicationSupportDirectory, in: .userDomainMask,
			appropriateFor: nil, create: true) else { return nil }
		// Stabiler Hash der Server-URL (hashValue ist pro Prozess randomisiert!).
		let digest = SHA256.hash(data: Data(serverBase.utf8))
		let serverHash = digest.prefix(8).map { String(format: "%02x", $0) }.joined()
		let dir = base.appendingPathComponent("Horizont/Snapshots/\(serverHash)", isDirectory: true)
		do { try fm.createDirectory(at: dir, withIntermediateDirectories: true) } catch { return nil }
		let fileName = generation.isEmpty ? "\(name).json" : "\(name)~\(generation).json"
		return dir.appendingPathComponent(fileName)
	}

	static func load<T: Decodable>(_ type: T.Type, name: String, serverBase: String, generation: String = "") -> T? {
		guard let url = fileURL(named: name, serverBase: serverBase, generation: generation),
		      let data = try? Data(contentsOf: url) else { return nil }
		return try? decoder.decode(type, from: data)
	}

	static func save<T: Encodable>(_ value: T, name: String, serverBase: String, generation: String = "") {
		guard let url = fileURL(named: name, serverBase: serverBase, generation: generation),
		      let data = try? encoder.encode(value) else { return }
		try? data.write(to: url, options: .atomic)
	}
}
