import XCTest
@testable import Nav2PilotKit

final class CoordinateParserTests: XCTestCase {
    func testAcceptsCommaSpaceAndSemicolonSeparators() {
        let expected = LatLng(latitude: 45.4642, longitude: 9.19)
        XCTAssertEqual(expected, CoordinateParser.parse("45.4642, 9.19"))
        XCTAssertEqual(expected, CoordinateParser.parse("45.4642,9.19"))
        XCTAssertEqual(expected, CoordinateParser.parse("45.4642 9.19"))
        XCTAssertEqual(expected, CoordinateParser.parse("  45.4642;9.19  "))
    }

    func testAcceptsSignsAndLocPrefix() {
        XCTAssertEqual(LatLng(latitude: -33.8688, longitude: 151.2093), CoordinateParser.parse("-33.8688, +151.2093"))
        XCTAssertEqual(LatLng(latitude: 47.5951518, longitude: -122.3316393), CoordinateParser.parse("loc: 47.5951518,-122.3316393"))
        XCTAssertEqual(LatLng(latitude: 47.5951518, longitude: -122.3316393), CoordinateParser.parse("47.5951518 ,-122.3316393"))
    }

    func testRejectsOutOfRangeValuesLikeAthena() {
        XCTAssertNil(CoordinateParser.parse("91, 0"))
        XCTAssertNil(CoordinateParser.parse("0, -181"))
        XCTAssertNotNil(CoordinateParser.parse("90, 180"))
        XCTAssertNotNil(CoordinateParser.parse("-90, -180"))
    }

    func testRejectsTextThatIsNotACoordinatePair() {
        XCTAssertNil(CoordinateParser.parse(""))
        XCTAssertNil(CoordinateParser.parse("Piazza del Duomo, Milano"))
        XCTAssertNil(CoordinateParser.parse("45.4642"))
        XCTAssertNil(CoordinateParser.parse("45.4642, 9.19, 12"))
        XCTAssertNil(CoordinateParser.parse("1970 Naglee Ave San Jose"))
        XCTAssertNil(CoordinateParser.parse("45.4642, 9.19\nmore"))
    }

    func testCoordinateRulesRejectNanAndInfinity() {
        XCTAssertFalse(CoordinateRules.isValid(latitude: .nan, longitude: 0))
        XCTAssertFalse(CoordinateRules.isValid(latitude: 0, longitude: .infinity))
        XCTAssertFalse(CoordinateRules.isValid(latitude: -.infinity, longitude: 0))
        XCTAssertTrue(CoordinateRules.isValid(latitude: 0, longitude: 0))
    }

    func testDongleIdRules() {
        XCTAssertTrue(DongleIdRules.isValid("1a2b3c4d5e6f7a8b"))
        XCTAssertFalse(DongleIdRules.isValid("1A2B3C4D5E6F7A8B"))
        XCTAssertFalse(DongleIdRules.isValid("1a2b3c4d5e6f7a8"))
        XCTAssertFalse(DongleIdRules.isValid("1a2b3c4d5e6f7a8g"))
        XCTAssertEqual("1a2b3c4d5e6f7a8b", DongleIdRules.normalize(" 1A2B3C4D5E6F7A8B \n"))
    }

    func testCoordinatesTextIsLocaleIndependent() {
        XCTAssertEqual("45.464200, 9.190000", Destination(latitude: 45.4642, longitude: 9.19).coordinatesText())
    }
}

final class MapLinkParserTests: XCTestCase {
    private func found(_ link: String, file: StaticString = #filePath, line: UInt = #line) -> Destination {
        let result = MapLinkParser.parse(link)
        guard let destination = foundDestination(result) else {
            XCTFail("expected coordinates for \(link) but got \(result)", file: file, line: line)
            return Destination(latitude: 0, longitude: 0)
        }
        return destination
    }

    private func query(_ link: String, file: StaticString = #filePath, line: UInt = #line) -> String {
        let result = MapLinkParser.parse(link)
        guard let text = queryText(result) else {
            XCTFail("expected a query for \(link) but got \(result)", file: file, line: line)
            return ""
        }
        return text
    }

