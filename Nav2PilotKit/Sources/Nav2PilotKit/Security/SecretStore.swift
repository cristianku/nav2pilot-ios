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
/// - kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly: readable once the iPhone has been unlocked after it
///   was turned on, also while it is locked again (CarPlay runs with the iPhone locked in the car); never
///   synced to iCloud Keychain and never restored to another phone from a backup. Items written by older
///   versions (readable only while unlocked) are moved to it the first time they are read.
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
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status != errSecSuccess {
            return nil
        }
        guard let attributes = item as? [String: Any], let data = attributes[kSecValueData as String] as? Data else {
            return nil
        }
        if let accessible = attributes[kSecAttrAccessible as String] as? String, accessible != KeychainSecretStore.accessibility as String {
            let update: [String: Any] = [kSecAttrAccessible as String: KeychainSecretStore.accessibility]
            SecItemUpdate(baseQuery(key) as CFDictionary, update as CFDictionary)
        }
        return String(data: data, encoding: .utf8)
    }

    public func write(_ key: String, _ value: String) throws {
        delete(key)
        var attributes = baseQuery(key)
        attributes[kSecValueData as String] = Data(value.utf8)
        attributes[kSecAttrAccessible as String] = KeychainSecretStore.accessibility
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status != errSecSuccess {
            throw KeychainError(status: status)
        }
    }

    public func delete(_ key: String) {
        SecItemDelete(baseQuery(key) as CFDictionary)
    }

    /// How readable the items are; see the type's documentation.
    public static let accessibility = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

    private func baseQuery(_ key: String) -> [String: Any] {
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrSynchronizable as String: false,
        ]
    }
}
