import Foundation

/// The request is city-wide: the selected pin and the phone's position never leave the phone.
@MainActor public final class BaselParking {
    private let http: HttpClient
    private var fetched = Date.distantPast
    private var garages: [Garage] = []
    private var pending: Task<[Garage], Never>?

    public init(http: HttpClient) { self.http = http }

    public func lookup(_ place: Place) async -> Garage? {
        guard place.category == .parking, (47.52...47.59).contains(place.latitude),
              (7.55...7.63).contains(place.longitude) else { return nil }
        let matches = await load().filter { $0.matches(place) }
        guard matches.count == 1, matches[0].isFresh(at: Date()) else { return nil }
        return matches[0]
    }

    func places(in area: MapArea) async -> [Place] {
        guard area.north >= 47.52, area.south <= 47.59, area.east >= 7.55, area.west <= 7.63 else { return [] }
        return await load().filter {
            $0.point.latitude >= area.south && $0.point.latitude <= area.north &&
                $0.point.longitude >= area.west && $0.point.longitude <= area.east
        }.map { Place(category: .parking, latitude: $0.point.latitude, longitude: $0.point.longitude, name: $0.title,
                      details: $0.address, kind: "amenity:parking") }
    }

    func merge(_ official: [Place], with osm: [Place]) -> [Place] {
        var remaining = osm
        let pins = official.map { pin in
            guard let garage = garages.first(where: { $0.title == pin.name }) else { return pin }
            let indexes = remaining.indices.filter { garage.matches(remaining[$0]) }
            guard indexes.count == 1 else { return pin }
            let other = remaining.remove(at: indexes[0])
            return Place(category: .parking, latitude: pin.latitude, longitude: pin.longitude, name: pin.name,
                         details: pin.details, kind: pin.kind, info: other.info, parkingNotes: other.parkingNotes)
        }
        return pins + remaining
    }

    private func load() async -> [Garage] {
        if Date().timeIntervalSince(fetched) >= 60 {
            if pending == nil {
                pending = Task {
                    let request = HttpRequest(method: "GET", url: "https://data.bs.ch/api/explore/v2.1/catalog/datasets/100088/records?limit=100", timeoutSeconds: 5)
                    guard let response = try? await http.execute(request), response.isSuccessful(),
                          let rows = Json.parseObject(response.body)?["results"] as? [[String: Any]] else { return [] }
                    return rows.compactMap(Garage.init)
                }
            }
            garages = await pending?.value ?? []
            fetched = Date()
            pending = nil
        }
        return garages
    }

    public struct Garage {
        public let title: String
        public let address: String
        public let published: Date
        let point: LatLng
        let status: String
        let free: Int?
        let total: Int?

        init?(_ row: [String: Any]) {
            guard let title = row["title"] as? String, row["name"] is String,
                  let geo = row["geo_point_2d"] as? [String: Any],
                  let lat = Json.double(geo, "lat"), let lon = Json.double(geo, "lon"),
                  (47.52...47.59).contains(lat), (7.55...7.63).contains(lon),
                  let published = ISO8601DateFormatter().date(from: Json.string(row, "published")) else { return nil }
            self.title = title
            self.address = Json.string(row, "address")
            self.point = LatLng(latitude: lat, longitude: lon)
            self.published = published
            self.status = Json.string(row, "status")
            self.free = row["free"] as? Int
            self.total = row["total"] as? Int
        }

        func isFresh(at now: Date) -> Bool { (-60...300).contains(now.timeIntervalSince(published)) }

        func matches(_ place: Place) -> Bool {
            guard RouteShaping.distanceMeters(point, LatLng(latitude: place.latitude, longitude: place.longitude)) <= 150 else { return false }
            func words(_ text: String) -> [String] {
                text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
            }
            func name(_ text: String) -> [String] { words(text).filter { !["parkhaus", "parking", "garage", "basel"].contains($0) } }
            let pin = name(place.name)
            if !pin.isEmpty { return pin == name(title) }
            let street = words(String(place.details.prefix { $0 != "," }))
            return address.contains(where: \.isNumber) && street == words(address)
        }

        public var availability: String {
            if status == "zu" || status == "geschlossen" { return "Closed" }
            guard status == "offen", let free, free >= 0 else { return "Availability unknown" }
            if let total, total <= 0 || free > total { return "Availability unknown" }
            if free == 0 { return "Full" }
            if let total { return "\(free) of \(total) spaces free" }
            return "\(free) spaces free"
        }
    }
}
