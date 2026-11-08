import XCTest
@testable import Nav2PilotKit

private let swissServer = OverpassEndpoints.switzerland
private let mainServer = "https://main.example/api/interpreter"

// Apple's results for "ikea" around Basel: a store, and its name alone
private let pratteln = Destination(latitude: 47.5302, longitude: 7.7012, name: "IKEA", details: "Grüssenweg 21, 4133 Pratteln", kind: "shop:yes")
private let spreitenbach = Destination(latitude: 47.4189, longitude: 8.3741, name: "IKEA", details: "8957 Spreitenbach", kind: "shop:yes")
private let freiburg = Destination(latitude: 48.0185, longitude: 7.8036, name: "IKEA", details: "Freiburg im Breisgau", kind: "shop:yes")

// Overpass's answer of 7 November 2026, shortened: way/26343678 and way/76278068, their centres next to the pins
private let swissAnswer = """
{"elements": [
    {"type": "way", "id": 26343678, "center": {"lat": 47.5300, "lon": 7.7010},
     "tags": {"name": "IKEA", "shop": "furniture", "branch": "Pratteln",
              "opening_hours": "Mo-We 10:00-20:00; Th-Fr 10:00-21:00; Sa 09:00-20:00", "phone": "+41 848 801100",
              "website": "https://www.ikea.com/ch/de/stores/pratteln/"}},
    {"type": "way", "id": 76278068, "center": {"lat": 47.4191, "lon": 8.3743},
     "tags": {"name": "IKEA", "opening_hours": "Mo-Sa 09:00-21:00",
              "contact:phone": "+41 848 801 100; +41 56 418 00 00", "contact:website": "www.ikea.com/ch/de/stores/spreitenbach"}}
]}
"""

private func key(_ destination: Destination) -> String {
    return PlaceInfoLookup.key(destination)
}

/// The same cases as the Android app's PlaceKindsTest.
final class PlaceKindsTests: XCTestCase {
    func testLabels() {
        XCTAssertEqual("Furniture store", PlaceKinds.label("shop:furniture"))
        XCTAssertEqual("Fuel station", PlaceKinds.label("amenity:fuel"))
        XCTAssertEqual("Town", PlaceKinds.label("place:town"))
        // not in the list: from the value
        XCTAssertEqual("Second hand shop", PlaceKinds.label("shop:second_hand"))
        XCTAssertEqual("Ice rink", PlaceKinds.label("leisure:ice_rink"))
        XCTAssertEqual("Shop", PlaceKinds.label("shop:yes"))
        // an address or a building says nothing
        XCTAssertEqual("", PlaceKinds.label("building:yes"))
        XCTAssertEqual("", PlaceKinds.label("place:house"))
        XCTAssertEqual("", PlaceKinds.label("boundary:administrative"))
        XCTAssertEqual("", PlaceKinds.label(""))
        XCTAssertEqual("", PlaceKinds.label("shop"))
    }

    func testSymbols() {
        XCTAssertEqual(.fuel, PlaceKinds.category("amenity:fuel"))
        XCTAssertEqual(.restaurant, PlaceKinds.category("amenity:fast_food"))
        XCTAssertNil(PlaceKinds.category("shop:furniture"))
        XCTAssertTrue(PlaceKinds.isShop("shop:furniture"))
        XCTAssertTrue(PlaceKinds.isArea("place:city"))
        XCTAssertTrue(PlaceKinds.isArea("highway:residential"))
        XCTAssertFalse(PlaceKinds.isArea("highway:services"))
        XCTAssertTrue(PlaceKinds.isAddress("place:house"))
        XCTAssertTrue(PlaceKinds.isAddress("building:residential"))
    }

