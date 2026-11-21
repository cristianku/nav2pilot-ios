import Foundation

/// Public feeds are shared by visible pins and favorites; never send a saved name or precise coordinates.
@MainActor public final class BaselParking {
    private let http: HttpClient
    private var cache: [String: (Date, [Garage])] = [:]
    private var pending: [String: Task<[Garage], Never>] = [:]
    private var hkDirectory: (Date, [ParkingFeeds.Row])?
    public init(http: HttpClient) { self.http = http }

    private func readings(_ area: MapArea) async -> [Garage] {
        var seen = Set<String>(), result: [Garage] = []
        for feed in ParkingFeeds.covering(area) {
            guard !Task.isCancelled else { break }
            let rows: [Garage]
            if let (at, old) = cache[feed.key], Date().timeIntervalSince(at) < 60 {
                rows = old
            } else if let task = pending[feed.key] { rows = await task.value }
            else {
                let task = Task { () -> [Garage] in
                    do {
                        return try await feed.load(http) { [self] in
                            if let (at, rows) = hkDirectory, Date().timeIntervalSince(at) < 86400 { return rows }
                            let response = try await ParkingFeeds.get(http, ParkingFeeds.hkInfo)
                            let rows = try ParkingFeeds.rows(response, "results")
                            hkDirectory = (Date(), rows)
                            return rows
                        }
                    } catch { return cache[feed.key]?.1 ?? [] }
                }
                pending[feed.key] = task
                rows = await task.value
                cache[feed.key] = (Date(), rows)
                pending[feed.key] = nil
            }
            result += rows.filter { area.contains($0.point) && seen.insert($0.id).inserted }
        }
        return result
    }

    public func lookup(_ place: Place, id: String = "") async -> Garage? {
        guard place.category == .parking else { return nil }
        let a = MapArea(south: place.latitude-0.002, west: place.longitude-0.004, north: place.latitude+0.002, east: place.longitude+0.004)
        let matches = await readings(a).filter { id.isEmpty ? $0.matches(place) : $0.id == id }
        guard matches.count == 1, matches[0].isFresh(at: Date()) else { return nil }
        return matches[0]
    }

    func places(in area: MapArea) async -> [Place] {
        let center = area.center()
        return await readings(area).sorted { RouteShaping.distanceMeters(center, $0.point) < RouteShaping.distanceMeters(center, $1.point) }
            .prefix(100).map { g in
                var pin = Place(category: .parking, latitude: g.point.latitude, longitude: g.point.longitude,
                                name: g.title, details: g.address, kind: "amenity:parking")
                pin.garage = g
                pin.parkingStructure = g.structure
                return pin
            }
    }
    func merge(_ official: [Place], with osm: [Place]) -> [Place] {
        var removed = Set<Int>()
        let pins = official.map { pin -> Place in
            guard let g = pin.garage else { return pin }
            let matches = osm.indices.filter { g.matches(osm[$0]) }
            guard matches.count == 1, let i = matches.first, official.filter({ $0.garage?.matches(osm[i]) == true }).count == 1 else { return pin }
            removed.insert(i)
            var merged = Place(category: .parking, latitude: pin.latitude, longitude: pin.longitude, name: pin.name,
                               details: pin.details, kind: pin.kind, info: osm[i].info, parkingNotes: osm[i].parkingNotes,
                               capacity: osm[i].capacity, osmID: osm[i].osmID,
                               parkingStructure: pin.parkingStructure == .unknown ? osm[i].parkingStructure : pin.parkingStructure)
            merged.garage = g
            return merged
        }
        return pins + osm.indices.filter { !removed.contains($0) }.map { osm[$0] }
    }

    public enum Level { case available, few, full, closed, unknown }
    public struct Garage: Equatable {
        public let id, title, address, source, zone: String
        public let published: Date
        let point: LatLng
        let status: String
        public let free, total: Int?
        let age: TimeInterval
        public func isFresh(at now: Date) -> Bool { (-60...age).contains(now.timeIntervalSince(published)) }
        public func level(at now: Date) -> Level {
            guard isFresh(at: now) else { return .unknown }
            if ["zu","geschlossen","closed"].contains(status) { return .closed }
            guard ["offen","open"].contains(status), let free, free >= 0 else { return .unknown }
            if let total, total <= 0 || free > total { return .unknown }
            if free == 0 { return .full }
            return free <= 5 || free <= (total ?? 0)/10 ? .few : .available
        }
        public var structure: ParkingStructure = .unknown
        public var availability: String {
            switch level(at: Date()) {
            case .unknown: return "Availability unknown"
            case .closed: return "Closed"
            case .full: return "Full"
            default: return "\(free ?? 0) spaces free"
            }
        }
        func matches(_ place: Place) -> Bool {
            guard RouteShaping.distanceMeters(point, LatLng(latitude: place.latitude, longitude: place.longitude)) <= 150 else { return false }
            func words(_ s: String) -> [String] { s.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init) }
            func name(_ s: String) -> [String] { words(s).filter { !["parkhaus","parking","garage","basel","parcheggio"].contains($0) } }
            let n = name(place.name)
            if !n.isEmpty { return n == name(title) }
            let street = String(place.details.prefix { $0 != "," })
            return street.contains(where: \.isNumber) && words(street) == words(String(address.prefix { $0 != "," }))
        }
    }
}
extension MapArea {
    func contains(_ point: LatLng) -> Bool {
        point.latitude >= south && point.latitude <= north && point.longitude >= west && point.longitude <= east
    }
}
