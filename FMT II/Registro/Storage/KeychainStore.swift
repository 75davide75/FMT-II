import Foundation
import Security

/// Archivio Keychain per credenziali e token del registro.
/// Elementi generic password, accessibili dopo il primo sblocco, solo su questo dispositivo,
/// mai sincronizzati (nessun iCloud Keychain). I valori non vengono mai loggati.
struct KeychainStore {
    let service: String

    init(service: String = "com.davide.fmtII.registro") {
        self.service = service
    }

    enum KeychainError: Error, Equatable {
        case status(OSStatus)
    }

    private func baseQuery(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrSynchronizable as String: false,
        ]
    }

    func set(_ data: Data, for key: String) throws {
        let update = SecItemUpdate(baseQuery(key) as CFDictionary,
                                   [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw KeychainError.status(update) }
        var item = baseQuery(key)
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let add = SecItemAdd(item as CFDictionary, nil)
        guard add == errSecSuccess else { throw KeychainError.status(add) }
    }

    func data(for key: String) -> Data? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    func remove(_ key: String) {
        SecItemDelete(baseQuery(key) as CFDictionary)
    }
}
