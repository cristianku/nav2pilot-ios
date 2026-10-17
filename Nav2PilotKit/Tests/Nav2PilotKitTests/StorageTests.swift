import XCTest
@testable import Nav2PilotKit

final class RepositoriesTests: XCTestCase {
    private var storage = InMemoryKeyValueStore()

    override func setUp() {
        super.setUp()
        storage = InMemoryKeyValueStore()
    }

    func testFavoritesPersistAndDeduplicate() {
        let repository = FavoritesRepository(store: storage)
        let home = Destination(latitude: 45.4642, longitude: 9.19, name: "Home", details: "Milano")

        let first = repository.add(home)
        var samePlace = home
        samePlace.name = "Same place"
        let second = repository.add(samePlace)

        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(1, repository.favorites.count)

        let reloaded = FavoritesRepository(store: storage)
        XCTAssertEqual([first], reloaded.favorites)

        reloaded.remove(first.id)
        XCTAssertTrue(reloaded.favorites.isEmpty)
        XCTAssertNil(reloaded.findByLocation(home))
    }

    func testCorruptedFavoritesAreIgnored() {
        storage.values[FavoritesRepository.keyFavorites] = "not json"
        XCTAssertTrue(FavoritesRepository(store: storage).favorites.isEmpty)
    }

    func testAccountRefreshKeepsManualDevices() {
        let repository = DeviceRepository(store: storage)
        let manual = PairedDevice(dongleId: "aaaaaaaaaaaaaaaa", alias: "Borrowed", addedManually: true)
        XCTAssertTrue(repository.addManual(manual))
        XCTAssertFalse(repository.addManual(manual))
        XCTAssertEqual("aaaaaaaaaaaaaaaa", repository.selectedDongleId)

        let accountDevice = PairedDevice(dongleId: "1a2b3c4d5e6f7a8b", alias: "Peugeot 3008", deviceType: "three", lastAthenaPingSeconds: 1760700000)
        repository.replaceAccountDevices([accountDevice])

        XCTAssertEqual([accountDevice, manual], repository.devices)
        XCTAssertEqual("aaaaaaaaaaaaaaaa", repository.selectedDongleId)

        // the account now also lists the manual device: it becomes an account device, no duplicate
        repository.replaceAccountDevices([accountDevice, PairedDevice(dongleId: "aaaaaaaaaaaaaaaa", alias: "Now owned")])
        XCTAssertEqual(2, repository.devices.count)
        XCTAssertFalse(repository.devices[1].addedManually)
    }

    func testSelectionFollowsRemovalAndSurvivesRestart() {
        let repository = DeviceRepository(store: storage)
        repository.replaceAccountDevices([
            PairedDevice(dongleId: "1111111111111111", alias: "A"),
            PairedDevice(dongleId: "2222222222222222", alias: "B"),
        ])
        repository.select("2222222222222222")
        XCTAssertEqual("B", repository.selectedDevice()?.alias)

        let reloaded = DeviceRepository(store: storage)
        XCTAssertEqual("2222222222222222", reloaded.selectedDongleId)

        reloaded.remove("2222222222222222")
        XCTAssertEqual("1111111111111111", reloaded.selectedDongleId)

        reloaded.select("9999999999999999")
        XCTAssertEqual("1111111111111111", reloaded.selectedDongleId)

        reloaded.remove("1111111111111111")
        XCTAssertEqual("", reloaded.selectedDongleId)
        XCTAssertNil(reloaded.selectedDevice())
    }

    func testChangesFromTheOtherProcessAreSeenAfterReload() {
        // the app and the share extension each have their own repository on the same App Group storage
        let app = DeviceRepository(store: storage)
        let shareExtension = DeviceRepository(store: storage)
        app.addManual(PairedDevice(dongleId: "1a2b3c4d5e6f7a8b", alias: "Car"))

        XCTAssertTrue(shareExtension.devices.isEmpty)
        shareExtension.reload()
        XCTAssertEqual("1a2b3c4d5e6f7a8b", shareExtension.selectedDongleId)
    }

    func testDeviceJsonRoundTrip() {
        let devices = [
            PairedDevice(dongleId: "1a2b3c4d5e6f7a8b", alias: "Car", deviceType: "three", lastAthenaPingSeconds: 42, isOwner: false, backend: .sunnylink, addedManually: true),
        ]
        XCTAssertEqual(devices, JsonCodec.devicesFromJson(JsonCodec.devicesToJson(devices)))
    }

    func testAndroidJsonFormatIsReadable() {
        // what the Android app stores, so the format stays the same on both platforms
        let text = #"[{"dongle_id":"1a2b3c4d5e6f7a8b","alias":"Car","device_type":"three","last_athena_ping":42,"is_owner":true,"backend":"comma_athena","added_manually":false}]"#
        XCTAssertEqual([PairedDevice(dongleId: "1a2b3c4d5e6f7a8b", alias: "Car", deviceType: "three", lastAthenaPingSeconds: 42)], JsonCodec.devicesFromJson(text))
    }
}

final class TokenStoreTests: XCTestCase {
    private var secrets = InMemorySecretStore()
    private var tokenStore: TokenStore!

    override func setUp() {
        super.setUp()
        secrets = InMemorySecretStore()
        tokenStore = TokenStore(secrets: secrets)
    }

    func testSavesTheNormalizedToken() throws {
        try tokenStore.save("  JWT " + Fixtures.testJwt + "\n")

        XCTAssertEqual(Fixtures.testJwt, secrets.values[TokenStore.keyCommaToken])
        XCTAssertEqual(Fixtures.testJwt, tokenStore.load())
        XCTAssertTrue(tokenStore.hasToken())
    }

    func testNormalizesPastedHeaderValues() {
        XCTAssertEqual("abc.def.ghi", TokenStore.normalize("  JWT abc.def.ghi \n"))
        XCTAssertEqual("abc.def.ghi", TokenStore.normalize("Bearer abc.def.ghi"))
        XCTAssertEqual("abc.def.ghi", TokenStore.normalize("abc.def.ghi"))
    }

    func testClearRemovesTheToken() throws {
        try tokenStore.save(Fixtures.testJwt)
        tokenStore.clear()
        XCTAssertNil(tokenStore.load())
        XCTAssertFalse(tokenStore.hasToken())
    }

    func testJwtExpiryIsRead() {
        XCTAssertTrue(JwtInfo.looksLikeJwt(Fixtures.testJwt))
        XCTAssertEqual(1893456000, JwtInfo.expirySeconds(Fixtures.testJwt))
    }

    func testNotAJwt() {
        XCTAssertFalse(JwtInfo.looksLikeJwt("abc"))
        XCTAssertFalse(JwtInfo.looksLikeJwt("a..c"))
        XCTAssertFalse(JwtInfo.looksLikeJwt("a.b c.d"))
        XCTAssertNil(JwtInfo.expirySeconds("a.b.c"))
        // payload without exp
        XCTAssertNil(JwtInfo.expirySeconds("eyJhbGciOiJub25lIn0.eyJpZGVudGl0eSI6InRlc3QifQ.c2ln"))
    }
}

