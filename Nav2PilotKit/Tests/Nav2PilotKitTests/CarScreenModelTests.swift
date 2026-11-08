import XCTest
@testable import Nav2PilotKit

@MainActor
final class CarScreenModelTests: XCTestCase {
    private var http = FakeHttpClient()
    private var storage = InMemoryKeyValueStore()
    private var secrets = InMemorySecretStore()
    private var tokenStore: TokenStore!
    private var mapboxTokenStore: TokenStore!
    private var deviceRepository: DeviceRepository!
    private var favoritesRepository: FavoritesRepository!

    override func setUp() async throws {
        http = FakeHttpClient()
        storage = InMemoryKeyValueStore()
        secrets = InMemorySecretStore()
        tokenStore = TokenStore(secrets: secrets)
        mapboxTokenStore = TokenStore(secrets: secrets, key: TokenStore.keyMapboxToken)
        deviceRepository = DeviceRepository(store: storage)
        favoritesRepository = FavoritesRepository(store: storage)
    }

    private func createModel() -> CarScreenModel {
        let store = tokenStore!
        let comma = CommaAthenaTransport(http: http, tokenProvider: {
            return store.load()
        })
        return CarScreenModel(
            tokenStore: tokenStore,
            deviceRepository: deviceRepository,
            favoritesRepository: favoritesRepository,
            transports: TransportRegistry(comma: comma, sunnylink: SunnylinkTransport()),
            mapboxTokenStore: mapboxTokenStore,
            placeInfoLookup: PlaceInfoLookup(http: http, endpoints: { _ in ["https://overpass.example/api/interpreter"] })
        )
    }

    func testSetupMessageSaysWhatIsMissing() throws {
        let model = createModel()
        XCTAssertEqual("No comma account in Nav2Pilot yet.", model.setupMessage())

        try tokenStore.save(Fixtures.testJwt)
        XCTAssertEqual("No car in Nav2Pilot yet.", model.setupMessage())

        // added by the app: the CarPlay screen reads it again
        DeviceRepository(store: storage).addManual(PairedDevice(dongleId: Fixtures.dongleId, alias: "Peugeot 3008"))
        model.reload()
        XCTAssertNil(model.setupMessage())
        XCTAssertEqual("Peugeot 3008", model.selectedDevice()?.alias)
    }

    func testNearestFavoritesComeFirst() {
        let verona = Favorite(id: "verona", destination: Destination(latitude: 45.4384, longitude: 10.9916, name: "Arena"))
        let milano = Favorite(id: "milano", destination: Destination(latitude: 45.4642, longitude: 9.19, name: "Duomo"))
        let here = LatLng(latitude: 45.47, longitude: 9.18)

        XCTAssertEqual(["milano", "verona"], CarScreenModel.nearestFirst([verona, milano], from: here, limit: 12).map { $0.id })
        XCTAssertEqual(["verona", "milano"], CarScreenModel.nearestFirst([verona, milano], from: nil, limit: 12).map { $0.id })
        XCTAssertEqual(["milano"], CarScreenModel.nearestFirst([verona, milano], from: here, limit: 1).map { $0.id })
        XCTAssertEqual(1012, CarScreenModel.distanceMeters(milano, from: here), accuracy: 5)
    }

    func testFavoritePlacesSayWhetherTheyAreOpen() async throws {
        let ikea = Favorite(
            id: "ikea",
            destination: Destination(latitude: 47.5302, longitude: 7.7012, name: "IKEA", details: "Pratteln", kind: "shop:yes")
        )
        let home = Favorite(
            id: "home",
            destination: Destination(latitude: 47.5076, longitude: 8.0148, name: "Home", details: "Hauptstrasse 1, Frick")
        )
        http.respond(200, #"{"elements": [{"type": "way", "id": 26343678, "center": {"lat": 47.5300, "lon": 7.7010}, "tags": {"name": "IKEA", "opening_hours": "Mo-Sa 10:00-20:00"}}]}"#)
        let model = createModel()

        let arrived = await model.lookUpInfo([ikea, home])

        XCTAssertTrue(arrived)
        // only the store goes to OpenStreetMap, never the address
        XCTAssertEqual(1, http.requests.count)
        let query = (http.requests[0].body ?? "").removingPercentEncoding ?? ""
        XCTAssertTrue(query.contains("IKEA"), query)
        XCTAssertFalse(query.contains("Home"), query)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Zurich")!
        // Monday 9 November 2026
        let morning = calendar.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 12))!
        let evening = calendar.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 21))!
        let swiss = Locale(identifier: "de_CH")
        XCTAssertEqual("Open · Closes 20:00", model.openStatus(of: ikea, at: morning, calendar: calendar, locale: swiss))
        XCTAssertEqual("Closed · Opens tomorrow 10:00", model.openStatus(of: ikea, at: evening, calendar: calendar, locale: swiss))
        XCTAssertNil(model.openStatus(of: home, at: morning, calendar: calendar, locale: swiss))

        // known now: the next time the map is drawn asks nothing
        let again = await model.lookUpInfo([ikea, home])
        XCTAssertFalse(again)
        XCTAssertEqual(1, http.requests.count)
    }

    func testSendGoesWithTheMapboxTokenFirst() async throws {
        try tokenStore.save(Fixtures.testJwt)
        try mapboxTokenStore.save("pk.a.b")
        deviceRepository.addManual(PairedDevice(dongleId: Fixtures.dongleId, alias: "Peugeot 3008"))
        http.respond(200, #"{"jsonrpc":"2.0","id":0,"result":{"success":1}}"#)
        http.respond(200, #"{"jsonrpc":"2.0","id":0,"result":{"success":1}}"#)

        let outcome = await createModel().send(Destination(latitude: 45.4642, longitude: 9.19, name: "Duomo"))

        XCTAssertEqual(SendOutcome(success: true, message: "Destination sent to Peugeot 3008."), outcome)
        XCTAssertEqual("setMapboxToken", jsonObject(http.requests[0].body)["method"] as? String)
        XCTAssertEqual("setNavDestination", jsonObject(http.requests[1].body)["method"] as? String)
    }

    func testStatusAndClear() async throws {
        try tokenStore.save(Fixtures.testJwt)
        deviceRepository.addManual(PairedDevice(dongleId: Fixtures.dongleId, alias: "Peugeot 3008"))
        let model = createModel()

        http.respond(200, #"{"jsonrpc":"2.0","id":0,"result":{"version":"0.10.1","branch":"nav-alpha","remote":"","commit":""}}"#)
        let status = await model.status(of: model.devices[0])
        XCTAssertEqual("Online · 0.10.1 (nav-alpha)", status)

        http.respond(200, #"{"jsonrpc":"2.0","id":0,"result":{"success":1}}"#)
        let cleared = await model.clearDestination()
        XCTAssertEqual(SendOutcome(success: true, message: "Destination cleared on Peugeot 3008."), cleared)
        XCTAssertEqual("clearNavDestination", jsonObject(http.requests.last?.body)["method"] as? String)
    }

    func testFailedSendSaysWhy() async throws {
        try tokenStore.save(Fixtures.testJwt)
        deviceRepository.addManual(PairedDevice(dongleId: Fixtures.dongleId, alias: "Peugeot 3008"))
        http.respond(401, #"{"error":"unauthorized"}"#)

        let outcome = await createModel().send(Destination(latitude: 45.4642, longitude: 9.19))

        XCTAssertFalse(outcome.success)
        XCTAssertTrue(outcome.message.contains("401"), outcome.message)
    }
}
