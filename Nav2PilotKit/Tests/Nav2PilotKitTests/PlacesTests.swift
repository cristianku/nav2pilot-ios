import MapKit
import XCTest
@testable import Nav2PilotKit

private let firstServer = "https://one.example/api/interpreter"
private let secondServer = "https://two.example/api/interpreter"

/// Around Frick (CH): a named node with an address, a way with only a brand, an unnamed node, a relation without centre.
private let overpassAnswer = """
{
  "version": 0.6,
  "generator": "Overpass API",
  "elements": [
    {"type": "node", "id": 1, "lat": 47.505, "lon": 8.015,
     "tags": {"amenity": "fuel", "name": "Migrol Frick", "brand": "Migrol", "addr:street": "Hauptstrasse",
              "addr:housenumber": "12", "addr:postcode": "5070", "addr:city": "Frick"}},
    {"type": "way", "id": 2, "center": {"lat": 47.48, "lon": 8.03}, "nodes": [10, 11, 12],
     "tags": {"amenity": "fuel", "brand": "Shell"}},
    {"type": "node", "id": 3, "lat": 47.5, "lon": 8.02, "tags": {"amenity": "fuel"}},
    {"type": "relation", "id": 4, "tags": {"amenity": "fuel", "name": "No position"}}
  ]
}
"""

private let frick = MapArea(south: 47.45, west: 7.95, north: 47.55, east: 8.10)

