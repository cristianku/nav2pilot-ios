import XCTest
@testable import Nav2PilotKit

private let photon = "https://photon.example/reverse"
private let overpass = "https://overpass.example/api/interpreter"

private let sanFrancisco = MapArea(south: 37.72, west: -122.48, north: 37.82, east: -122.36)

private let photonAnswer = """
{"features": [
    {"geometry": {"coordinates": [-122.30, 37.77]}, "properties": {"name": "Across the bay"}},
    {"geometry": {"coordinates": [-122.45, 37.75]}, "properties": {"name": "Far"}},
    {"geometry": {"coordinates": [-122.42, 37.77]}, "properties": {"name": "Near", "street": "Market St", "housenumber": "1", "postcode": "94103", "city": "San Francisco"}},
    {"geometry": {"coordinates": [-122.41, 37.76]}, "properties": {}}
]}
"""

final class PhotonPlacesTests: XCTestCase {
    private func withReserve(_ http: FakeHttpClient) -> OverpassPlaces {
        return OverpassPlaces(http: http, endpoints: { _ in [overpass] }, reserve: PhotonPlaces(http: http, endpoint: photon))
    }

    func testUrlAsksAllTheCategoryTagsInACircleAroundTheArea() {
        XCTAssertEqual(
            photon + "?lat=37.77000&lon=-122.42000&radius=8&limit=50&osm_tag=amenity:restaurant&osm_tag=amenity:fast_food",
            PhotonPlaces.url(photon, .restaurant, sanFrancisco)
        )
    }

    func testParsePlacesKeepsTheAreaAndPutsTheNearestFirst() throws {
        let json = try XCTUnwrap(Json.parseObject(photonAnswer))
        let places = PhotonPlaces.parsePlaces(json, category: .fuel, area: sanFrancisco)

        XCTAssertEqual(["Near", "Fuel station", "Far"], places.map { $0.name })
        XCTAssertEqual("Market St 1, 94103 San Francisco", places[0].details)
        XCTAssertEqual(37.77, places[0].latitude, accuracy: 0.0001)
        XCTAssertEqual(-122.42, places[0].longitude, accuracy: 0.0001)
    }

    func testTheReserveAnswersWhenNoOverpassServerDoes() async {
        let http = FakeHttpClient()

        http.fail("timeout")
        http.respond(200, photonAnswer)
        let result = await withReserve(http).search(.fuel, in: sanFrancisco)

        guard case .success(let found) = result else {
            return XCTFail("expected places, got \(result)")
        }
        XCTAssertEqual(3, found.count)
        XCTAssertEqual("GET", http.requests[1].method)
        XCTAssertTrue(http.requests[1].url.hasPrefix(photon))
    }

    func testAReserveWithNothingLeavesTheOverpassError() async {
        let http = FakeHttpClient()

        http.respond(504, "<html>Gateway Timeout</html>")
        http.respond(200, #"{"features": []}"#)
        let empty = await withReserve(http).search(.fuel, in: sanFrancisco)
        guard case .failure(.httpFailure(let code, _)) = empty else {
            return XCTFail("expected HTTP 504, got \(empty)")
        }
        XCTAssertEqual(504, code)

        http.respond(504, "<html>Gateway Timeout</html>")
        http.fail("timeout")
        let down = await withReserve(http).search(.fuel, in: sanFrancisco)
        guard case .failure(.httpFailure(let downCode, _)) = down else {
            return XCTFail("expected HTTP 504, got \(down)")
        }
        XCTAssertEqual(504, downCode)
    }

    func testOverpassAnsweringMeansNoReserve() async {
        let http = FakeHttpClient()

        http.respond(200, #"{"elements": []}"#)
        let none = await withReserve(http).search(.fuel, in: sanFrancisco)
        XCTAssertEqual(.success([]), none)
        XCTAssertEqual(1, http.requests.count)
    }
}