    private func assertCoordinates(_ destination: Destination, _ latitude: Double, _ longitude: Double, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(latitude, destination.latitude, accuracy: 0.0000001, file: file, line: line)
        XCTAssertEqual(longitude, destination.longitude, accuracy: 0.0000001, file: file, line: line)
    }

    func testPlacePinWinsOverViewport() {
        // Real redirect target of a maps.app.goo.gl link: the viewport (@43.676,6.990) is far from the pin.
        let destination = found(Fixtures.shortLinkTarget)
        assertCoordinates(destination, 43.695783, 7.260654)
        XCTAssertEqual("Copenhagen Coffee Lab", destination.name)
        XCTAssertFalse(destination.approximate)
    }

    func testMapsUrlsApiSearchAndDirections() {
        // https://developers.google.com/maps/documentation/urls/get-started
        assertCoordinates(found("https://www.google.com/maps/search/?api=1&query=47.5951518%2C-122.3316393"), 47.5951518, -122.3316393)
        assertCoordinates(found("https://www.google.com/maps/search/?api=1&query=47.5951518+,-122.3316393"), 47.5951518, -122.3316393)
        assertCoordinates(found("https://www.google.com/maps/dir/?api=1&destination=47.5951518,+-122.3316393"), 47.5951518, -122.3316393)
        XCTAssertEqual("Pike Place Market, Seattle", query("https://www.google.com/maps/search/?api=1&query=Pike+Place+Market%2C+Seattle"))
    }

    func testLegacyQueryParameters() {
        assertCoordinates(found("https://maps.google.com/?q=45.4642,9.19"), 45.4642, 9.19)
        assertCoordinates(found("http://maps.google.co.uk/maps?q=loc:+47.5951518,-122.3316393&z=15"), 47.5951518, -122.3316393)
        assertCoordinates(found("https://maps.google.de/maps?q=47.5951518,-122.3316393&z=17&t=k"), 47.5951518, -122.3316393)
        assertCoordinates(found("http://maps.google.com/maps?saddr=Here&daddr=45.1,9.2"), 45.1, 9.2)
    }

    func testLegacyLlIsApproximate() {
        let destination = found("http://maps.google.com/maps?q=%3Cname%3E&ie=UTF8&hl=en&hq=&ll=47.5951518,-122.3316393&spn=0,359.967062")
        assertCoordinates(destination, 47.5951518, -122.3316393)
        XCTAssertTrue(destination.approximate)
    }

    func testPathForms() {
        assertCoordinates(found("https://www.google.com/maps/search/47.5951518,-122.3316393"), 47.5951518, -122.3316393)
        assertCoordinates(found("https://www.google.com/maps/dir/Current+Location/47.5951518+,-122.3316393"), 47.5951518, -122.3316393)
        assertCoordinates(found("https://www.google.com/maps/place/45.4642,9.19/@45.4642,9.19,17z"), 45.4642, 9.19)
        XCTAssertEqual("1970 Naglee Ave San Jose, CA 95126", query("https://www.google.com/maps/dir//1970%20Naglee%20Ave%20San%20Jose,%20CA%2095126"))
        XCTAssertEqual("1970 Naglee Ave San Jose, CA 95126", query("https://www.google.com/maps/place/1970%20Naglee%20Ave%20San%20Jose,%20CA%2095126"))
    }

    func testViewportOnlyIsApproximateAndKeepsPlaceName() {
        let destination = found("https://www.google.com/maps/place/Duomo+di+Milano/@45.4640976,9.1897378,17z")
        assertCoordinates(destination, 45.4640976, 9.1897378)
        XCTAssertTrue(destination.approximate)
        XCTAssertEqual("Duomo di Milano", destination.name)
    }

    func testGeoUris() {
        assertCoordinates(found("geo:37.330593,-121.859425"), 37.330593, -121.859425)
        assertCoordinates(found("geo:37.330593,+-121.859425+;u=35"), 37.330593, -121.859425)
        assertCoordinates(found("geo:0,0?q=37.330593+,-121.859425"), 37.330593, -121.859425)

        let labelled = found("geo:0,0?q=37.330593,-121.859425%28Main+Street%29")
        assertCoordinates(labelled, 37.330593, -121.859425)
        XCTAssertEqual("Main Street", labelled.name)

        XCTAssertEqual("Main Street", found("geo:0,0?q=37.330593,-121.859425 (Main Street)").name)
        XCTAssertEqual("1970 Naglee Ave San Jose, CA 95126", query("geo:0,0?q=1970+Naglee+Ave+San+Jose,+CA+95126"))
    }

