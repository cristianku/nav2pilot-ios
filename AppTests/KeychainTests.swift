import Nav2PilotKit
import Security
import XCTest

/// Runs inside the app process, so the Keychain sees the app's entitlements (keychain-access-groups).
final class KeychainTests: XCTestCase {
    func testWriteReadReplaceDelete() throws {
        let store = KeychainSecretStore(service: "com.cristianku.nav2pilot.tests")
        store.delete("token")
        XCTAssertNil(store.read("token"))

        try store.write("token", "first.jwt.value")
        XCTAssertEqual("first.jwt.value", store.read("token"))

        try store.write("token", "second.jwt.value")
        XCTAssertEqual("second.jwt.value", store.read("token"))

        store.delete("token")
        XCTAssertNil(store.read("token"))
    }

    func testItemsStayReadableWithTheIPhoneLocked() throws {
        let store = KeychainSecretStore(service: KeychainTests.service)
        try store.write("token", "value.jwt")
        XCTAssertEqual(kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String, accessibility("token"))
        store.delete("token")
    }

    func testItemsOfOlderVersionsMoveToTheNewAccessibility() {
        // as written up to 1.0.x: readable only while the iPhone is unlocked, so not in CarPlay
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainTests.service,
            kSecAttrAccount as String: "old",
            kSecAttrSynchronizable as String: false,
        ]
        SecItemDelete(query as CFDictionary)
        var old = query
        old[kSecValueData as String] = Data("old.jwt".utf8)
        old[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        XCTAssertEqual(errSecSuccess, SecItemAdd(old as CFDictionary, nil))

        let store = KeychainSecretStore(service: KeychainTests.service)
        XCTAssertEqual("old.jwt", store.read("old"))
        XCTAssertEqual(kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String, accessibility("old"))
        store.delete("old")
    }

    private static let service = "com.cristianku.nav2pilot.tests"

    private func accessibility(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainTests.service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) != errSecSuccess {
            return nil
        }
        let attributes = item as? [String: Any]
        return attributes?[kSecAttrAccessible as String] as? String
    }

    func testAppGroupStorageIsUsable() {
        let defaults = UserDefaults(suiteName: AppContainer.appGroupIdentifier)
        XCTAssertNotNil(defaults)
        defaults?.set("value", forKey: "nav2pilot.tests")
        XCTAssertEqual("value", defaults?.string(forKey: "nav2pilot.tests"))
        defaults?.removeObject(forKey: "nav2pilot.tests")
    }
}
