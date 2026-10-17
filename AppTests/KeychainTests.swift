import Nav2PilotKit
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

    func testAppGroupStorageIsUsable() {
        let defaults = UserDefaults(suiteName: AppContainer.appGroupIdentifier)
        XCTAssertNotNil(defaults)
        defaults?.set("value", forKey: "nav2pilot.tests")
        XCTAssertEqual("value", defaults?.string(forKey: "nav2pilot.tests"))
        defaults?.removeObject(forKey: "nav2pilot.tests")
    }
}