    func testGeoUriWithoutLocationIsNotRecognized() {
        XCTAssertEqual(.notRecognized, MapLinkParser.parse("geo:0,0"))
        XCTAssertEqual(.notRecognized, MapLinkParser.parse("geo:abc"))
        XCTAssertEqual(.notRecognized, MapLinkParser.parse("geo:0,0?q="))
    }

    func testGoogleNavigationUri() {
        assertCoordinates(found("google.navigation:q=47.5951518,-122.3316393"), 47.5951518, -122.3316393)
        XCTAssertEqual("1970 Naglee Ave San Jose, CA 95126", query("google.navigation:q=1970+Naglee+Ave+San+Jose,+CA+95126&mode=d"))
    }

    func testNonMapsLinksAreIgnored() {
        XCTAssertEqual(.notRecognized, MapLinkParser.parse("https://example.com/maps?q=45.1,9.2"))
        XCTAssertEqual(.notRecognized, MapLinkParser.parse("https://www.google.com/search?q=45.1,9.2"))
        XCTAssertEqual(.notRecognized, MapLinkParser.parse("https://google.evil.com/maps?q=45.1,9.2"))
        XCTAssertEqual(.notRecognized, MapLinkParser.parse("https://maps.apple.com.evil.org/place?coordinate=45.1,9.2"))
        // a short link has no coordinates until it is expanded
        XCTAssertEqual(.notRecognized, MapLinkParser.parse(Fixtures.shortLink))
        XCTAssertEqual(.notRecognized, MapLinkParser.parse("https://maps.apple/p/abc"))
    }

    func testHostRules() {
        XCTAssertTrue(GoogleHosts.isGoogleHost("www.google.com"))
        XCTAssertTrue(GoogleHosts.isGoogleHost("google.it"))
        XCTAssertTrue(GoogleHosts.isGoogleHost("maps.google.co.uk"))
        XCTAssertTrue(GoogleHosts.isGoogleHost("www.google.com.au"))
        XCTAssertFalse(GoogleHosts.isGoogleHost("google.com.evil.org"))
        XCTAssertFalse(GoogleHosts.isGoogleHost("notgoogle.com"))
        XCTAssertTrue(GoogleHosts.isShortLink(UrlParts.parse("https://maps.app.goo.gl/abc")!))
        XCTAssertTrue(GoogleHosts.isShortLink(UrlParts.parse("https://goo.gl/maps/abc")!))
        XCTAssertFalse(GoogleHosts.isShortLink(UrlParts.parse("https://goo.gl/other")!))
        XCTAssertTrue(AppleMapsHosts.isShortLink(UrlParts.parse("https://maps.apple/p/abc")!))
        XCTAssertFalse(AppleMapsHosts.isShortLink(UrlParts.parse("https://maps.apple.com/p/abc")!))
    }

    // Apple Maps: unified Maps URLs (developer.apple.com "Adopting unified Maps URLs")

    func testApplePlaceWithCoordinate() {
        let destination = found("https://maps.apple.com/place?coordinate=45.4642%2C9.19&name=Duomo&address=Piazza%20del%20Duomo%2C%20Milano")
        assertCoordinates(destination, 45.4642, 9.19)
        XCTAssertEqual("Duomo", destination.name)
        XCTAssertEqual("Piazza del Duomo, Milano", destination.details)
        XCTAssertFalse(destination.approximate)
    }

    func testAppleDirectionsSearchAndAddress() {
        assertCoordinates(found("https://maps.apple.com/directions?destination=45.4642%2C9.19&mode=driving"), 45.4642, 9.19)
        XCTAssertEqual("Piazza del Duomo, Milano", query("https://maps.apple.com/directions?destination=Piazza%20del%20Duomo%2C%20Milano"))
        XCTAssertEqual("Piazza del Duomo, Milano", query("https://maps.apple.com/place?address=Piazza%20del%20Duomo%2C%20Milano"))
        XCTAssertEqual("Duomo Milano", query("https://maps.apple.com/search?query=Duomo%20Milano&center=45.4,9.1"))
    }

