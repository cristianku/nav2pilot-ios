import Foundation

/// One route of a Directions API answer, as drawn on the map.
public struct RoutePreview: Equatable {
    /// The full route geometry.
    public let coordinates: [LatLng]
    public let distanceMeters: Double
    public let durationSeconds: Double
    /// Main roads, from the legs' summaries ("A22, SS12").
    public let summary: String

    public init(coordinates: [LatLng], distanceMeters: Double, durationSeconds: Double, summary: String) {
        self.coordinates = coordinates
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
        self.summary = summary
    }
}

/// Route previews from the Mapbox Directions API with the user's own token.
///
/// Same profile as the device's navd (mapbox/driving-traffic), so the route picked on the phone is the one the
/// device recomputes when it gets the destination and the waypoints.
public final class MapboxDirections {
    private let http: HttpClient
    private let tokenProvider: () -> String?

    public init(http: HttpClient, tokenProvider: @escaping () -> String?) {
        self.http = http
        self.tokenProvider = tokenProvider
    }

    /// Fastest route first, then up to two alternatives (only without stops, as the device gets one route).
    public func routes(from origin: LatLng, stops: [LatLng], to destination: LatLng) async -> Result<[RoutePreview], TransportError> {
        guard let token = tokenProvider() else {
            return .failure(.noToken)
        }
        guard let url = MapboxDirections.requestUrl(from: origin, stops: stops, to: destination, token: token) else {
            return .failure(.invalidRequest("Too many stops"))
        }

        let response: HttpResponse
        do {
            response = try await http.execute(HttpRequest(method: "GET", url: url, headers: ["Accept": "application/json"]))
        } catch {
            return .failure(.network(error.localizedDescription))
        }
        if response.code == 401 {
            return .failure(.unauthorized)
        }
        if response.code == 429 {
            return .failure(.rateLimited)
        }
        guard let json = Json.parseObject(response.body) else {
            return .failure(.malformed(ErrorText.shorten(response.body)))
        }
        // "Ok", or e.g. "NoRoute" / "NoSegment" with a message
        let code = Json.string(json, "code")
        if code != "Ok" {
            var message = Json.string(json, "message")
            if message.isEmpty {
                message = code
            }
            return .failure(.deviceRejected(message))
        }
        return .success(MapboxDirections.parseRoutes(json))
    }

    static func requestUrl(from origin: LatLng, stops: [LatLng], to destination: LatLng, token: String) -> String? {
        // Directions API: up to 25 coordinates
        if stops.count > 23 {
            return nil
        }
        var points: [LatLng] = [origin]
        points.append(contentsOf: stops)
        points.append(destination)
        var pairs: [String] = []
        for point in points {
            pairs.append(String(format: "%.6f,%.6f", locale: Locale(identifier: "en_US_POSIX"), point.longitude, point.latitude))
        }

        var components = URLComponents(string: MapboxEndpoints.directionsUrl + pairs.joined(separator: ";"))
        var alternatives = "false"
        if stops.isEmpty {
            alternatives = "true"
        }
        components?.queryItems = [
            URLQueryItem(name: "alternatives", value: alternatives),
            URLQueryItem(name: "geometries", value: "geojson"),
            URLQueryItem(name: "overview", value: "full"),
            URLQueryItem(name: "steps", value: "false"),
            URLQueryItem(name: "access_token", value: token),
        ]
        return components?.url?.absoluteString
    }

    static func parseRoutes(_ json: [String: Any]) -> [RoutePreview] {
        var previews: [RoutePreview] = []
        guard let routes = json["routes"] as? [Any] else {
            return previews
        }
        for element in routes {
            guard let route = element as? [String: Any] else {
                continue
            }
            guard let geometry = route["geometry"] as? [String: Any], let pairs = geometry["coordinates"] as? [Any] else {
                continue
            }
            var coordinates: [LatLng] = []
            for pairElement in pairs {
                guard let pair = pairElement as? [Any], pair.count >= 2 else {
                    continue
                }
                guard let longitude = pair[0] as? NSNumber, let latitude = pair[1] as? NSNumber else {
                    continue
                }
                coordinates.append(LatLng(latitude: latitude.doubleValue, longitude: longitude.doubleValue))
            }
            if coordinates.count < 2 {
                continue
            }

            var summaries: [String] = []
            if let legs = route["legs"] as? [Any] {
                for legElement in legs {
                    if let leg = legElement as? [String: Any] {
                        let summary = Json.string(leg, "summary")
                        if !summary.isEmpty {
                            summaries.append(summary)
                        }
                    }
                }
            }

            previews.append(
                RoutePreview(
                    coordinates: coordinates,
                    distanceMeters: Json.double(route, "distance") ?? 0,
                    durationSeconds: Json.double(route, "duration") ?? 0,
                    summary: summaries.joined(separator: " · ")
                )
            )
        }
        return previews
    }
}

/// A point the device's route has to go through (sunnypilot setNavRoute).
public struct RouteWaypoint: Equatable {
    public let latitude: Double
    public let longitude: Double
    /// True for a silent point that only shapes the route, false for a stop.
    public let via: Bool

    public init(latitude: Double, longitude: Double, via: Bool) {
        self.latitude = latitude
        self.longitude = longitude
        self.via = via
    }
}

public enum RouteShaping {
    /// Silent via points that make the device's Mapbox request follow `route`: points at 25 %, 50 % and 75 % of
    /// its length. They lie on the route's own geometry, so Mapbox snaps them to the same roads.
    public static func viaPoints(along route: RoutePreview, fractions: [Double] = [0.25, 0.5, 0.75]) -> [RouteWaypoint] {
        let points = route.coordinates
        if points.count < 2 {
            return []
        }
        var cumulative: [Double] = [0]
        var index = 1
        while index < points.count {
            cumulative.append(cumulative[index - 1] + distanceMeters(points[index - 1], points[index]))
            index += 1
        }
        let total = cumulative[cumulative.count - 1]
        if total <= 0 {
            return []
        }

        var waypoints: [RouteWaypoint] = []
        for fraction in fractions {
            let target = total * fraction
            var segment = 1
            while segment < points.count - 1 && cumulative[segment] < target {
                segment += 1
            }
            let start = points[segment - 1]
            let end = points[segment]
            let length = cumulative[segment] - cumulative[segment - 1]
            var t = 0.0
            if length > 0 {
                t = (target - cumulative[segment - 1]) / length
            }
            let latitude = start.latitude + (end.latitude - start.latitude) * t
            let longitude = start.longitude + (end.longitude - start.longitude) * t
            waypoints.append(RouteWaypoint(latitude: latitude, longitude: longitude, via: true))
        }
        return waypoints
    }

    /// Great-circle distance (haversine), metres.
    public static func distanceMeters(_ a: LatLng, _ b: LatLng) -> Double {
        let earthRadius = 6_371_000.0
        let latitude1 = a.latitude * .pi / 180
        let latitude2 = b.latitude * .pi / 180
        let deltaLatitude = (b.latitude - a.latitude) * .pi / 180
        let deltaLongitude = (b.longitude - a.longitude) * .pi / 180
        let h = sin(deltaLatitude / 2) * sin(deltaLatitude / 2)
            + cos(latitude1) * cos(latitude2) * sin(deltaLongitude / 2) * sin(deltaLongitude / 2)
        return 2 * earthRadius * asin(min(1, sqrt(h)))
    }
}
