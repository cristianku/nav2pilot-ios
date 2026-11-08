import Foundation

public struct LatLng: Equatable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// A navigation destination.
///
/// Only `latitude` and `longitude` are sent to the device: athenad's setNavDestination accepts
/// exactly these two parameters (see README "Verified API"). `name`, `details`, `kind`, `phone` and
/// `website` are kept for display and favorites only.
///
/// `approximate` is true when the coordinates are a map viewport centre rather than a place pin.
public struct Destination: Equatable {
    public var latitude: Double
    public var longitude: Double
    public var name: String
    public var details: String
    public var approximate: Bool
    /// What the place is, as OpenStreetMap's main tag "shop:furniture" (Apple's categories are turned into the
    /// same, see PlaceKinds); "" for an address or when unknown.
    public var kind: String
    /// The phone number Apple's map has for the place; "" when none.
    public var phone: String
    /// Its web page, an http or https address; "" when none.
    public var website: String

    public init(
        latitude: Double,
        longitude: Double,
        name: String = "",
        details: String = "",
        approximate: Bool = false,
        kind: String = "",
        phone: String = "",
        website: String = ""
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.name = name
        self.details = details
        self.approximate = approximate
        self.kind = kind
        self.phone = phone
        self.website = website
    }

    public func coordinatesText() -> String {
        return String(format: "%.6f, %.6f", locale: Locale(identifier: "en_US_POSIX"), latitude, longitude)
    }

    public func displayName() -> String {
        if !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }
        return coordinatesText()
    }

    public func sameLocationAs(_ other: Destination) -> Bool {
        let latitudeDifference = abs(latitude - other.latitude)
        let longitudeDifference = abs(longitude - other.longitude)
        return latitudeDifference < Destination.sameLocationToleranceDegrees
            && longitudeDifference < Destination.sameLocationToleranceDegrees
    }

    // About 0.1 m: two destinations closer than this are the same place.
    private static let sameLocationToleranceDegrees = 0.000001
}

public enum CoordinateRules {
    /// Same acceptance rule as athenad's setNavDestination
    /// (`-90 <= latitude <= 90 and -180 <= longitude <= 180`), which also rejects NaN and infinity.
    public static func isValid(latitude: Double, longitude: Double) -> Bool {
        if latitude.isNaN || longitude.isNaN {
            return false
        }
        if latitude < -90.0 || latitude > 90.0 {
            return false
        }
        if longitude < -180.0 || longitude > 180.0 {
            return false
        }
        return true
    }
}