    func testAppleFrameCentreIsApproximate() {
        let destination = found("https://maps.apple.com/frame?center=45.4642%2C9.19&span=0.05,0.05")
        assertCoordinates(destination, 45.4642, 9.19)
        XCTAssertTrue(destination.approximate)
    }

    func testAppleLegacyParametersMatchTheirRedirects() {
        // maps.apple.com redirects (checked 2026-10-17):
        // ?ll=45.4642,9.19&q=Duomo -> /place?coordinate=45.4642%2C9.19&name=Duomo
        let pinned = found("https://maps.apple.com/?ll=45.4642,9.19&q=Duomo")
        assertCoordinates(pinned, 45.4642, 9.19)
        XCTAssertEqual("Duomo", pinned.name)
        XCTAssertFalse(pinned.approximate)
        // ?ll=45.4642,9.19 -> /frame?center=45.4642%2C9.19
        XCTAssertTrue(found("http://maps.apple.com/?ll=45.4642,9.19").approximate)
        // ?daddr=45.4642,9.19 -> /directions?destination=45.4642%2C9.19
        XCTAssertFalse(found("https://maps.apple.com/?daddr=45.4642,9.19").approximate)
        // ?q=Duomo%20Milano -> /search?query=Duomo%20Milano
        XCTAssertEqual("Duomo Milano", query("https://maps.apple.com/?q=Duomo%20Milano"))
        // ?address=... -> /place?address=...
        XCTAssertEqual("Piazza del Duomo, Milano", query("https://maps.apple.com/?address=Piazza%20del%20Duomo,%20Milano"))
    }
}

final class ShareTextParserTests: XCTestCase {
    func testSplitsNameAddressAndLink() {
        let text = "Copenhagen Coffee Lab\n5 Rue de la Préfecture, 06300 Nice, France\nhttps://maps.app.goo.gl/gqhGPJxrF8E7MX479"
        let shared = ShareTextParser.parse(text, subject: "")
        XCTAssertEqual("https://maps.app.goo.gl/gqhGPJxrF8E7MX479", shared.link)
        XCTAssertEqual("Copenhagen Coffee Lab", shared.title)
        XCTAssertEqual("5 Rue de la Préfecture, 06300 Nice, France", shared.details)
    }

    func testLinkOnly() {
        let shared = ShareTextParser.parse("https://maps.app.goo.gl/abc", subject: "Duomo")
        XCTAssertEqual("https://maps.app.goo.gl/abc", shared.link)
        XCTAssertEqual("Duomo", shared.title)
        XCTAssertEqual("", shared.details)
    }

    func testLinkInsideSentenceAndTrailingPunctuation() {
        let shared = ShareTextParser.parse("Meet me here: https://maps.google.com/?q=45.1,9.2.", subject: "")
        XCTAssertEqual("https://maps.google.com/?q=45.1,9.2", shared.link)
        XCTAssertEqual("Meet me here:", shared.title)
    }

    func testGeoLinkIsDetected() {
        XCTAssertEqual("geo:45.1,9.2", ShareTextParser.parse("Parking\ngeo:45.1,9.2", subject: "").link)
    }

    func testNoLink() {
        let shared = ShareTextParser.parse("Via Roma 1\r\nTorino", subject: "")
        XCTAssertEqual("", shared.link)
        XCTAssertEqual("Via Roma 1", shared.title)
        XCTAssertEqual("Via Roma 1, Torino", shared.textWithoutLink)
    }

    func testUrlPartsDecodesParameters() {
        let parts = UrlParts.parse("https://WWW.Google.com:443/maps/search/?api=1&query=Pike+Place%2C+Seattle#frag")!
        XCTAssertEqual("https", parts.scheme)
        XCTAssertEqual("www.google.com", parts.host)
        XCTAssertEqual("/maps/search/", parts.path)
        XCTAssertEqual("1", parts.parameter("api"))
        XCTAssertEqual("Pike Place, Seattle", parts.parameter("query"))
        XCTAssertNil(parts.parameter("missing"))
    }

    func testMalformedPercentEscapesAreKept() {
        XCTAssertEqual("100% sure", UrlParts.decode("100%+sure"))
    }
}
