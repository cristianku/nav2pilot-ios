import XCTest
@testable import Nav2PilotKit

final class FakeLocationProvider: LocationProvider {
    var location: LatLng?

    init(_ location: LatLng?) {
        self.location = location
    }

    func currentLocation() async -> LatLng? {
        return location
    }
}

/// Two routes from (45.0, 9.0) to (45.0, 9.2): the fastest straight east, an alternative bending north.
let twoRoutesResponse = #"""
{"code": "Ok", "routes": [
  {"distance": 15700, "duration": 900, "geometry": {"type": "LineString", "coordinates": [[9.0, 45.0], [9.1, 45.0], [9.2, 45.0]]},
   "legs": [{"summary": "A4"}]},
  {"distance": 18200, "duration": 1080, "geometry": {"type": "LineString", "coordinates": [[9.0, 45.0], [9.1, 45.1], [9.2, 45.0]]},
   "legs": [{"summary": "SS11"}]}
]}
"""#

final class MapboxTokenTests: XCTestCase {
    func testTokenKinds() {
        XCTAssertTrue(MapboxTokenRules.isPublicToken("pk.eyJ1IjoiYSJ9.abc"))
        XCTAssertFalse(MapboxTokenRules.isPublicToken("sk.eyJ1IjoiYSJ9.abc"))
        XCTAssertFalse(MapboxTokenRules.isPublicToken("pk.only-two"))
        XCTAssertTrue(MapboxTokenRules.isSecretToken("sk.eyJ1IjoiYSJ9.abc"))
    }

    func testVerifierReadsTheTokensApiCode() async {
        let http = FakeHttpClient()
        http.respond(200, #"{"code": "TokenValid", "token": {"usage": "pk", "user": "driver"}}"#)
        http.respond(200, #"{"code": "TokenInvalid", "token": {"usage": "pk"}}"#)
        http.fail("offline")
        let verifier = MapboxTokenVerifier(http: http)

        let valid = await verifier.verify("pk.a.b")
        let invalid = await verifier.verify("pk.a.c")
        let offline = await verifier.verify("pk.a.d")

        XCTAssertEqual(.valid, valid)
        XCTAssertEqual(.rejected("TokenInvalid"), invalid)
        XCTAssertEqual(.failed(.network("offline")), offline)
        XCTAssertEqual("https://api.mapbox.com/tokens/v2?access_token=pk.a.b", http.requests[0].url)
        XCTAssertEqual("HttpRequest(GET https://api.mapbox.com/tokens/v2?access_token=***)", http.requests[0].description)
    }
}

final class MapboxDirectionsTests: XCTestCase {
    func testRequestMatchesTheDeviceProfile() {
        let url = MapboxDirections.requestUrl(
            from: LatLng(latitude: 45.0, longitude: 9.0),
            stops: [],
            to: LatLng(latitude: 45.0, longitude: 9.2),
            token: "pk.a.b"
        )
        XCTAssertEqual(
            "https://api.mapbox.com/directions/v5/mapbox/driving-traffic/9.000000,45.000000;9.200000,45.000000"
                + "?alternatives=true&geometries=geojson&overview=full&steps=false&access_token=pk.a.b",
            url
        )
        let withStop = MapboxDirections.requestUrl(
            from: LatLng(latitude: 45.0, longitude: 9.0),
            stops: [LatLng(latitude: 45.1, longitude: 9.1)],
            to: LatLng(latitude: 45.0, longitude: 9.2),
            token: "pk.a.b"
        ) ?? ""
        XCTAssertTrue(withStop.contains("9.000000,45.000000;9.100000,45.100000;9.200000,45.000000?alternatives=false"))
    }

    func testParsesRoutesAndErrors() async {
        let http = FakeHttpClient()
        http.respond(200, twoRoutesResponse)
        http.respond(200, #"{"code": "NoRoute", "message": "No route found", "routes": []}"#)
        http.respond(401, #"{"message": "Not Authorized - Invalid Token"}"#)
        let directions = MapboxDirections(http: http, tokenProvider: { "pk.a.b" })
        let origin = LatLng(latitude: 45.0, longitude: 9.0)
        let target = LatLng(latitude: 45.0, longitude: 9.2)

        let found = await directions.routes(from: origin, stops: [], to: target)
        let none = await directions.routes(from: origin, stops: [], to: target)
        let unauthorized = await directions.routes(from: origin, stops: [], to: target)

        guard case .success(let routes) = found else {
            return XCTFail("got \(found)")
        }
        XCTAssertEqual(2, routes.count)
        XCTAssertEqual("A4", routes[0].summary)
        XCTAssertEqual(900, routes[0].durationSeconds)
        XCTAssertEqual(LatLng(latitude: 45.1, longitude: 9.1), routes[1].coordinates[1])
        XCTAssertEqual(.failure(.deviceRejected("No route found")), none)
        XCTAssertEqual(.failure(.unauthorized), unauthorized)
    }

    func testNoTokenNoRequest() async {
        let http = FakeHttpClient()
        let directions = MapboxDirections(http: http, tokenProvider: { nil })
        let result = await directions.routes(from: LatLng(latitude: 0, longitude: 0), stops: [], to: LatLng(latitude: 0, longitude: 1))
        XCTAssertEqual(.failure(.noToken), result)
        XCTAssertTrue(http.requests.isEmpty)
    }

    func testViaPointsLieOnTheRouteAtEvenSpacing() {
        let route = RoutePreview(
            coordinates: [LatLng(latitude: 0, longitude: 0), LatLng(latitude: 0, longitude: 1), LatLng(latitude: 0, longitude: 2)],
            distanceMeters: 0,
            durationSeconds: 0,
            summary: ""
        )
        let points = RouteShaping.viaPoints(along: route)
        XCTAssertEqual(3, points.count)
        XCTAssertEqual(0.5, points[0].longitude, accuracy: 0.0001)
        XCTAssertEqual(1.0, points[1].longitude, accuracy: 0.0001)
        XCTAssertEqual(1.5, points[2].longitude, accuracy: 0.0001)
        XCTAssertTrue(points[0].via)
        XCTAssertEqual(111_195, RouteShaping.distanceMeters(LatLng(latitude: 0, longitude: 0), LatLng(latitude: 0, longitude: 1)), accuracy: 10)
    }
}

final class SetRouteTransportTests: XCTestCase {
    private let device = PairedDevice(dongleId: Fixtures.dongleId, alias: "Car")
    private let destination = Destination(latitude: 45.0, longitude: 9.2)
    private let stop = RouteWaypoint(latitude: 45.1, longitude: 9.1, via: false)

    func testSendsSetNavRouteWithWaypoints() async {
        let http = FakeHttpClient()
        http.respond(200, #"{"jsonrpc": "2.0", "id": 0, "result": {"success": 1}}"#)
        let transport = CommaAthenaTransport(http: http, tokenProvider: { "a.b.c" })

        let result = await transport.setRoute(device, destination, waypoints: [stop])

        XCTAssertEqual(.success(Delivery(queued: false, note: "")), result)
        let body = jsonObject(http.requests[0].body)
        XCTAssertEqual("setNavRoute", body["method"] as? String)
        let params = body["params"] as? [String: Any] ?? [:]
        let waypoints = params["waypoints"] as? [[String: Any]] ?? []
        XCTAssertEqual(1, waypoints.count)
        XCTAssertEqual(45.1, waypoints[0]["latitude"] as? Double)
        XCTAssertEqual(false, waypoints[0]["via"] as? Bool)
    }

    func testFallsBackToTheDestinationOnCommasNavAlpha() async {
        let http = FakeHttpClient()
        http.respond(200, #"{"jsonrpc": "2.0", "id": 0, "error": {"code": -32601, "message": "Method not found"}}"#)
        http.respond(200, #"{"jsonrpc": "2.0", "id": 0, "result": {"success": 1}}"#)
        let transport = CommaAthenaTransport(http: http, tokenProvider: { "a.b.c" })

        let result = await transport.setRoute(device, destination, waypoints: [stop])

        XCTAssertEqual(.success(Delivery(queued: false, note: CommaAthenaTransport.noWaypointsNote)), result)
        XCTAssertEqual("setNavDestination", jsonObject(http.requests[1].body)["method"] as? String)
    }

    func testWithoutWaypointsItIsSetNavDestination() async {
        let http = FakeHttpClient()
        http.respond(200, #"{"jsonrpc": "2.0", "id": 0, "result": {"success": 1}}"#)
        let transport = CommaAthenaTransport(http: http, tokenProvider: { "a.b.c" })

        _ = await transport.setRoute(device, destination, waypoints: [])

        XCTAssertEqual(1, http.requests.count)
        XCTAssertEqual("setNavDestination", jsonObject(http.requests[0].body)["method"] as? String)
    }
}

@MainActor
final class RoutePlanningViewModelTests: XCTestCase {
    private var http = FakeHttpClient()
    private var secrets = InMemorySecretStore()
    private var storage = InMemoryKeyValueStore()
    private var location = FakeLocationProvider(LatLng(latitude: 45.0, longitude: 9.0))

    override func setUp() async throws {
        http = FakeHttpClient()
        secrets = InMemorySecretStore()
        storage = InMemoryKeyValueStore()
        location = FakeLocationProvider(LatLng(latitude: 45.0, longitude: 9.0))
    }

    private func createViewModel() -> MainViewModel {
        let commaTokens = TokenStore(secrets: secrets)
        let mapboxTokens = TokenStore(secrets: secrets, key: TokenStore.keyMapboxToken)
        let comma = CommaAthenaTransport(http: http, tokenProvider: {
            return commaTokens.load()
        })
        let search = FakePlaceSearch()
        let planning = RoutePlanning(
            mapboxTokenStore: mapboxTokens,
            verifier: MapboxTokenVerifier(http: http),
            directions: MapboxDirections(http: http, tokenProvider: {
                return mapboxTokens.load()
            }),
            location: location
        )
        let devices = DeviceRepository(store: storage)
        devices.addManual(PairedDevice(dongleId: Fixtures.dongleId, alias: "Car"))
        return MainViewModel(
            resolver: DestinationResolver(shortLinkResolver: ShortLinkResolver(http: http), placeSearch: search),
            placeSearch: search,
            transports: TransportRegistry(comma: comma, sunnylink: SunnylinkTransport()),
            tokenStore: commaTokens,
            favoritesRepository: FavoritesRepository(store: storage),
            deviceRepository: devices,
            routePlanning: planning
        )
    }

    func testSecretAndMalformedTokensAreRefusedLocally() async {
        let viewModel = createViewModel()
        await viewModel.saveMapboxToken("sk.eyJ1IjoiYSJ9.abc")
        XCTAssertTrue(viewModel.mapboxMessage.contains("secret"))
        await viewModel.saveMapboxToken("hello")
        XCTAssertTrue(viewModel.mapboxMessage.contains("pk."))
        XCTAssertTrue(http.requests.isEmpty)
        XCTAssertFalse(viewModel.hasMapboxToken)
    }

    func testValidTokenIsStoredAndRoutesAreLoaded() async {
        let viewModel = createViewModel()
        await viewModel.search("45.0, 9.2")
        http.respond(200, #"{"code": "TokenValid"}"#)
        http.respond(200, twoRoutesResponse)

        await viewModel.saveMapboxToken(" pk.eyJ1IjoiYSJ9.abc ")

        XCTAssertTrue(viewModel.hasMapboxToken)
        XCTAssertEqual("pk.eyJ1IjoiYSJ9.abc", secrets.values[TokenStore.keyMapboxToken])
        XCTAssertEqual(2, viewModel.routes.count)
        XCTAssertEqual(LatLng(latitude: 45.0, longitude: 9.0), viewModel.origin)
    }

    func testPickedAlternativeIsSentAsViaPoints() async throws {
        try TokenStore(secrets: secrets).save(Fixtures.testJwt)
        try TokenStore(secrets: secrets, key: TokenStore.keyMapboxToken).save("pk.eyJ1IjoiYSJ9.abc")
        let viewModel = createViewModel()
        await viewModel.start()  // no getVersion answer scripted: connection unreachable, sending still works
        await viewModel.search("45.0, 9.2")
        http.respond(200, twoRoutesResponse)
        await viewModel.refreshRoutes()

        viewModel.selectRoute(1)
        http.respond(200, #"{"jsonrpc": "2.0", "id": 0, "result": {"success": 1}}"#)  // setMapboxToken
        http.respond(200, #"{"jsonrpc": "2.0", "id": 0, "result": {"success": 1}}"#)  // setNavRoute
        await viewModel.sendDestination()

        XCTAssertEqual(true, viewModel.feedback?.success)
        XCTAssertEqual("Route sent to Car.", viewModel.feedback?.message)
        let body = jsonObject(http.requests.last?.body)
        XCTAssertEqual("setNavRoute", body["method"] as? String)
        let waypoints = (body["params"] as? [String: Any])?["waypoints"] as? [[String: Any]] ?? []
        XCTAssertEqual(3, waypoints.count)
        XCTAssertEqual(true, waypoints[1]["via"] as? Bool)
    }

    func testStopsAreSentAsStopsAndTheFastestRouteNeedsNoWaypoints() async throws {
        try TokenStore(secrets: secrets).save(Fixtures.testJwt)
        try TokenStore(secrets: secrets, key: TokenStore.keyMapboxToken).save("pk.eyJ1IjoiYSJ9.abc")
        let viewModel = createViewModel()
        await viewModel.start()
        await viewModel.search("45.0, 9.2")
        http.respond(200, twoRoutesResponse)
        await viewModel.refreshRoutes()
        XCTAssertTrue(viewModel.plannedWaypoints().isEmpty)

        http.respond(200, twoRoutesResponse)
        await viewModel.addStop(latitude: 45.1, longitude: 9.1)
        XCTAssertEqual("Stop 1", viewModel.stops.first?.name)
        XCTAssertEqual([RouteWaypoint(latitude: 45.1, longitude: 9.1, via: false)], viewModel.plannedWaypoints())

        http.respond(200, twoRoutesResponse)
        await viewModel.removeStop(at: 0)
        XCTAssertTrue(viewModel.stops.isEmpty)
    }

    func testWithoutLocationTheReasonIsShown() async throws {
        try TokenStore(secrets: secrets, key: TokenStore.keyMapboxToken).save("pk.eyJ1IjoiYSJ9.abc")
        location.location = nil
        let viewModel = createViewModel()
        await viewModel.start()
        await viewModel.search("45.0, 9.2")
        await viewModel.refreshRoutes()

        XCTAssertTrue(viewModel.routes.isEmpty)
        XCTAssertTrue(viewModel.routesMessage.contains("location"))
    }
}

@MainActor
final class MapboxDeviceTokenTests: XCTestCase {
    private let token = "pk.eyJ1IjoiYSJ9.abc"
    private let success = #"{"jsonrpc": "2.0", "id": 0, "result": {"success": 1}}"#
    private let methodNotFound = #"{"jsonrpc": "2.0", "id": 0, "error": {"code": -32601, "message": "Method not found"}}"#
    private var http = FakeHttpClient()
    private var secrets = InMemorySecretStore()
    private var storage = InMemoryKeyValueStore()

    override func setUp() async throws {
        http = FakeHttpClient()
        secrets = InMemorySecretStore()
        storage = InMemoryKeyValueStore()
        try TokenStore(secrets: secrets).save(Fixtures.testJwt)
    }

    private func createViewModel() async -> MainViewModel {
        let commaTokens = TokenStore(secrets: secrets)
        let mapboxTokens = TokenStore(secrets: secrets, key: TokenStore.keyMapboxToken)
        let comma = CommaAthenaTransport(http: http, tokenProvider: {
            return commaTokens.load()
        })
        let search = FakePlaceSearch()
        let planning = RoutePlanning(
            mapboxTokenStore: mapboxTokens,
            verifier: MapboxTokenVerifier(http: http),
            directions: MapboxDirections(http: http, tokenProvider: {
                return mapboxTokens.load()
            }),
            location: FakeLocationProvider(LatLng(latitude: 45.0, longitude: 9.0))
        )
        let devices = DeviceRepository(store: storage)
        devices.addManual(PairedDevice(dongleId: Fixtures.dongleId, alias: "Car"))
        let viewModel = MainViewModel(
            resolver: DestinationResolver(shortLinkResolver: ShortLinkResolver(http: http), placeSearch: search),
            placeSearch: search,
            transports: TransportRegistry(comma: comma, sunnylink: SunnylinkTransport()),
            tokenStore: commaTokens,
            favoritesRepository: FavoritesRepository(store: storage),
            deviceRepository: devices,
            routePlanning: planning
        )
        http.respond(200, #"{"jsonrpc": "2.0", "id": 0, "result": {"version": "1", "branch": "b", "remote": "", "commit": ""}}"#)
        await viewModel.start()
        return viewModel
    }

    private func methods() -> [String] {
        var names: [String] = []
        for request in http.requests {
            names.append(jsonObject(request.body)["method"] as? String ?? request.url)
        }
        return names
    }

    private func sentToken(_ index: Int) -> String? {
        let params = jsonObject(http.requests[index].body)["params"] as? [String: Any] ?? [:]
        return params["token"] as? String
    }

    func testEverySendCarriesTheTokenBeforeTheDestination() async throws {
        try TokenStore(secrets: secrets, key: TokenStore.keyMapboxToken).save(token)
        let viewModel = await createViewModel()
        await viewModel.search("45.0, 9.2")

        http.respond(200, success)
        http.respond(200, success)
        await viewModel.sendDestination()
        http.respond(200, success)
        http.respond(200, success)
        await viewModel.sendDestination()

        XCTAssertEqual(["getVersion", "setMapboxToken", "setNavDestination", "setMapboxToken", "setNavDestination"], methods())
        XCTAssertEqual(token, sentToken(1))
        XCTAssertEqual(token, sentToken(3))
        XCTAssertEqual("Destination sent to Car.", viewModel.feedback?.message)
    }

    func testUnmodifiedOpenpilotGetsTheDestinationWithoutAnyError() async throws {
        try TokenStore(secrets: secrets, key: TokenStore.keyMapboxToken).save(token)
        let viewModel = await createViewModel()
        await viewModel.search("45.0, 9.2")

        http.respond(200, methodNotFound)
        http.respond(200, success)
        await viewModel.sendDestination()

        XCTAssertEqual(true, viewModel.feedback?.success)
        XCTAssertEqual("Destination sent to Car.", viewModel.feedback?.message)
    }

    func testShareExtensionWithoutRouteMapSendsTheTokenToo() async throws {
        let mapboxTokens = TokenStore(secrets: secrets, key: TokenStore.keyMapboxToken)
        try mapboxTokens.save(token)
        let commaTokens = TokenStore(secrets: secrets)
        let comma = CommaAthenaTransport(http: http, tokenProvider: {
            return commaTokens.load()
        })
        let search = FakePlaceSearch()
        let devices = DeviceRepository(store: storage)
        devices.addManual(PairedDevice(dongleId: Fixtures.dongleId, alias: "Car"))
        // like AppContainer.makeViewModel(withRoutePlanning: false), used by the share extension
        let viewModel = MainViewModel(
            resolver: DestinationResolver(shortLinkResolver: ShortLinkResolver(http: http), placeSearch: search),
            placeSearch: search,
            transports: TransportRegistry(comma: comma, sunnylink: SunnylinkTransport()),
            tokenStore: commaTokens,
            favoritesRepository: FavoritesRepository(store: storage),
            deviceRepository: devices,
            mapboxTokenStore: mapboxTokens
        )
        await viewModel.search("45.0, 9.2")

        http.respond(200, success)
        http.respond(200, success)
        await viewModel.sendDestination()

        XCTAssertEqual(["setMapboxToken", "setNavDestination"], methods())
        XCTAssertEqual(token, sentToken(0))
    }

    func testWithoutMapboxTokenNothingExtraIsSent() async {
        let viewModel = await createViewModel()
        await viewModel.search("45.0, 9.2")

        http.respond(200, success)
        await viewModel.sendDestination()

        XCTAssertEqual(["getVersion", "setNavDestination"], methods())
    }

    func testSavingTheTokenSendsItToTheSelectedCarSilently() async {
        let viewModel = await createViewModel()
        http.respond(200, #"{"code": "TokenValid"}"#)
        http.respond(200, methodNotFound)

        await viewModel.saveMapboxToken(token)

        XCTAssertTrue(viewModel.hasMapboxToken)
        XCTAssertEqual("", viewModel.mapboxMessage)
        XCTAssertEqual("setMapboxToken", methods().last)
        XCTAssertEqual(token, sentToken(http.requests.count - 1))
    }

    func testRemovingTheTokenAlsoRemovesItFromTheSelectedCar() async throws {
        try TokenStore(secrets: secrets, key: TokenStore.keyMapboxToken).save(token)
        let viewModel = await createViewModel()

        http.respond(200, success)
        await viewModel.removeMapboxToken()

        XCTAssertFalse(viewModel.hasMapboxToken)
        XCTAssertNil(TokenStore(secrets: secrets, key: TokenStore.keyMapboxToken).load())
        XCTAssertEqual("setMapboxToken", methods().last)
        XCTAssertEqual("", sentToken(http.requests.count - 1))
    }
}
