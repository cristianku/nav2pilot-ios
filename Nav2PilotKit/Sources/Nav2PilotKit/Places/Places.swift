import Foundation

/// A kind of point of interest in the map's places menu.
///
/// `filter` is the Overpass QL tag filter that makes it in OpenStreetMap, `tags` the same as Photon's key:value
/// pairs; `singular` names a place that has no name of its own there.
public enum PlaceCategory: String, CaseIterable, Identifiable {
    case fuel
    case charging
    case parking
    case restArea
    case restaurant
    case cafe
    case supermarket
    case hotel
    case pharmacy

    public var id: String {
        return rawValue
    }

    public var label: String {
        switch self {
        case .fuel: return "Fuel stations"
        case .charging: return "EV charging"
        case .parking: return "Parking"
        case .restArea: return "Rest areas"
        case .restaurant: return "Restaurants"
        case .cafe: return "Cafés"
        case .supermarket: return "Supermarkets"
        case .hotel: return "Hotels"
        case .pharmacy: return "Pharmacies"
        }
    }

    public var singular: String {
        switch self {
        case .fuel: return "Fuel station"
        case .charging: return "Charging station"
        case .parking: return "Parking"
        case .restArea: return "Rest area"
        case .restaurant: return "Restaurant"
        case .cafe: return "Café"
        case .supermarket: return "Supermarket"
        case .hotel: return "Hotel"
        case .pharmacy: return "Pharmacy"
        }
    }

    public var tags: [String] {
        switch self {
        case .fuel: return ["amenity:fuel"]
        case .charging: return ["amenity:charging_station"]
        case .parking: return ["amenity:parking"]
        case .restArea: return ["highway:services", "highway:rest_area"]
        case .restaurant: return ["amenity:restaurant", "amenity:fast_food"]
        case .cafe: return ["amenity:cafe"]
        case .supermarket: return ["shop:supermarket"]
        case .hotel: return ["tourism:hotel", "tourism:motel"]
        case .pharmacy: return ["amenity:pharmacy"]
        }
    }

    public var filter: String {
        switch self {
        case .fuel: return #"["amenity"="fuel"]"#
        case .charging: return #"["amenity"="charging_station"]"#
        // private car parks are mapped too, and nobody can use them
        case .parking: return #"["amenity"="parking"]["access"!~"^(private|no)$"]"#
        // motorway service areas ("services") and lay-bys with tables and toilets ("rest_area")
        case .restArea: return #"["highway"~"^(services|rest_area)$"]"#
        case .restaurant: return #"["amenity"~"^(restaurant|fast_food)$"]"#
        case .cafe: return #"["amenity"="cafe"]"#
        case .supermarket: return #"["shop"="supermarket"]"#
        case .hotel: return #"["tourism"~"^(hotel|motel)$"]"#
        case .pharmacy: return #"["amenity"="pharmacy"]"#
        }
    }
}

/// A point of interest from OpenStreetMap, drawn on the map.
public struct Place: Equatable {
    public let category: PlaceCategory
    public let latitude: Double
    public let longitude: Double
    public let name: String
    /// The address, "" when OpenStreetMap has none.
    public let details: String

    public init(category: PlaceCategory, latitude: Double, longitude: Double, name: String, details: String) {
        self.category = category
        self.latitude = latitude
        self.longitude = longitude
        self.name = name
        self.details = details
    }

    public func toDestination() -> Destination {
        return Destination(latitude: latitude, longitude: longitude, name: name, details: details)
    }
}

/// A box of latitudes and longitudes: the part of the map the user sees, where the places are looked for.
public struct MapArea: Equatable {
    public let south: Double
    public let west: Double
    public let north: Double
    public let east: Double

    public init(south: Double, west: Double, north: Double, east: Double) {
        self.south = south
        self.west = west
        self.north = north
        self.east = east
    }

    public func center() -> LatLng {
        return LatLng(latitude: (south + north) / 2, longitude: (west + east) / 2)
    }

    /// The same centre, at most `maxHalfMeters` to each side: a zoomed-out map is searched in its middle.
    public func limited(to maxHalfMeters: Double) -> MapArea {
        let middle = center()
        let halfLatitude = min((north - south) / 2, maxHalfMeters / MapArea.metersPerDegree)
        let halfLongitude = min((east - west) / 2, maxHalfMeters / MapArea.metersPerDegreeOfLongitude(middle.latitude))
        return MapArea(
            south: max(-90.0, middle.latitude - halfLatitude),
            west: middle.longitude - halfLongitude,
            north: min(90.0, middle.latitude + halfLatitude),
            east: middle.longitude + halfLongitude
        )
    }

    private static let metersPerDegree = 111_320.0

    // near the poles a degree of longitude shrinks to nothing: kept above a kilometre
    private static func metersPerDegreeOfLongitude(_ latitude: Double) -> Double {
        return max(metersPerDegree * cos(latitude * .pi / 180), 1_000.0)
    }
}