final class OverpassPlacesTests: XCTestCase {
    func testQueryAsksTheCategoryInTheAreaWithCentres() {
        XCTAssertEqual(
            #"[out:json][timeout:10];nwr["amenity"="fuel"](47.45000,7.95000,47.55000,8.10000);out center 200;"#,
            OverpassPlaces.query(.fuel, frick)
        )
        XCTAssertTrue(OverpassPlaces.query(.parking, frick).contains(#"["access"!~"^(private|no)$"]"#))
        XCTAssertEqual(9, PlaceCategory.allCases.count)
    }

    func testParsePlacesNamesThemAndPutsTheNearestFirst() {
        let json = jsonObject(overpassAnswer)
        let places = OverpassPlaces.parsePlaces(json, category: .fuel, center: frick.center(), limit: 50)

        XCTAssertEqual(3, places.count)
        // unnamed: called by its category
        XCTAssertEqual("Fuel station", places[0].name)
        XCTAssertEqual(47.5, places[0].latitude, accuracy: 1e-9)
        XCTAssertEqual("Migrol Frick", places[1].name)
        XCTAssertEqual("Hauptstrasse 12, 5070 Frick", places[1].details)
        // a way: its centre, and the brand when it has no name
        XCTAssertEqual("Shell", places[2].name)
        XCTAssertEqual("", places[2].details)
        XCTAssertEqual(47.48, places[2].latitude, accuracy: 1e-9)
        XCTAssertEqual(8.03, places[2].longitude, accuracy: 1e-9)

        let nearest = OverpassPlaces.parsePlaces(json, category: .fuel, center: frick.center(), limit: 2)
        XCTAssertEqual(["Fuel station", "Migrol Frick"], nearest.map { $0.name })
    }

    func testSearchPostsTheQueryAndTriesTheNextServerWhenOneIsBusy() async {
        let http = FakeHttpClient()
        let places = OverpassPlaces(http: http, endpoints: { _ in [firstServer, secondServer] })

        http.respond(429, "")
        http.respond(200, overpassAnswer)
        let result = await places.search(.fuel, in: frick)

        guard case .success(let found) = result else {
            return XCTFail("expected places, got \(result)")
        }
        XCTAssertEqual(3, found.count)
        XCTAssertEqual([firstServer, secondServer], http.requests.map { $0.url })
        let request = http.requests[1]
        XCTAssertEqual("POST", request.method)
        XCTAssertEqual("application/x-www-form-urlencoded", request.headers["Content-Type"])
        let body = request.body ?? ""
        XCTAssertTrue(body.hasPrefix("data="))
        XCTAssertEqual(OverpassPlaces.query(.fuel, frick), String(body.dropFirst(5)).removingPercentEncoding)
    }

    func testSearchReportsWhatWentWrong() async {
        let http = FakeHttpClient()
        let places = OverpassPlaces(http: http, endpoints: { _ in [firstServer, secondServer] })

        // both busy: the last answer
        http.fail("timeout")
        http.respond(504, "<html>Gateway Timeout</html>")
        let busy = await places.search(.fuel, in: frick)
        guard case .failure(.httpFailure(let code, _)) = busy else {
            return XCTFail("expected HTTP 504, got \(busy)")
        }
        XCTAssertEqual(504, code)

        // a refused query is not sent again elsewhere
        http.requests = []
        http.respond(400, "<html>Error: line 1: parse error</html>")
        let refused = await places.search(.fuel, in: frick)
        guard case .failure(.httpFailure(let refusedCode, _)) = refused else {
            return XCTFail("expected HTTP 400, got \(refused)")
        }
        XCTAssertEqual(400, refusedCode)
        XCTAssertEqual(1, http.requests.count)

        // out of time on both: 200 with a remark and no elements
        let outOfTime = #"{"elements": [], "remark": "runtime error: Query timed out in \"query\" at line 1 after 21 seconds."}"#
        http.respond(200, outOfTime)
        http.respond(200, outOfTime)
        let timedOut = await places.search(.fuel, in: frick)
        guard case .failure(.deviceRejected) = timedOut else {
            return XCTFail("expected a rejection, got \(timedOut)")
        }

        http.respond(200, #"{"elements": []}"#)
        let none = await places.search(.fuel, in: frick)
        XCTAssertEqual(.success([]), none)
    }

    func testAServerThatRefusesTheAppOrAnswersBadlyLeavesItToTheNext() async {
        let http = FakeHttpClient()
        let places = OverpassPlaces(http: http, endpoints: { _ in [firstServer, secondServer] })

        http.respond(406, "<html>Not Acceptable</html>")
        http.respond(200, overpassAnswer)
        let refused = await places.search(.fuel, in: frick)
        guard case .success(let found) = refused else {
            return XCTFail("expected places, got \(refused)")
        }
        XCTAssertEqual(3, found.count)

        http.respond(200, "<html>rate_limited</html>")
        http.respond(200, overpassAnswer)
        let notJson = await places.search(.fuel, in: frick)
        guard case .success(let foundAgain) = notJson else {
            return XCTFail("expected places, got \(notJson)")
        }
        XCTAssertEqual(3, foundAgain.count)
    }

    func testTheSwissServerIsAskedFirstOnlyAroundSwitzerland() {
        XCTAssertEqual(OverpassEndpoints.switzerland, OverpassEndpoints.forArea(frick).first)
        XCTAssertEqual(3, OverpassEndpoints.forArea(frick).count)
        let milan = MapArea(south: 45.40, west: 9.10, north: 45.50, east: 9.25)
        XCTAssertEqual(OverpassEndpoints.interpreters, OverpassEndpoints.forArea(milan))
    }

    func testNoneOnTheSwissServerIsCheckedAcrossTheBorder() async {
        let http = FakeHttpClient()
        let places = OverpassPlaces(http: http, endpoints: { _ in [OverpassEndpoints.switzerland, firstServer] })

        http.respond(200, #"{"elements": []}"#)
        http.respond(200, overpassAnswer)
        let across = await places.search(.fuel, in: frick)
        guard case .success(let found) = across else {
            return XCTFail("expected places, got \(across)")
        }
        XCTAssertEqual(3, found.count)

        // the world servers are busy: still "none", not an error
        http.respond(200, #"{"elements": []}"#)
        http.fail("timeout")
        let none = await places.search(.fuel, in: frick)
        XCTAssertEqual(.success([]), none)
    }

    func testAreaLimitedAroundItsCentre() {
        let small = frick.limited(to: 25_000)
        XCTAssertEqual(frick.south, small.south, accuracy: 1e-9)
        XCTAssertEqual(frick.west, small.west, accuracy: 1e-9)
        XCTAssertEqual(frick.north, small.north, accuracy: 1e-9)
        XCTAssertEqual(frick.east, small.east, accuracy: 1e-9)

        // a whole country in view: 50 km around its middle
        let large = MapArea(south: 40, west: 0, north: 50, east: 20).limited(to: 25_000)
        XCTAssertEqual(45, large.center().latitude, accuracy: 1e-9)
        XCTAssertEqual(10, large.center().longitude, accuracy: 1e-9)
        let height = (large.north - large.south) * 111_320
        let width = (large.east - large.west) * 111_320 * cos(45 * Double.pi / 180)
        XCTAssertEqual(50_000, height, accuracy: 1)
        XCTAssertEqual(50_000, width, accuracy: 1)
    }

    func testFormEncodingKeepsOnlyLettersDigitsAndFourMarks() {
        XCTAssertEqual("%5B%22a%22%3D%22b%2Bc%22%5D", OverpassPlaces.formEncode(#"["a"="b+c"]"#))
        XCTAssertEqual("a-b._*%20%3B", OverpassPlaces.formEncode("a-b._* ;"))
    }

    func testSearchRegionIsAroundThePhone() {
        let region = MapKitPlaceSearch.searchRegion(around: LatLng(latitude: 47.5596, longitude: 7.5886))
        XCTAssertEqual(47.5596, region.center.latitude, accuracy: 1e-9)
        XCTAssertEqual(7.5886, region.center.longitude, accuracy: 1e-9)
        // 50 km from south to north
        XCTAssertEqual(50_000.0 / 111_000, region.span.latitudeDelta, accuracy: 0.01)
    }
}

final class MapKitPlaceSearchTests: XCTestCase {
    private func item(_ category: MKPointOfInterestCategory?, url: String?) -> MKMapItem {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 47.5302, longitude: 7.7012)))
        item.name = "IKEA"
        item.phoneNumber = " +41 848 801 100 "
        if let address = url {
            item.url = URL(string: address)
        }
        item.pointOfInterestCategory = category
        return item
    }

    func testApplesCategoriesAreOpenStreetMapKinds() {
        XCTAssertEqual("amenity:fuel", MapKitPlaceSearch.kind(.gasStation))
        XCTAssertEqual("shop:supermarket", MapKitPlaceSearch.kind(.foodMarket))
        XCTAssertEqual("", MapKitPlaceSearch.kind(nil))
        // the same labels and symbols as OpenStreetMap's places
        XCTAssertEqual("Shop", PlaceKinds.label(MapKitPlaceSearch.kind(.store)))
        XCTAssertEqual("Fuel station", PlaceKinds.label(MapKitPlaceSearch.kind(.gasStation)))
        XCTAssertEqual(.restaurant, PlaceKinds.category(MapKitPlaceSearch.kind(.restaurant)))
        XCTAssertEqual(.charging, PlaceKinds.category(MapKitPlaceSearch.kind(.evCharger)))
        let named: [MKPointOfInterestCategory] = [.airport, .bakery, .cafe, .hotel, .museum, .parking, .pharmacy, .theater, .zoo]
        for category in named {
            XCTAssertFalse(PlaceKinds.label(MapKitPlaceSearch.kind(category)).isEmpty, category.rawValue)
        }
    }

    func testAMapItemBringsItsKindPhoneAndWebPage() {
        let destination = MapKitPlaceSearch.toDestination(item(.store, url: "https://www.ikea.com/ch/de/stores/pratteln/"))

        XCTAssertEqual("IKEA", destination.name)
        XCTAssertEqual(47.5302, destination.latitude, accuracy: 1e-9)
        XCTAssertEqual("shop:yes", destination.kind)
        XCTAssertEqual("+41 848 801 100", destination.phone)
        XCTAssertEqual("https://www.ikea.com/ch/de/stores/pratteln/", destination.website)
        XCTAssertTrue(PlaceInfoLookup.wants(destination))

        // only a web page opens from the details
        XCTAssertEqual("", MapKitPlaceSearch.toDestination(item(.store, url: "tel:+41848801100")).website)
        let address = MapKitPlaceSearch.toDestination(item(nil, url: nil))
        XCTAssertEqual("", address.kind)
        XCTAssertEqual("", address.website)
        XCTAssertFalse(PlaceInfoLookup.wants(address))
    }
}

@MainActor
final class PlacesViewModelTests: XCTestCase {
    private var http = FakeHttpClient()
    private var storage = InMemoryKeyValueStore()

    override func setUp() async throws {
        http = FakeHttpClient()
        storage = InMemoryKeyValueStore()
    }

    private func createViewModel(withPlaces: Bool = true) -> MainViewModel {
        let tokenStore = TokenStore(secrets: InMemorySecretStore())
        let comma = CommaAthenaTransport(http: http, tokenProvider: {
            return tokenStore.load()
        })
        let search = FakePlaceSearch()
        var places: OverpassPlaces?
        if withPlaces {
            places = OverpassPlaces(http: http, endpoints: { _ in [firstServer] })
        }
        return MainViewModel(
            resolver: DestinationResolver(shortLinkResolver: ShortLinkResolver(http: http), placeSearch: search),
            placeSearch: search,
            transports: TransportRegistry(comma: comma, sunnylink: SunnylinkTransport()),
            tokenStore: tokenStore,
            favoritesRepository: FavoritesRepository(store: storage),
            deviceRepository: DeviceRepository(store: storage),
            places: places
        )
    }

    func testShowPlacesThenChooseOneAsTheDestination() async {
        let viewModel = createViewModel()
        XCTAssertTrue(viewModel.placesAvailable)

        http.respond(200, overpassAnswer)
        await viewModel.showPlaces(.fuel, in: frick)

        XCTAssertEqual(.fuel, viewModel.placesCategory)
        XCTAssertEqual(3, viewModel.places.count)
        XCTAssertFalse(viewModel.placesLoading)

        viewModel.choosePlace(viewModel.places[1])
        XCTAssertEqual("Migrol Frick", viewModel.destination?.name)
        XCTAssertEqual("Hauptstrasse 12, 5070 Frick", viewModel.destination?.details)
        XCTAssertEqual(DestinationResolver.sourcePlaces, viewModel.destinationSource)
        // the places stay, to add one as a stop
        XCTAssertEqual(3, viewModel.places.count)

        viewModel.hidePlaces()
        XCTAssertNil(viewModel.placesCategory)
        XCTAssertTrue(viewModel.places.isEmpty)
    }

    func testNoneFoundOrNoAnswerIsToldOnce() async {
        let viewModel = createViewModel()

        http.respond(200, #"{"elements": []}"#)
        await viewModel.showPlaces(.pharmacy, in: frick)
        XCTAssertNil(viewModel.placesCategory)
        XCTAssertEqual("Pharmacies: none in this part of the map.", viewModel.placesMessage)
        XCTAssertEqual(1, viewModel.placesMessageRequest)

        http.respond(429, "")
        await viewModel.showPlaces(.fuel, in: frick)
        XCTAssertEqual("OpenStreetMap is busy (HTTP 429). Try again in a moment.", viewModel.placesMessage)
        XCTAssertEqual(2, viewModel.placesMessageRequest)

        await viewModel.showPlaces(.fuel, in: nil)
        XCTAssertEqual("The map is not ready yet. Try again in a moment.", viewModel.placesMessage)
        XCTAssertEqual(3, viewModel.placesMessageRequest)
    }

    func testAZoomedOutMapIsSearchedInItsMiddle() async {
        let viewModel = createViewModel()
        http.respond(200, #"{"elements": []}"#)
        await viewModel.showPlaces(.hotel, in: MapArea(south: 40, west: 0, north: 50, east: 20))

        let body = String((http.requests.first?.body ?? "").dropFirst(5)).removingPercentEncoding ?? ""
        XCTAssertTrue(body.contains("(44.77542,"), body)
    }

    func testNoPlacesWithoutTheMap() async {
        let viewModel = createViewModel(withPlaces: false)
        XCTAssertFalse(viewModel.placesAvailable)
        await viewModel.showPlaces(.fuel, in: frick)
        XCTAssertNil(viewModel.placesCategory)
        XCTAssertTrue(http.requests.isEmpty)
    }
}
