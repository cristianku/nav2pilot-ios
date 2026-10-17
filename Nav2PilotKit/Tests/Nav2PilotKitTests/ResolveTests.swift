import XCTest
@testable import Nav2PilotKit

final class ShortLinkResolverTests: XCTestCase {
    func testFollowsOneRedirectAndStopsAtThePlacePin() async {
        let http = FakeHttpClient()
        http.redirect(Fixtures.shortLinkTarget)

        let result = await ShortLinkResolver(http: http).resolve(Fixtures.shortLink)

        XCTAssertEqual(1, http.requests.count)
        let request = http.requests[0]
        XCTAssertEqual("GET", request.method)
        XCTAssertEqual(Fixtures.shortLink, request.url)
        XCTAssertFalse(request.followRedirects, "redirects must be followed one hop at a time")
        XCTAssertFalse(request.readBody)
        XCTAssertTrue(request.headers.isEmpty)

        let destination = foundDestination(result.result)
        XCTAssertEqual(43.695783, destination?.latitude ?? 0, accuracy: 0.0000001)
        XCTAssertEqual(7.260654, destination?.longitude ?? 0, accuracy: 0.0000001)
        XCTAssertEqual("", result.networkError)
    }

    func testConsentInterstitialIsUnwrappedWithoutFetchingIt() async {
        let http = FakeHttpClient()
        // short link -> Maps URL without a pin -> consent page whose continue= carries the pin
        http.redirect("https://www.google.com/maps/place/Copenhagen+Coffee+Lab/@43.6764552,6.9908374,10.65z")
        http.redirect(Fixtures.consentRedirect)

        let result = await ShortLinkResolver(http: http).resolve(Fixtures.shortLink)

        XCTAssertEqual(2, http.requests.count)
        for request in http.requests {
            XCTAssertFalse(request.url.contains("consent.google.com"))
        }
        let destination = foundDestination(result.result)
        XCTAssertEqual(43.695783, destination?.latitude ?? 0, accuracy: 0.0000001)
        XCTAssertEqual(7.260654, destination?.longitude ?? 0, accuracy: 0.0000001)
        XCTAssertEqual(false, destination?.approximate)
    }

    func testKeepsViewportWhenNothingBetterIsAvailable() async {
        let http = FakeHttpClient()
        http.redirect("https://www.google.com/maps/place/Somewhere/@45.1,9.2,15z")
        http.respond(200)

        let result = await ShortLinkResolver(http: http).resolve(Fixtures.shortLink)

        let destination = foundDestination(result.result)
        XCTAssertEqual(true, destination?.approximate)
        XCTAssertEqual("Somewhere", destination?.name)
    }

    func testDoesNotFollowRedirectsToOtherHosts() async {
        let http = FakeHttpClient()
        http.redirect("https://example.com/somewhere?q=45.1,9.2")

        let result = await ShortLinkResolver(http: http).resolve(Fixtures.shortLink)

        XCTAssertEqual(1, http.requests.count)
        XCTAssertEqual(.notRecognized, result.result)
        XCTAssertEqual("https://example.com/somewhere?q=45.1,9.2", result.finalUrl)
    }

    func testRelativeLocationIsResolved() async {
        let http = FakeHttpClient()
        http.redirect("/maps?q=45.1,9.2")

        let result = await ShortLinkResolver(http: http).resolve("https://maps.google.com/maps?cid=123")

        XCTAssertEqual(45.1, foundDestination(result.result)?.latitude ?? 0, accuracy: 0.0000001)
        XCTAssertEqual("https://maps.google.com/maps?q=45.1,9.2", result.finalUrl)
    }

    func testAppleShortLinkIsExpandedToItsPlace() async {
        // Shape of the redirect: maps.apple.com answers relative Location headers (checked 2026-10-17).
        let http = FakeHttpClient()
        http.redirect("https://maps.apple.com/?ll=45.4642,9.19&q=Duomo")
        http.redirect("/place?coordinate=45.4642%2C9.19&name=Duomo", code: 301)

        let result = await ShortLinkResolver(http: http).resolve("https://maps.apple/p/abc")

        XCTAssertEqual(1, http.requests.count, "the legacy ll+q link already is an exact pin")
        XCTAssertEqual("Duomo", foundDestination(result.result)?.name)
    }

    func testStopsAfterMaxHops() async {
        let http = FakeHttpClient()
        for index in 0..<10 {
            http.redirect("https://maps.app.goo.gl/loop\(index)")
        }

        let result = await ShortLinkResolver(http: http, maxHops: 3).resolve(Fixtures.shortLink)

        XCTAssertEqual(3, http.requests.count)
        XCTAssertEqual(.notRecognized, result.result)
    }

    func testNetworkErrorIsReported() async {
        let http = FakeHttpClient()
        http.fail("timeout")

        let result = await ShortLinkResolver(http: http).resolve(Fixtures.shortLink)

        XCTAssertEqual("timeout", result.networkError)
        XCTAssertEqual(.notRecognized, result.result)
    }

    func testHttpIsUpgradedToHttps() async {
        let http = FakeHttpClient()
        http.redirect(Fixtures.shortLinkTarget)

        _ = await ShortLinkResolver(http: http).resolve("http://maps.app.goo.gl/gqhGPJxrF8E7MX479")

        XCTAssertEqual(Fixtures.shortLink, http.requests[0].url)
    }
}

final class DestinationResolverTests: XCTestCase {
    private var http = FakeHttpClient()
    private var search = FakePlaceSearch()
    private var resolver: DestinationResolver!

