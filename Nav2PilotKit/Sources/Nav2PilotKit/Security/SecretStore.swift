import Foundation
import Security

/// Storage for secrets, so TokenStore can be unit tested without the Keychain.
public protocol SecretStore: AnyObject {
    func read(_ key: String) -> String?
    func write(_ key: String, _ value: String) throws
    func delete(_ key: String)
}

public struct KeychainError: Error, LocalizedError, Equatable {
    public let status: OSStatus

    public var errorDescription: String? {
        return "Keychain error \(status)"
    }
}

/// Generic password items in the iOS Keychain.
///
/// - kSecAttrAccessibleWhenUnlockedThisDeviceOnly: readable only while the phone is unlocked, never
///   synced to iCloud Keychain and never restored to another phone from a backup.
/// - No explicit access group: the item goes to the first group of the keychain-access-groups
///   entitlement, which the app and the share extension have in common, so both can read the token.
public final class KeychainSecretStore: SecretStore {
    private let service: String

    public init(service: String) {
        self.service = service
    }

    public func read(_ key: String) -> String? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status != errSecSuccess {
            return nil
        }
        guard let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    public func write(_ key: String, _ value: String) throws {
        delete(key)
        var attributes = baseQuery(key)
        attributes[kSecValueData as String] = Data(value.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status != errSecSuccess {
            throw KeychainError(status: status)
        }
    }

    public func delete(_ key: String) {
        SecItemDelete(baseQuery(key) as CFDictionary)
    }

    private func baseQuery(_ key: String) -> [String: Any] {
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrSynchronizable as String: false,
        ]
    }
}