    func testFromPhotonAndOverpass() throws {
        let photon = try XCTUnwrap(Json.parseObject("""
        {"features": [
            {"geometry": {"coordinates": [7.70, 47.53]}, "properties": {"name": "Shell", "osm_key": "amenity", "osm_value": "fuel"}},
            {"geometry": {"coordinates": [7.71, 47.53]}, "properties": {"name": "No tag"}}
        ]}
        """))
        let area = MapArea(south: 47.50, west: 7.65, north: 47.56, east: 7.75)
        let places = PhotonPlaces.parsePlaces(photon, category: .fuel, area: area)
        XCTAssertEqual(["amenity:fuel", "amenity:fuel"], places.map { $0.kind })
        XCTAssertNil(places[0].info)

        XCTAssertEqual("amenity:fast_food", PlaceKinds.fromTags(["amenity": "fast_food"], category: .restaurant))
        XCTAssertEqual("amenity:restaurant", PlaceKinds.fromTags([:], category: .restaurant))
        // what it is, not the building it is in; a fuel station with a shop is a fuel station
        XCTAssertEqual("shop:furniture", PlaceKinds.mainTag(["building": "retail", "shop": "furniture"]))
        XCTAssertEqual("amenity:fuel", PlaceKinds.mainTag(["shop": "convenience", "amenity": "fuel"]))
        XCTAssertEqual("", PlaceKinds.mainTag(["building": "yes"]))
    }

    func testPlacesFromOverpassBringTheirOpeningHours() throws {
        let json = try XCTUnwrap(Json.parseObject("""
        {"elements": [{"type": "node", "id": 1, "lat": 47.505, "lon": 8.015,
         "tags": {"amenity": "fast_food", "name": "Kebab Frick", "opening_hours": "Mo-Su 11:00-23:00", "phone": "+41 62 000 00 00"}}]}
        """))
        let places = OverpassPlaces.parsePlaces(json, category: .restaurant, center: LatLng(latitude: 47.5, longitude: 8.0), limit: 10)

        XCTAssertEqual("amenity:fast_food", places[0].kind)
        XCTAssertEqual("Mo-Su 11:00-23:00", places[0].info?.openingHours)
        XCTAssertEqual("+41 62 000 00 00", places[0].info?.phone)
        XCTAssertEqual("amenity:fast_food", places[0].toDestination().kind)
    }
}

final class PlaceInfoTests: XCTestCase {
    func testInfoFromTheTags() throws {
        let json = try XCTUnwrap(Json.parseObject(swissAnswer))
        let elements = try XCTUnwrap(json["elements"] as? [[String: Any]])
        let first = PlaceInfo.fromTags(try XCTUnwrap(elements[0]["tags"] as? [String: Any]))
        let second = PlaceInfo.fromTags(try XCTUnwrap(elements[1]["tags"] as? [String: Any]))

        XCTAssertEqual("Mo-We 10:00-20:00; Th-Fr 10:00-21:00; Sa 09:00-20:00", first.openingHours)
        XCTAssertEqual("+41 848 801100", first.phone)
        XCTAssertEqual("https://www.ikea.com/ch/de/stores/pratteln/", first.website)
        XCTAssertEqual("shop:furniture", first.kind)
        // the first of two numbers, and an address without https
        XCTAssertEqual("+41 848 801 100", second.phone)
        XCTAssertEqual("https://www.ikea.com/ch/de/stores/spreitenbach", second.website)
        XCTAssertEqual("", second.kind)

        XCTAssertTrue(PlaceInfo.fromTags(["shop": "furniture"]).isEmpty())
        XCTAssertFalse(first.isEmpty())
    }

    func testOnlyWebPagesAreKept() {
        XCTAssertEqual("http://example.com", PlaceInfo.webAddress("http://example.com"))
        XCTAssertEqual("HTTPS://example.com", PlaceInfo.webAddress("HTTPS://example.com"))
        XCTAssertEqual("https://www.ikea.ch", PlaceInfo.webAddress("www.ikea.ch"))
        XCTAssertEqual("", PlaceInfo.webAddress("javascript:alert(1)"))
        XCTAssertEqual("", PlaceInfo.webAddress("intent://scan/#Intent;end"))
        XCTAssertEqual("", PlaceInfo.webAddress("see the sign"))
        XCTAssertEqual("", PlaceInfo.webAddress("tel:+41848801100"))
        XCTAssertEqual("", PlaceInfo.webAddress(""))
    }

    func testTheDetailsWriteThemShort() {
        XCTAssertEqual("ikea.com/ch/de/stores/pratteln", PlaceInfo.shortWebAddress("https://www.ikea.com/ch/de/stores/pratteln/"))
        XCTAssertEqual("example.com", PlaceInfo.shortWebAddress("http://example.com"))
        XCTAssertEqual("tel:+41848801100", PlaceInfo.phoneLink("+41 848 801100"))
        XCTAssertEqual("tel:0616110000", PlaceInfo.phoneLink("061 611 00 00"))
        XCTAssertEqual("", PlaceInfo.phoneLink("ask at the desk"))
        XCTAssertEqual("", PlaceInfo.phoneLink("+"))
    }
}

