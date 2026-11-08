import Foundation
import Security

/// Minimales Keychain-Wrapper für Login-Zugangsdaten (App-Weiterlogin).
enum Keychain {
	private static let service = "de.hott.horizont"

	static func set(_ account: String, value: String) {
		let data = Data(value.utf8)
		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: account,
			// Moderne Keychain-API: keine ACL-Nachfragen, kein Blockieren bei gesperrtem Bildschirm.
			kSecUseDataProtectionKeychain as String: true
		]
		SecItemDelete(query as CFDictionary)
		var attributes = query
		attributes[kSecValueData as String] = data
		attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
		SecItemAdd(attributes as CFDictionary, nil)
	}

	static func get(_ account: String) -> String? {
		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: account,
			kSecReturnData as String: true,
			kSecMatchLimit as String: kSecMatchLimitOne,
			kSecUseDataProtectionKeychain as String: true
		]
		var out: AnyObject?
		guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
		      let data = out as? Data else { return nil }
		return String(data: data, encoding: .utf8)
	}

	static func delete(_ account: String) {
		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: account,
			kSecUseDataProtectionKeychain as String: true
		]
		SecItemDelete(query as CFDictionary)
	}
}
