import Foundation

/// Points of interest from Photon, komoot's public search over OpenStreetMap: the reserve when no Overpass server
/// answers. Quick and worldwide, but it knows only the places that have a name, and not who may use a car park.
public final class PhotonPlaces {
    public static let endpoint = "https://photon.komoot.io/reverse"

    private static let timeoutSeconds: TimeInterval = 8

    private let http: HttpClient
    private let endpoint: String

    public init(http: HttpClient, endpoint: String = PhotonPlaces.endpoint) {
        self.http = http
        self.endpoint = endpoint
    }

    public func search(_ category: PlaceCategory, in area: MapArea) async -> Result<[Place], TransportError> {
        let request = HttpRequest(
            method: "GET",
            url: PhotonPlaces.url(endpoint, category, area),
            headers: ["Accept": "application/json"],
            timeoutSeconds: PhotonPlaces.timeoutSeconds
        )
        let response: HttpResponse
        do {
            response = try await http.execute(request)
        } catch {
            return .failure(.network(error.localizedDescription))
        }
        if !response.isSuccessful() {
            return .failure(.httpFailure(code: response.code, detail: ErrorText.fromHttpBody(response.body)))
        }
        guard let json = Json.parseObject(response.body) else {
            return .failure(.malformed(ErrorText.shorten(response.body)))
        }
        return .success(PhotonPlaces.parsePlaces(json, category: category, area: area))
    }

    /// The circle around the area's middle that holds all of it, and the category's tags.
    static func url(_ endpoint: String, _ category: PlaceCategory, _ area: MapArea) -> String {
        let center = area.center()
        let corner = LatLng(latitude: area.north, longitude: area.east)
        let radiusKm = Int((RouteShaping.distanceMeters(center, corner) / 1000).rounded(.up))
        let position = String(
            format: "lat=%.5f&lon=%.5f",
            locale: Locale(identifier: "en_US_POSIX"),
            center.latitude,
            center.longitude
        )
        let tags = category.tags.map { "&osm_tag=" + $0 }.joined()
        return endpoint + "?" + position + "&radius=\(radiusKm)&limit=\(OverpassPlaces.maxPlaces)" + tags
    }

    /// The places inside `area`, nearest to its middle first: the circle asked for is larger than the area.
    static func parsePlaces(_ json: [String: Any], category: PlaceCategory, area: MapArea) -> [Place] {
        var found: [Place] = []
        guard let features = json["features"] as? [Any] else {
            return found
        }
        for item in features {
            guard let feature = item as? [String: Any],
                let geometry = feature["geometry"] as? [String: Any],
                let coordinates = geometry["coordinates"] as? [NSNumber],
                coordinates.count >= 2
            else {
                continue
            }
            let longitude = coordinates[0].doubleValue
            let latitude = coordinates[1].doubleValue
            if !CoordinateRules.isValid(latitude: latitude, longitude: longitude) {
                continue
            }
            if latitude < area.south || latitude > area.north || longitude < area.west || longitude > area.east {
                continue
            }
            let properties = feature["properties"] as? [String: Any] ?? [:]
            var name = text(properties, "name")
            if name.isEmpty {
                name = category.singular
            }
            // Photon's own key and value are the place's main tag; the category's first without them
            var kind = category.tags.first ?? ""
            let key = text(properties, "osm_key")
            let value = text(properties, "osm_value")
            if !key.isEmpty && !value.isEmpty {
                kind = key + ":" + value
            }
            found.append(
                Place(category: category, latitude: latitude, longitude: longitude, name: name, details: address(properties), kind: kind)
            )
        }
        let center = area.center()
        return found.sorted { first, second in
            let firstDistance = RouteShaping.distanceMeters(center, LatLng(latitude: first.latitude, longitude: first.longitude))
            let secondDistance = RouteShaping.distanceMeters(center, LatLng(latitude: second.latitude, longitude: second.longitude))
            return firstDistance < secondDistance
        }
    }

    /// "Hauptstrasse 12, 5070 Frick"; "" without an address.
    private static func address(_ properties: [String: Any]) -> String {
        var street = text(properties, "street")
        let number = text(properties, "housenumber")
        if !street.isEmpty && !number.isEmpty {
            street = street + " " + number
        }
        var town: [String] = []
        for key in ["postcode", "city"] {
            let value = text(properties, key)
            if !value.isEmpty {
                town.append(value)
            }
        }
        var parts: [String] = []
        if !street.isEmpty {
            parts.append(street)
        }
        if !town.isEmpty {
            parts.append(town.joined(separator: " "))
        }
        return parts.joined(separator: ", ")
    }

    private static func text(_ properties: [String: Any], _ key: String) -> String {
        return Json.string(properties, key).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
