import XCTest
@testable import Nav2PilotKit

@MainActor final class BaselParkingTests: XCTestCase {
    func testZeroMissingAndStaleCountsStayDistinct() async throws {
        func lookup(_ free: Any, _ status: String, _ age: TimeInterval, name: String = "City") async -> BaselParking.Garage? {
            let http = FakeHttpClient()
            let row: [String: Any] = ["title": "Parkhaus City", "name": "City", "address": "Uferstrasse 3",
                                      "published": ISO8601DateFormatter().string(from: Date().addingTimeInterval(-age)),
                                      "geo_point_2d": ["lat": 47.56, "lon": 7.59], "status": status, "free": free, "total": 10]
            http.respond(200, Json.serialize(["results": [row]]))
            let place = Place(category: .parking, latitude: 47.56, longitude: 7.59, name: name, details: "")
            return await BaselParking(http: http).lookup(place)
        }
        let full = await lookup(0, "offen", 30)
        let unknown = await lookup(NSNull(), "offen", 30)
        let closed = await lookup(3, "zu", 30)
        let stale = await lookup(3, "offen", 400)
        let nearby = await lookup(3, "offen", 30, name: "Parking")
        XCTAssertEqual(full?.availability, "Full")
        XCTAssertEqual(unknown?.availability, "Availability unknown")
        XCTAssertEqual(closed?.availability, "Closed")
        XCTAssertNil(stale)
        XCTAssertNil(nearby)
    }
}
