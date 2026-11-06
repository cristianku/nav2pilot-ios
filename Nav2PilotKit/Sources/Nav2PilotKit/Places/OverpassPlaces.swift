import Foundation

/// Public Overpass API servers (OpenStreetMap data, free and without a key), tried in this order.
public enum OverpassEndpoints {
    /// Answers in under a second, but has only Switzerland and the land along its border.
    public static let switzerland = "https://overpass.osm.ch/api/interpreter"

    public static let interpreters = [
        "https://overpass-api.de/api/interpreter",
        // the main server answers 429 or 504 when it is busy
        "https://overpass.private.coffee/api/interpreter",
    ]

    /// The servers for `area`: the Swiss one first when its middle is around Switzerland.
    public static func forArea(_ area: MapArea) -> [String] {
        let center = area.center()
        if (45.8...47.9).contains(center.latitude) && (5.9...10.5).contains(center.longitude) {
            return [switzerland] + interpreters
        }
        return interpreters
    }
}

/// Points of interest from OpenStreetMap through the Overpass API: the places of one category in the part of the
/// map the user sees, nearest to its middle first. Works for everybody, with or without a Mapbox token.
public final class OverpassPlaces {
    private let http: HttpClient
    private let endpoints: (MapArea) -> [String]
    /// Asked when no Overpass server gave an answer.
    private let reserve: PhotonPlaces?

    /// Places shown on the map at most; more would hide it.
    public static let maxPlaces = 50

    // fetched to pick the maxPlaces nearest to the middle
    private static let maxFetched = 200

    // a busy server takes half a minute or more: better the next one, and in the end the reserve
    private static let serverTimeoutSeconds: TimeInterval = 6

    public init(
        http: HttpClient,
        endpoints: @escaping (MapArea) -> [String] = OverpassEndpoints.forArea,
        reserve: PhotonPlaces? = nil
    ) {
        self.http = http
        self.endpoints = endpoints
        self.reserve = reserve
    }

    public func search(_ category: PlaceCategory, in area: MapArea) async -> Result<[Place], TransportError> {
        let body = "data=" + OverpassPlaces.formEncode(OverpassPlaces.query(category, area))
        var failure = TransportError.network("no Overpass server")
        var noneInSwitzerland = false
        for endpoint in endpoints(area) {
            let request = HttpRequest(
                method: "POST",
                url: endpoint,
                headers: [
                    "Content-Type": "application/x-www-form-urlencoded",
                    "Accept": "application/json",
                ],
                body: body,
                timeoutSeconds: OverpassPlaces.serverTimeoutSeconds
            )
            let response: HttpResponse
            do {
                response = try await http.execute(request)
            } catch {
                failure = .network(error.localizedDescription)
                continue
            }
            // a query the server cannot read: the others would refuse it too
            if response.code == 400 {
                return .failure(.httpFailure(code: response.code, detail: ErrorText.fromHttpBody(response.body)))
            }
            // busy, down or refusing this client: the next server may answer
            if response.code == 429 {
                failure = .rateLimited
                continue
            }
            if !response.isSuccessful() {
                failure = .httpFailure(code: response.code, detail: ErrorText.fromHttpBody(response.body))
                continue
            }
            guard let json = Json.parseObject(response.body) else {
                failure = .malformed(ErrorText.shorten(response.body))
                continue
            }
            let places = OverpassPlaces.parsePlaces(json, category: category, center: area.center(), limit: OverpassPlaces.maxPlaces)
            // a query that ran out of time or memory comes back as 200 with a remark and no elements
            let remark = Json.string(json, "remark").trimmingCharacters(in: .whitespacesAndNewlines)
            if places.isEmpty && !remark.isEmpty {
                failure = .deviceRejected(ErrorText.shorten(remark))
                continue
            }
            // the Swiss server stops at the border: the places may be just across it
            if places.isEmpty && endpoint == OverpassEndpoints.switzerland {
                noneInSwitzerland = true
                continue
            }
            return .success(places)
        }
        if let reserved = await reserve?.search(category, in: area), case .success(let places) = reserved, !places.isEmpty {
            return reserved
        }
        if noneInSwitzerland {
            return .success([])
        }
        return .failure(failure)
    }

    /// Overpass QL: nodes, ways and relations with the category's tags in `area`; ways and relations as their centre.
    static func query(_ category: PlaceCategory, _ area: MapArea) -> String {
        let box = String(
            format: "%.5f,%.5f,%.5f,%.5f",
            locale: Locale(identifier: "en_US_POSIX"),
            area.south,
            area.west,
            area.north,
            area.east
        )
        return "[out:json][timeout:10];nwr" + category.filter + "(" + box + ");out center \(maxFetched);"
    }

    static func parsePlaces(_ json: [String: Any], category: PlaceCategory, center: LatLng, limit: Int) -> [Place] {
        var found: [Place] = []
        guard let elements = json["elements"] as? [Any] else {
            return found
        }
        for item in elements {
            guard let element = item as? [String: Any] else {
                continue
            }
            // a node has its own position, a way or a relation the centre Overpass adds with "out center"
            var position = element
            if let elementCenter = element["center"] as? [String: Any] {
                position = elementCenter
            }
            guard let latitude = Json.double(position, "lat"), let longitude = Json.double(position, "lon") else {
                continue
            }
            if !CoordinateRules.isValid(latitude: latitude, longitude: longitude) {
                continue
            }
            let tags = element["tags"] as? [String: Any] ?? [:]
            found.append(
                Place(category: category, latitude: latitude, longitude: longitude, name: placeName(tags, category), details: address(tags))
            )
        }
        let nearest = found.sorted { first, second in
            let firstDistance = RouteShaping.distanceMeters(center, LatLng(latitude: first.latitude, longitude: first.longitude))
            let secondDistance = RouteShaping.distanceMeters(center, LatLng(latitude: second.latitude, longitude: second.longitude))
            return firstDistance < secondDistance
        }
        return Array(nearest.prefix(limit))
    }

    private static func placeName(_ tags: [String: Any], _ category: PlaceCategory) -> String {
        for key in ["name", "brand", "operator"] {
            let value = text(tags, key)
            if !value.isEmpty {
                return value
            }
        }
        return category.singular
    }

    /// "Hauptstrasse 12, 5070 Frick" from the addr:* tags; "" without them.
    private static func address(_ tags: [String: Any]) -> String {
        var street = text(tags, "addr:street")
        if street.isEmpty {
            street = text(tags, "addr:place")
        }
        let number = text(tags, "addr:housenumber")
        if !street.isEmpty && !number.isEmpty {
            street = street + " " + number
        }
        var town: [String] = []
        for key in ["addr:postcode", "addr:city"] {
            let value = text(tags, key)
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

    private static func text(_ tags: [String: Any], _ key: String) -> String {
        return Json.string(tags, key).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The form body's value: letters, digits and -._* stay, everything else is %XX (a space too, which Overpass
    /// accepts like a +).
    static func formEncode(_ text: String) -> String {
        var allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        allowed.insert(charactersIn: "-._*")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
    }
}
