import Foundation

public enum LinkParseResult: Equatable {
    /// Coordinates were found in the link.
    case found(Destination)
    /// The link only names a place or address; it has to be geocoded.
    case query(String)
    case notRecognized
}

/// Extracts a destination from a map link without any network access.
///
/// Supported:
/// - geo: URIs (RFC 5870 and the Android "geo:0,0?q=..." form)
/// - google.navigation:q=...
/// - Google Maps URLs (Maps URLs API `api=1` links, /maps/place, /maps/search, /maps/dir, legacy q= / ll= links)
/// - Apple Maps URLs (unified Maps URLs /place, /directions, /search, /frame and the older Map Links parameters)
///
/// Short links (maps.app.goo.gl, maps.apple/p/...) carry no coordinates; they are expanded by ShortLinkResolver first.
public enum MapLinkParser {
    // Place pin inside the "data=" blob: ...!3d<latitude>!4d<longitude>...
    // Not a documented format; observed in links that maps.app.goo.gl redirects to. It is preferred over
    // the "@lat,lng,zoom" viewport because the viewport can be kilometres away from the place.
    private static let placePinPattern = Pattern(#"!3d(-?\d{1,3}(?:\.\d+)?)!4d(-?\d{1,3}(?:\.\d+)?)"#)

    // Map viewport centre: /@<latitude>,<longitude>,<zoom>z
    private static let viewportPattern = Pattern(#"@(-?\d{1,3}(?:\.\d+)?),(-?\d{1,3}(?:\.\d+)?)"#)

    // Google parameters that name the destination, most specific first.
    private static let googleDestinationParameterNames = ["destination", "daddr", "query", "q"]

    public static let exactRank = 3

    public static func parse(_ link: String) -> LinkParseResult {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercase = trimmed.lowercased()
        if lowercase.hasPrefix("geo:") {
            return parseGeoUri(trimmed)
        }
        if lowercase.hasPrefix("google.navigation:") {
            return parseGoogleNavigation(trimmed)
        }
        guard let parts = UrlParts.parse(trimmed) else {
            return .notRecognized
        }
        if GoogleHosts.isGoogleMapsUrl(parts) {
            return parseGoogleMapsUrl(parts)
        }
        if AppleMapsHosts.isAppleMapsUrl(parts) {
            return parseAppleMapsUrl(parts)
        }
        return .notRecognized
    }

    /// Higher is better: exact coordinates, then a viewport centre, then a text query.
    public static func rank(_ result: LinkParseResult) -> Int {
        switch result {
        case .found(let destination):
            if destination.approximate {
                return 2
            }
            return 3
        case .query:
            return 1
        case .notRecognized:
            return 0
        }
    }

    // MARK: - Google Maps

    private static func parseGoogleMapsUrl(_ parts: UrlParts) -> LinkParseResult {
        let decodedPath = UrlParts.decode(parts.path)
        var segments: [String] = []
        for segment in decodedPath.components(separatedBy: "/") {
            let cleaned = segment.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty {
                segments.append(cleaned)
            }
        }
        let placeName = placeNameFromSegments(segments)

        // 1. place pin from the data blob (last one wins: it is the selected place)
        var pin: LatLng?
        for match in placePinPattern.allMatches(decodedPath) {
            if let latitude = Double(match.groups[0]), let longitude = Double(match.groups[1]) {
                if CoordinateRules.isValid(latitude: latitude, longitude: longitude) {
                    pin = LatLng(latitude: latitude, longitude: longitude)
                }
            }
        }
        if let pin = pin {
            return .found(Destination(latitude: pin.latitude, longitude: pin.longitude, name: placeName))
        }

        // 2. destination / daddr / query / q parameters
        var queryText = ""
        for parameterName in googleDestinationParameterNames {
            guard let value = parts.parameter(parameterName) else {
                continue
            }
            let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleaned.isEmpty {
                continue
            }
            if let coordinates = CoordinateParser.parse(cleaned) {
                return .found(Destination(latitude: coordinates.latitude, longitude: coordinates.longitude, name: placeName))
            }
            if queryText.isEmpty {
                queryText = cleaned
            }
        }

        // 3. coordinates or a place written in the path (/maps/search/<x>, /maps/place/<x>, /maps/dir/.../<x>)
        let pathTarget = destinationFromSegments(segments)
        if !pathTarget.isEmpty {
            if let coordinates = CoordinateParser.parse(pathTarget) {
                return .found(Destination(latitude: coordinates.latitude, longitude: coordinates.longitude, name: placeName))
            }
            // a /maps/place/<name> segment is only a label; it is used as a last resort (step 7)
            if queryText.isEmpty && pathTarget != placeName {
                queryText = pathTarget
            }
        }

        // 4. legacy ll= parameter (documented by Google as the map centre, hence approximate)
        if let llValue = parts.parameter("ll") {
            if let coordinates = CoordinateParser.parse(llValue) {
                return .found(
                    Destination(latitude: coordinates.latitude, longitude: coordinates.longitude, name: placeName, approximate: true)
                )
            }
        }

        // 5. an explicit text query is a better destination than the viewport
        if !queryText.isEmpty {
            return .query(queryText)
        }

        // 6. viewport centre
        if let viewport = viewportPattern.firstMatch(decodedPath) {
            if let latitude = Double(viewport.groups[0]), let longitude = Double(viewport.groups[1]) {
                if CoordinateRules.isValid(latitude: latitude, longitude: longitude) {
                    return .found(Destination(latitude: latitude, longitude: longitude, name: placeName, approximate: true))
                }
            }
        }

        // 7. the place name alone
        if !placeName.isEmpty {
            return .query(placeName)
        }
        return .notRecognized
    }

    private static func isNonTargetSegment(_ segment: String) -> Bool {
        if segment.hasPrefix("@") {
            return true
        }
        if segment.hasPrefix("data=") {
            return true
        }
        return false
    }

    /// The text after /maps/place/, unless it is a coordinate pair.
    private static func placeNameFromSegments(_ segments: [String]) -> String {
        guard let placeIndex = segments.firstIndex(of: "place") else {
            return ""
        }
        if placeIndex + 1 >= segments.count {
            return ""
        }
        let candidate = segments[placeIndex + 1]
        if isNonTargetSegment(candidate) {
            return ""
        }
        if CoordinateParser.parse(candidate) != nil {
            return ""
        }
        return candidate
    }

    private static func destinationFromSegments(_ segments: [String]) -> String {
        if let directionsIndex = segments.firstIndex(of: "dir") {
            var lastTarget = ""
            var index = directionsIndex + 1
            while index < segments.count {
                let segment = segments[index]
                if !isNonTargetSegment(segment) {
                    lastTarget = segment
                }
                index += 1
            }
            return lastTarget
        }
        for keyword in ["search", "place"] {
            if let keywordIndex = segments.firstIndex(of: keyword) {
                if keywordIndex + 1 < segments.count {
                    let candidate = segments[keywordIndex + 1]
                    if !isNonTargetSegment(candidate) {
                        return candidate
                    }
                }
            }
        }
        return ""
    }

    // MARK: - Apple Maps

    /// Apple Maps links.
    ///
    /// Unified Maps URLs (Apple developer documentation "Adopting unified Maps URLs", iOS 18.4+):
    /// /place?coordinate=&name=&address=, /directions?destination=, /search?query=&center=, /frame?center=.
    /// The older Map Links parameters are redirected by maps.apple.com to those forms (checked 2026-10-17):
    /// ll+q -> /place?coordinate=<ll>&name=<q>, ll alone -> /frame?center=, daddr -> /directions?destination=,
    /// q -> /search?query=, address -> /place?address=. They are handled here the same way, without the redirect.
    private static func parseAppleMapsUrl(_ parts: UrlParts) -> LinkParseResult {
        let name = trimmedParameter(parts, "name")
        let address = trimmedParameter(parts, "address")
        let legacyQuery = trimmedParameter(parts, "q")

        // 1. the place pin
        if let coordinates = CoordinateParser.parse(trimmedParameter(parts, "coordinate")) {
            return .found(Destination(latitude: coordinates.latitude, longitude: coordinates.longitude, name: name, details: address))
        }

        // 2. legacy ll together with a q label: Apple turns it into /place?coordinate=<ll>&name=<q>
        if let coordinates = CoordinateParser.parse(trimmedParameter(parts, "ll")) {
            if !legacyQuery.isEmpty {
                var label = legacyQuery
                if CoordinateParser.parse(legacyQuery) != nil {
                    label = name
                }
                return .found(Destination(latitude: coordinates.latitude, longitude: coordinates.longitude, name: label, details: address))
            }
        }

        // 3. directions destination, then address and search texts
        var queryText = ""
        for parameterName in ["destination", "daddr", "address", "query", "q"] {
            let value = trimmedParameter(parts, parameterName)
            if value.isEmpty {
                continue
            }
            if let coordinates = CoordinateParser.parse(value) {
                return .found(Destination(latitude: coordinates.latitude, longitude: coordinates.longitude, name: name))
            }
            if queryText.isEmpty {
                queryText = value
            }
        }
        if !queryText.isEmpty {
            return .query(queryText)
        }

        // 4. only a map centre
        for parameterName in ["center", "ll", "sll"] {
            if let coordinates = CoordinateParser.parse(trimmedParameter(parts, parameterName)) {
                return .found(
                    Destination(latitude: coordinates.latitude, longitude: coordinates.longitude, name: name, approximate: true)
                )
            }
        }

        if !name.isEmpty {
            return .query(name)
        }
        return .notRecognized
    }

    private static func trimmedParameter(_ parts: UrlParts, _ name: String) -> String {
        guard let value = parts.parameter(name) else {
            return ""
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - geo: and google.navigation:

    private static func parseGeoUri(_ uri: String) -> LinkParseResult {
        let body = String(uri.dropFirst("geo:".count))
        var coordinatePart = body
        var queryPart = ""
        if let questionIndex = body.firstIndex(of: "?") {
            coordinatePart = String(body[body.startIndex..<questionIndex])
            queryPart = String(body[body.index(after: questionIndex)...])
        }

        let query = parameterValue(UrlParts.parseQuery(queryPart), "q").trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            var coordinateText = query
            var label = ""
            if let labelStart = query.firstIndex(of: "(") {
                coordinateText = String(query[query.startIndex..<labelStart])
                let afterLabelStart = query.index(after: labelStart)
                if let labelEnd = query.lastIndex(of: ")"), labelEnd > labelStart {
                    label = String(query[afterLabelStart..<labelEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    label = String(query[afterLabelStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            if let coordinates = CoordinateParser.parse(coordinateText) {
                return .found(Destination(latitude: coordinates.latitude, longitude: coordinates.longitude, name: label))
            }
            return .query(query)
        }

        // RFC 5870 parameters such as ";u=35" follow the coordinates
        if let parameterStart = coordinatePart.firstIndex(of: ";") {
            coordinatePart = String(coordinatePart[coordinatePart.startIndex..<parameterStart])
        }
        guard let coordinates = CoordinateParser.parse(UrlParts.decode(coordinatePart)) else {
            return .notRecognized
        }
        if coordinates.latitude == 0.0 && coordinates.longitude == 0.0 {
            return .notRecognized
        }
        return .found(Destination(latitude: coordinates.latitude, longitude: coordinates.longitude))
    }

    private static func parseGoogleNavigation(_ uri: String) -> LinkParseResult {
        let body = String(uri.dropFirst("google.navigation:".count))
        let query = parameterValue(UrlParts.parseQuery(body), "q").trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            return .notRecognized
        }
        if let coordinates = CoordinateParser.parse(query) {
            return .found(Destination(latitude: coordinates.latitude, longitude: coordinates.longitude))
        }
        return .query(query)
    }

    private static func parameterValue(_ parameters: [QueryParameter], _ name: String) -> String {
        for parameter in parameters {
            if parameter.name == name {
                return parameter.value
            }
        }
        return ""
    }
}
