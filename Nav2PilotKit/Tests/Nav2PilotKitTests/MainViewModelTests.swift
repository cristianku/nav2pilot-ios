import XCTest
@testable import Nav2PilotKit

@MainActor
final class MainViewModelTests: XCTestCase {
    private var http = FakeHttpClient()
    private var storage = InMemoryKeyValueStore()
    private var secrets = InMemorySecretStore()
    private var tokenStore: TokenStore!
    private var deviceRepository: DeviceRepository!
    private var favoritesRepository: FavoritesRepository!

    override func setUp() async throws {
        http = FakeHttpClient()
        storage = InMemoryKeyValueStore()
        secrets = InMemorySecretStore()
        tokenStore = TokenStore(secrets: secrets)
        deviceRepository = DeviceRepository(store: storage)
        favoritesRepository = FavoritesRepository(store: storage)
    }

    private func createViewModel(search: PlaceSearch = FakePlaceSearch()) -> MainViewModel {
        let store = tokenStore!
        let comma = CommaAthenaTransport(http: http, tokenProvider: {
            return store.load()
        })
        return MainViewModel(
            resolver: DestinationResolver(shortLinkResolver: ShortLinkResolver(http: http), placeSearch: search),
            placeSearch: search,
            transports: TransportRegistry(comma: comma, sunnylink: SunnylinkTransport()),
            tokenStore: tokenStore,
            favoritesRepository: favoritesRepository,
            deviceRepository: deviceRepository,
            now: { Date(timeIntervalSince1970: 1) }
        )
    }

    func testShareThenSendReportsConfirmation() async throws {
        try tokenStore.save(Fixtures.testJwt)
        deviceRepository.addManual(PairedDevice(dongleId: Fixtures.dongleId, alias: "Peugeot 3008"))
        http.respond(200, #"{"jsonrpc":"2.0","id":0,"result":{"version":"0.10.1","branch":"feature/nav-alpha","remote":"","commit":""}}"#)

        let viewModel = createViewModel()
        await viewModel.start()

        XCTAssertEqual(.online(DeviceStatus(version: "0.10.1", branch: "feature/nav-alpha", remote: "", commit: "")), viewModel.connection)
        XCTAssertEqual(1893456000, viewModel.tokenExpirySeconds)

        await viewModel.handleShare(text: "Duomo\n45.4642, 9.19", subject: "")
        XCTAssertEqual("Duomo", viewModel.destination?.name)
        XCTAssertEqual(1, viewModel.showSendTabRequest)

        http.respond(200, #"{"jsonrpc":"2.0","id":0,"result":{"success":1}}"#)
        await viewModel.sendDestination()

        XCTAssertEqual(true, viewModel.feedback?.success)
        XCTAssertEqual("Destination sent to Peugeot 3008.", viewModel.feedback?.message)
        XCTAssertFalse(viewModel.sending)
        XCTAssertEqual("setNavDestination", jsonObject(http.requests.last?.body)["method"] as? String)
    }

    func testWithoutTokenNothingIsSent() async {
        deviceRepository.addManual(PairedDevice(dongleId: Fixtures.dongleId, alias: "Car"))
        let viewModel = createViewModel()
        await viewModel.start()
        XCTAssertEqual(.unknown, viewModel.connection)

        await viewModel.handleShare(text: "45.1, 9.2", subject: "")
        await viewModel.sendDestination()

        XCTAssertEqual(false, viewModel.feedback?.success)
        XCTAssertTrue(http.requests.isEmpty)
    }

    func testRejectedTokenIsNotStored() async {
        let viewModel = createViewModel()
        http.respond(401, #"{"error":"unauthorized"}"#)

        await viewModel.saveToken(Fixtures.testJwt)

        XCTAssertFalse(tokenStore.hasToken())
        XCTAssertTrue(viewModel.accountMessage.hasPrefix("Token not saved."))
    }

    func testKeychainFailureIsReported() async {
        let viewModel = createViewModel()
        secrets.failWrite = true
        http.respond(200, #"{"email":"driver@example.com"}"#)

        await viewModel.saveToken(Fixtures.testJwt)

        XCTAssertFalse(viewModel.hasToken)
        XCTAssertTrue(viewModel.accountMessage.hasPrefix("Token not saved."))
    }

    func testAcceptedTokenIsStoredAndDevicesAreLoaded() async {
        let viewModel = createViewModel()
        viewModel.showTokenSheet()
        http.respond(200, #"{"email":"driver@example.com"}"#)
        http.respond(200, #"[{"dongle_id":"1a2b3c4d5e6f7a8b","alias":"Peugeot 3008","device_type":"three","last_athena_ping":1760700000,"is_owner":true}]"#)
        http.respond(200, #"{"jsonrpc":"2.0","id":0,"result":{"version":"0.10.1","branch":"b","remote":"","commit":""}}"#)

        await viewModel.saveToken("JWT " + Fixtures.testJwt)

        XCTAssertEqual(Fixtures.testJwt, tokenStore.load())
        XCTAssertTrue(viewModel.hasToken)
        XCTAssertFalse(viewModel.tokenSheetVisible)
        XCTAssertEqual("driver@example.com", viewModel.accountEmail)
        XCTAssertEqual(1, viewModel.devices.count)
        XCTAssertEqual(Fixtures.dongleId, viewModel.selectedDongleId)
        XCTAssertEqual(.online(DeviceStatus(version: "0.10.1", branch: "b", remote: "", commit: "")), viewModel.connection)
    }

    func testManualDeviceValidation() async {
        let viewModel = createViewModel()
        let invalid = await viewModel.addManualDevice(dongleIdText: "xyz", alias: "")
        XCTAssertFalse(invalid.isEmpty)
        let added = await viewModel.addManualDevice(dongleIdText: " 1A2B3C4D5E6F7A8B ", alias: "Car")
        XCTAssertEqual("", added)
        XCTAssertEqual("1a2b3c4d5e6f7a8b", viewModel.devices[0].dongleId)
        let duplicate = await viewModel.addManualDevice(dongleIdText: "1a2b3c4d5e6f7a8b", alias: "Again")
        XCTAssertFalse(duplicate.isEmpty)
    }

    func testFavoriteToggle() async {
        let viewModel = createViewModel()
        await viewModel.handleShare(text: "45.1, 9.2", subject: "")

        viewModel.toggleFavorite()
        XCTAssertEqual(1, viewModel.favorites.count)
        XCTAssertTrue(viewModel.isFavorite(viewModel.destination))

        viewModel.toggleFavorite()
        XCTAssertTrue(viewModel.favorites.isEmpty)
    }

    func testClearSelectionDropsALateResult() async {
        let search = GatedPlaceSearch()
        let viewModel = createViewModel(search: search)

        let pending = Task {
            await viewModel.search("Via Roma")
        }
        while !search.isWaiting() {
            await Task.yield()
        }
        // the user clears while the search is still running
        viewModel.clearSelection()
        search.finish()
        await pending.value

        XCTAssertNil(viewModel.destination)
        XCTAssertFalse(viewModel.resolving)
    }
}

/// A search that does not return until finish() is called.
private final class GatedPlaceSearch: PlaceSearch {
    private var continuation: CheckedContinuation<Void, Never>?

    func isAvailable() -> Bool {
        return true
    }

    func isWaiting() -> Bool {
        return continuation != nil
    }

    func finish() {
        continuation?.resume()
        continuation = nil
    }

    @MainActor
    func search(_ query: String, maxResults: Int) async throws -> [Destination] {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
        return [Destination(latitude: 45.1, longitude: 9.2, name: "Late")]
    }
}