/// The Android app's PlaceInfoLookupTest, by name and position: Apple's results have no OpenStreetMap id.
@MainActor
final class PlaceInfoLookupTests: XCTestCase {
    private func body(_ http: FakeHttpClient, _ index: Int) -> String {
        let form = http.requests[index].body ?? ""
        return String(form.dropFirst("data=".count)).removingPercentEncoding ?? ""
    }

    func testQueryAsksForTheNameAroundEachPlace() {
        let named = Destination(latitude: 47.4189, longitude: 8.3741, name: "IKEA Spreitenbach", kind: "shop:yes")

        XCTAssertEqual(
            "[out:json][timeout:5];("
                + #"nwr(around:200,47.5302,7.7012)["opening_hours"]["name"~"^(IKEA)$",i];"#
                + #"nwr(around:200,47.4189,8.3741)["opening_hours"]["name"~"^(IKEA|IKEA Spreitenbach)$",i];"#
                + ");out tags center;",
            PlaceInfoLookup.query([pratteln, named])
        )
    }

    func testANameCannotChangeTheQuery() {
        let tricky = Destination(latitude: 47.5, longitude: 7.6, name: "Bar \"Zum\"\n(Hirschen) \\ ]; out;", kind: "amenity:bar")
        let query = PlaceInfoLookup.query([tricky])

        XCTAssertTrue(query.contains(#"["name"~"^(Bar|Bar .Zum.|Bar .Zum. .Hirschen.|Bar .Zum. .Hirschen. .|Bar .Zum. .Hirschen. . .;|Bar .Zum. .Hirschen. . .; out;)$",i];"#), query)
        XCTAssertFalse(query.contains("\n"))
        XCTAssertFalse(query.contains("\\"))

        // a long name: its first words
        let long = Destination(latitude: 47.5, longitude: 7.6, name: "one two three four five six seven eight nine ten", kind: "shop:yes")
        XCTAssertTrue(PlaceInfoLookup.query([long]).contains("|one two three four five six seven eight)$"))
    }

    func testThePlaceWithTheNameNearestToEachResultIsIt() throws {
        let json = try XCTUnwrap(Json.parseObject(swissAnswer))
        let found = PlaceInfoLookup.match(json, to: [pratteln, spreitenbach])

        // both called "IKEA": each one goes to the result next to it
        XCTAssertEqual("Mo-We 10:00-20:00; Th-Fr 10:00-21:00; Sa 09:00-20:00", found[key(pratteln)]?.openingHours)
        XCTAssertEqual("Mo-Sa 09:00-21:00", found[key(spreitenbach)]?.openingHours)

        let around = try XCTUnwrap(Json.parseObject("""
        {"elements": [
            {"type": "node", "id": 1, "lat": 47.5302, "lon": 7.7012, "tags": {"name": "IKEA Restaurant", "opening_hours": "Mo-Sa 09:00-19:00"}},
            {"type": "node", "id": 2, "lat": 47.5315, "lon": 7.7012, "tags": {"name": "ikea", "opening_hours": "Mo-Fr 07:00-16:00"}},
            {"type": "way", "id": 3, "center": {"lat": 47.5300, "lon": 7.7010}, "tags": {"name": "IKEA", "opening_hours": "Mo-Sa 09:00-20:00"}},
            {"type": "relation", "id": 4, "tags": {"name": "IKEA", "opening_hours": "24/7"}}
        ]}
        """))
        // another name is another place; the same name, nearer, is it; one without a position is left out
        XCTAssertEqual("Mo-Sa 09:00-20:00", PlaceInfoLookup.match(around, to: [pratteln])[key(pratteln)]?.openingHours)
        // the Spreitenbach store is no answer for Freiburg
        XCTAssertTrue(PlaceInfoLookup.match(json, to: [freiburg]).isEmpty)
    }

    func testANameWithItsBranchOrTownIsTheSamePlace() {
        let tags: [String: Any] = ["name": "IKEA", "branch": "Pratteln", "addr:city": "Pratteln", "alt_name": "Ikea Basel"]

        XCTAssertTrue(PlaceInfoLookup.isNamed("IKEA", by: tags))
        XCTAssertTrue(PlaceInfoLookup.isNamed("ikea pratteln", by: tags))
        XCTAssertTrue(PlaceInfoLookup.isNamed("IKEA Basel", by: tags))
        XCTAssertFalse(PlaceInfoLookup.isNamed("IKEA Spreitenbach", by: tags))
        XCTAssertFalse(PlaceInfoLookup.isNamed("Coop Pronto", by: ["name": "Coop"]))
        XCTAssertFalse(PlaceInfoLookup.isNamed("", by: tags))
        XCTAssertFalse(PlaceInfoLookup.isNamed("IKEA", by: ["brand": "IKEA"]))
    }

    func testOneRequestForTheListThenFromMemory() async {
        let http = FakeHttpClient()
        let lookup = PlaceInfoLookup(http: http, endpoints: { _ in [swissServer, mainServer] })
        http.respond(200, swissAnswer)

        let address = Destination(latitude: 47.0, longitude: 8.0, name: "Bahnhofstrasse 1")
        let first = await lookup.lookup([pratteln, spreitenbach, address, pratteln])
        let again = await lookup.lookup([spreitenbach])

        XCTAssertEqual(1, http.requests.count)
        XCTAssertEqual(swissServer, http.requests[0].url)
        XCTAssertEqual("POST", http.requests[0].method)
        XCTAssertEqual(PlaceInfoLookup.query([pratteln, spreitenbach]), body(http, 0))
        XCTAssertEqual(Set([key(pratteln), key(spreitenbach)]), Set(first.keys))
        XCTAssertEqual("Mo-Sa 09:00-21:00", again[key(spreitenbach)]?.openingHours)
    }

    func testWhatTheSwissServerLacksGoesToTheNext() async {
        let http = FakeHttpClient()
        let lookup = PlaceInfoLookup(http: http, endpoints: { _ in [swissServer, mainServer] })
        http.respond(200, swissAnswer)
        http.respond(200, #"{"elements": [{"type": "way", "id": 30519110, "center": {"lat": 48.0186, "lon": 7.8035}, "tags": {"name": "IKEA", "opening_hours": "Mo-Sa 10:00-20:00"}}]}"#)

        var reports: [[String]] = []
        let found = await lookup.lookup([pratteln, freiburg]) { answer in
            reports.append(Array(answer.keys))
        }

        XCTAssertEqual(2, http.requests.count)
        XCTAssertEqual(mainServer, http.requests[1].url)
        XCTAssertEqual(PlaceInfoLookup.query([freiburg]), body(http, 1))
        XCTAssertEqual("Mo-Sa 10:00-20:00", found[key(freiburg)]?.openingHours)
        XCTAssertEqual(2, found.count)
        // the Swiss answer is shown before the next server answers
        XCTAssertEqual([[key(pratteln)], [key(freiburg)]], reports)
    }

    func testAServerThatGivesNoAnswerLeavesItToTheNext() async {
        let http = FakeHttpClient()
        let lookup = PlaceInfoLookup(http: http, endpoints: { _ in [swissServer, mainServer] })
        http.respond(504, "<html>Gateway Timeout</html>")
        http.respond(200, swissAnswer)

        let found = await lookup.lookup([pratteln, spreitenbach])

        XCTAssertEqual([swissServer, mainServer], http.requests.map { $0.url })
        XCTAssertEqual(2, found.count)
    }

    func testNoAnswerIsAskedAgainNextTime() async {
        let http = FakeHttpClient()
        let lookup = PlaceInfoLookup(http: http, endpoints: { _ in [mainServer] })
        http.fail("timeout")
        http.respond(200, #"{"remark": "runtime error: out of memory", "elements": []}"#)
        http.respond(200, #"{"elements": []}"#)

        let timedOut = await lookup.lookup([freiburg])
        XCTAssertTrue(timedOut.isEmpty)
        let outOfMemory = await lookup.lookup([freiburg])
        XCTAssertTrue(outOfMemory.isEmpty)
        // answered: not in OpenStreetMap with opening hours, and not asked about again
        let answered = await lookup.lookup([freiburg])
        XCTAssertEqual(PlaceInfo(), answered[key(freiburg)])
        let remembered = await lookup.lookup([freiburg])
        XCTAssertEqual(PlaceInfo(), remembered[key(freiburg)])
        XCTAssertEqual(3, http.requests.count)
    }

    func testTheOldestAreForgottenFirst() async {
        let http = FakeHttpClient()
        let lookup = PlaceInfoLookup(http: http, endpoints: { _ in [mainServer] })
        var many: [Destination] = []
        for index in 0...PlaceInfoLookup.maxKnown {
            many.append(Destination(latitude: 47.0 + Double(index) * 0.001, longitude: 8.0, name: "Shop \(index)", kind: "shop:yes"))
        }
        http.respond(200, #"{"elements": []}"#)
        await lookup.lookup(many)

        await lookup.lookup([many[PlaceInfoLookup.maxKnown]])
        XCTAssertEqual(1, http.requests.count)
        http.respond(200, #"{"elements": []}"#)
        await lookup.lookup([many[0]])
        XCTAssertEqual(2, http.requests.count)
    }

    func testOnlyPlacesThatCanHaveOpeningHoursAreLookedFor() async {
        XCTAssertTrue(PlaceInfoLookup.wants(pratteln))
        XCTAssertFalse(PlaceInfoLookup.wants(Destination(latitude: 47.0, longitude: 8.0, name: "Bahnhofstrasse 1")))
        XCTAssertFalse(PlaceInfoLookup.wants(Destination(latitude: 47.0, longitude: 8.0, name: "Basel", kind: "place:city")))
        XCTAssertFalse(PlaceInfoLookup.wants(Destination(latitude: 47.0, longitude: 8.0, name: "Home", kind: "building:yes")))
        XCTAssertFalse(PlaceInfoLookup.wants(Destination(latitude: 47.0, longitude: 8.0, name: "Map", approximate: true, kind: "shop:yes")))
        XCTAssertFalse(PlaceInfoLookup.wants(Destination(latitude: 47.0, longitude: 8.0, name: " ", kind: "shop:yes")))

        let http = FakeHttpClient()
        let lookup = PlaceInfoLookup(http: http, endpoints: { _ in [mainServer] })
        let none = await lookup.lookup([Destination(latitude: 47.0, longitude: 8.0, name: "Basel", kind: "place:city")])
        XCTAssertTrue(none.isEmpty)
        XCTAssertTrue(http.requests.isEmpty)
    }

    func testTheSameNameAtTheSamePlaceIsOneKey() {
        XCTAssertEqual("ikea@47.53020,7.70120", key(pratteln))
        var moved = pratteln
        moved.details = "another address"
        XCTAssertEqual(key(pratteln), key(moved))
        XCTAssertNotEqual(key(pratteln), key(spreitenbach))
    }

    func testSwissServerFirstForPlacesAroundSwitzerland() {
        // Stuttgart and Pratteln
        XCTAssertEqual(swissServer, OverpassEndpoints.forPoints([LatLng(latitude: 48.78, longitude: 9.18), LatLng(latitude: 47.53, longitude: 7.70)])[0])
        XCTAssertFalse(OverpassEndpoints.forPoints([LatLng(latitude: 48.78, longitude: 9.18)]).contains(swissServer))
        XCTAssertEqual(OverpassEndpoints.interpreters, OverpassEndpoints.forPoints([]))
    }
}

/// Opening hours in the search: looked up once for the list of results, never while typing.
@MainActor
final class PlaceInfoViewModelTests: XCTestCase {
    private var http = FakeHttpClient()
    private var search = FakePlaceSearch()

    override func setUp() async throws {
        http = FakeHttpClient()
        search = FakePlaceSearch()
        search.results["ikea"] = [pratteln, spreitenbach, freiburg]
    }

    private func createViewModel() -> MainViewModel {
        let tokenStore = TokenStore(secrets: InMemorySecretStore())
        let comma = CommaAthenaTransport(http: http, tokenProvider: {
            return tokenStore.load()
        })
        let storage = InMemoryKeyValueStore()
        return MainViewModel(
            resolver: DestinationResolver(shortLinkResolver: ShortLinkResolver(http: http), placeSearch: search),
            placeSearch: search,
            transports: TransportRegistry(comma: comma, sunnylink: SunnylinkTransport()),
            tokenStore: tokenStore,
            favoritesRepository: FavoritesRepository(store: storage),
            deviceRepository: DeviceRepository(store: storage),
            places: OverpassPlaces(http: http, endpoints: { _ in [mainServer] }),
            placeInfoLookup: PlaceInfoLookup(http: http, endpoints: { _ in [swissServer, mainServer] }),
            typingPause: .milliseconds(1)
        )
    }

    func testTheResultsGetTheirOpeningHoursInOneRequest() async {
        let viewModel = createViewModel()
        http.respond(200, swissAnswer)
        http.respond(200, #"{"elements": []}"#)

        await viewModel.search("ikea")

        XCTAssertEqual(3, viewModel.choices.count)
        XCTAssertEqual([swissServer, mainServer], http.requests.map { $0.url })
        XCTAssertEqual(PlaceInfoLookup.query([pratteln, spreitenbach, freiburg]), String((http.requests[0].body ?? "").dropFirst(5)).removingPercentEncoding)
        XCTAssertEqual("Mo-Sa 09:00-21:00", viewModel.info(for: spreitenbach).openingHours)
        // asked and none: nothing to show
        XCTAssertTrue(viewModel.info(for: freiburg).isEmpty())

        // choosing one asks nothing more
        viewModel.chooseCandidate(viewModel.choices[0])
        await viewModel.placeInfoTask?.value
        XCTAssertEqual(2, http.requests.count)
        XCTAssertEqual("+41 848 801100", viewModel.info(for: pratteln).phone)
    }

    func testTypingAsksNothing() async {
        let viewModel = createViewModel()

        await viewModel.typeSearch("ikea")?.value

        XCTAssertEqual(3, viewModel.suggestions.count)
        XCTAssertTrue(http.requests.isEmpty)
        XCTAssertTrue(viewModel.placeInfo.isEmpty)
    }

    func testOpenStreetMapSaysWhatKindOfShopItIs() async {
        let viewModel = createViewModel()
        http.respond(200, swissAnswer)
        http.respond(200, #"{"elements": []}"#)
        await viewModel.search("ikea")

        // Apple's "store", OpenStreetMap's furniture store
        XCTAssertEqual("Furniture store", viewModel.kindLabel(for: pratteln))
        // no kind in OpenStreetMap: Apple's
        XCTAssertEqual("Shop", viewModel.kindLabel(for: spreitenbach))
        XCTAssertEqual("", viewModel.kindLabel(for: Destination(latitude: 47.0, longitude: 8.0, name: "Bahnhofstrasse 1")))
        XCTAssertEqual("", viewModel.kindLabel(for: Destination(latitude: 47.0, longitude: 8.0, name: "Town", kind: "place:town")))
    }

    func testApplesPhoneAndWebPageComeFirst() async {
        let viewModel = createViewModel()
        var withPhone = pratteln
        withPhone.phone = "+41 61 000 00 00"
        withPhone.website = "https://example.com/ikea"
        search.results["ikea"] = [withPhone, spreitenbach]
        http.respond(200, swissAnswer)
        await viewModel.search("ikea")

        let info = viewModel.info(for: withPhone)
        XCTAssertEqual("+41 61 000 00 00", info.phone)
        XCTAssertEqual("https://example.com/ikea", info.website)
        XCTAssertEqual("Mo-We 10:00-20:00; Th-Fr 10:00-21:00; Sa 09:00-20:00", info.openingHours)
    }

    func testAPlaceFromTheMapMenuBringsItsOwnHours() async {
        let viewModel = createViewModel()
        http.respond(200, """
        {"elements": [{"type": "node", "id": 1, "lat": 47.505, "lon": 8.015,
         "tags": {"amenity": "fuel", "name": "Migrol Frick", "opening_hours": "Mo-Sa 06:00-22:00"}}]}
        """)
        await viewModel.showPlaces(.fuel, in: MapArea(south: 47.45, west: 7.95, north: 47.55, east: 8.10))

        viewModel.choosePlace(viewModel.places[0])
        await viewModel.placeInfoTask?.value

        // only the places' own request
        XCTAssertEqual(1, http.requests.count)
        let destination = viewModel.destination!
        XCTAssertEqual("Mo-Sa 06:00-22:00", viewModel.info(for: destination).openingHours)
        XCTAssertEqual("Fuel station", viewModel.kindLabel(for: destination))
    }
}