    override func setUp() {
        super.setUp()
        http = FakeHttpClient()
        search = FakePlaceSearch()
        resolver = DestinationResolver(shortLinkResolver: ShortLinkResolver(http: http), placeSearch: search)
    }

    func testGoogleMapsShareResolvesThroughTheShortLink() async {
        http.redirect(Fixtures.shortLinkTarget)
        let text = "Copenhagen Coffee Lab\n5 Rue de la Préfecture, 06300 Nice, France\n" + Fixtures.shortLink

        let outcome = await resolver.resolveShared(text: text, subject: "")

        guard case .resolved(let destination, let source) = outcome else {
            return XCTFail("got \(outcome)")
        }
        XCTAssertEqual(43.695783, destination.latitude, accuracy: 0.0000001)
        XCTAssertEqual(7.260654, destination.longitude, accuracy: 0.0000001)
        XCTAssertEqual("Copenhagen Coffee Lab", destination.name)
        XCTAssertEqual("5 Rue de la Préfecture, 06300 Nice, France", destination.details)
        XCTAssertEqual(DestinationResolver.sourceSharedLink, source)
        XCTAssertTrue(search.queries.isEmpty)
    }

    func testLinkWithoutCoordinatesFallsBackToTheSharedAddress() async {
        http.redirect("https://www.google.com/maps/place/Some+Cafe/data=!4m2!3m1!1s0x0:0x1")
        http.respond(200)
        search.results["Via Roma 1, Torino"] = [Destination(latitude: 45.07, longitude: 7.68, name: "Via Roma 1")]

        let outcome = await resolver.resolveShared(text: "Some Cafe\nVia Roma 1, Torino\n" + Fixtures.shortLink, subject: "")

        guard case .resolved(let destination, _) = outcome else {
            return XCTFail("got \(outcome)")
        }
        XCTAssertEqual(45.07, destination.latitude, accuracy: 0.0000001)
        XCTAssertEqual("Some Cafe", destination.name)
        XCTAssertEqual("Via Roma 1, Torino", search.queries[0])
    }

    func testTypedCoordinatesNeedNoNetwork() async {
        let outcome = await resolver.resolveTyped(" 45.4642, 9.19 ")

        guard case .resolved(let destination, let source) = outcome else {
            return XCTFail("got \(outcome)")
        }
        XCTAssertEqual(45.4642, destination.latitude, accuracy: 0.0000001)
        XCTAssertEqual(DestinationResolver.sourceCoordinates, source)
        XCTAssertTrue(http.requests.isEmpty)
    }

    func testSharedTextWithCoordinateLine() async {
        let outcome = await resolver.resolveShared(text: "Parking spot\n45.1, 9.2", subject: "")

        guard case .resolved(let destination, _) = outcome else {
            return XCTFail("got \(outcome)")
        }
        XCTAssertEqual(45.1, destination.latitude, accuracy: 0.0000001)
        XCTAssertEqual("Parking spot", destination.name)
    }

    func testAppleMapsShareNeedsNoNetwork() async {
        let outcome = await resolver.resolveShared(text: "https://maps.apple.com/place?coordinate=45.4642,9.19&name=Duomo", subject: "")

        guard case .resolved(let destination, _) = outcome else {
            return XCTFail("got \(outcome)")
        }
        XCTAssertEqual("Duomo", destination.name)
        XCTAssertTrue(http.requests.isEmpty)
    }

    func testTypedAddressWithSeveralResultsOffersChoices() async {
        search.results["Via Roma"] = [
            Destination(latitude: 45.07, longitude: 7.68, name: "Via Roma", details: "Torino"),
            Destination(latitude: 41.9, longitude: 12.5, name: "Via Roma", details: "Roma"),
        ]

        let outcome = await resolver.resolveTyped("Via Roma")

        guard case .choices(_, let candidates) = outcome else {
            return XCTFail("got \(outcome)")
        }
        XCTAssertEqual(2, candidates.count)
    }

    func testNoResults() async {
        let outcome = await resolver.resolveTyped("nowhere at all")
        XCTAssertEqual(.failed("No results for \"nowhere at all\"."), outcome)
    }

    func testSearchErrorIsReported() async {
        search.error = HttpClientError("grpc failed")
        let outcome = await resolver.resolveTyped("Via Roma")
        XCTAssertEqual(.failed("Search failed: grpc failed"), outcome)
    }

    func testMissingSearchIsExplained() async {
        let offline = DestinationResolver(shortLinkResolver: ShortLinkResolver(http: http), placeSearch: FakePlaceSearch(available: false))
        let outcome = await offline.resolveTyped("Via Roma")
        guard case .failed(let reason) = outcome else {
            return XCTFail("got \(outcome)")
        }
        XCTAssertTrue(reason.contains("not available"))
    }

    func testGeoLink() async {
        let outcome = await resolver.resolveLink("geo:0,0?q=45.1,9.2(Garage)", title: "", details: "", source: DestinationResolver.sourceLink)
        guard case .resolved(let destination, _) = outcome else {
            return XCTFail("got \(outcome)")
        }
        XCTAssertEqual("Garage", destination.name)
        XCTAssertTrue(http.requests.isEmpty)
    }

    func testUnreachableShortLinkWithoutHints() async {
        http.fail("Unable to resolve host")
        let outcome = await resolver.resolveTyped(Fixtures.shortLink)
        XCTAssertEqual(.failed("Could not open the link: Unable to resolve host"), outcome)
    }
}
