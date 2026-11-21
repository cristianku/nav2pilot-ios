import XCTest
@testable import Nav2PilotKit

@MainActor final class BaselParkingTests: XCTestCase {
    func testVeronaPublicCarsOnlyAndFreshConsistentCounts() async throws {
        let http = FakeHttpClient()
        http.respond(200, #"{"Numeri Parcheggi":[{"id":"211","ts":"1795255410","parcheggio":"Tribunale","posti_liberi":"0","posti_totali":"340","parkingNumberOfOccupiedSpaces":"340"},{"id":"216","ts":"1795255410","parcheggio":"Polo Zanotto","posti_liberi":"0","posti_totali":"133","parkingNumberOfOccupiedSpaces":"211"},{"id":"218","ts":"1795255410","parcheggio":"Terminal Bus","posti_liberi":"45","posti_totali":"60"}]}"#)
        let feeds = ParkingFeeds.covering(MapArea(south:45.42, west:10.98, north:45.45, east:11.01))
        let rows = try await XCTUnwrap(feeds.first).load(http) { [] }
        XCTAssertEqual(rows.map(\.id), ["AMT3 Verona:211","AMT3 Verona:216"])
        let then = Date(timeIntervalSince1970:1795255410)
        XCTAssertEqual(rows[0].level(at:then), .full)
        XCTAssertEqual(rows[0].level(at:then.addingTimeInterval(301)), .unknown)
        XCTAssertEqual(rows[1].level(at:then), .unknown)
    }
    func testSingaporeResolvesCarsByFacilityIDAndSeparatesFullFromStale() async throws {
        let feed = ParkingFeeds(city: .singapore, lat: 0, lon: 0), http = FakeHttpClient()
        http.respond(200, #"{"items":[{"carpark_data":[{"carpark_number":"A1","update_datetime":"2026-11-20T20:00:00","carpark_info":[{"lot_type":"Y","lots_available":"40"},{"lot_type":"C","lots_available":"2","total_lots":"50"}]}]}]}"#)
        let rows = try await feed.load(http) { [] }
        let g = try XCTUnwrap(rows.first)
        XCTAssertEqual(g.total, 50)
        XCTAssertEqual(g.free, 2)
        let whenMeasured = try XCTUnwrap(ISO8601DateFormatter().date(from:"2026-11-20T12:00:00Z"))
        XCTAssertEqual(g.level(at: whenMeasured), .few)
        XCTAssertEqual(g.level(at: whenMeasured.addingTimeInterval(301)), .unknown)
        XCTAssertEqual(g.point.latitude, 1.366714, accuracy: 0.001)
    }
    func testBookingsDoNotTurnAGeneralHomepageIntoAReservationAndReviewsMatchIdentity() {
        XCTAssertTrue(PlaceInfo.fromTags(["website":"https://kaisin.ch","reservation":"yes"]).booking.isEmpty)
        XCTAssertEqual(PlaceInfo.fromTags(["reservation:website":"https://tables.example/42"]).booking, "https://tables.example/42")
        let p = Place(category:.restaurant,latitude:47.55,longitude:7.59,name:"Example",details:"",osmID:"node/1")
        func row(_ id:String) -> [String:Any] { ["payload":["sub":"geo:47.55,7.59?q=Example","metadata":["osm_id":id],"opinion":"Test","rating":80]] }
        let reviews = PlaceDetails.parseReviews(["reviews":[row("node/2"),row("node/1/3")]],p)
        XCTAssertEqual(reviews.count,1)
        XCTAssertEqual(reviews.first?.stars,4)
    }
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
