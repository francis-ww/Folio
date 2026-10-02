import Foundation
import Security
import FolioCore

/// Keychain calls run on this actor, never on SwiftUI's main actor.
actor KeychainOnlineDictionarySettings: OnlineDictionarySettingsStore {
    private let service = "app.folio.dictionary.youdao"
    private let account = "online-configuration"

    func configuration() throws -> YoudaoConfiguration {
        var query = identity
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return .init() }
        guard status == errSecSuccess, let data = result as? Data else { throw KeychainSettingsError(status: status) }
        return try JSONDecoder().decode(YoudaoConfiguration.self, from: data)
    }

    func update(_ configuration: YoudaoConfiguration) throws {
        guard configuration.credentials != nil else {
            let status = SecItemDelete(identity as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainSettingsError(status: status) }
            return
        }
        let data = try JSONEncoder().encode(configuration)
        let changed = [kSecValueData as String: data] as [String: Any]
        let status = SecItemUpdate(identity as CFDictionary, changed as CFDictionary)
        if status == errSecItemNotFound {
            var item = identity
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw KeychainSettingsError(status: added) }
        } else if status != errSecSuccess { throw KeychainSettingsError(status: status) }
    }

    private var identity: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: account, kSecAttrSynchronizable as String: false]
    }
}

private struct KeychainSettingsError: LocalizedError, FolioMessageProviding {
    let status: OSStatus
    var errorDescription: String? { message.englishDescription }
    var message: FolioMessage { FolioMessage("Folio couldn’t access your saved online keys. Unlock your device and try again (%lld).", [.integer(Int(status))]) }
}
