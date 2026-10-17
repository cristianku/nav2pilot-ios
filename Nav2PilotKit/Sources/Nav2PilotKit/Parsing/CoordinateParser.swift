import Foundation

/// Parses "latitude, longitude" in decimal degrees.
///
/// Accepted separators: comma, semicolon or whitespace (the same as sunnypilot's on-device
/// parse_destination). An optional "loc:" prefix, used by old Google Maps links, is ignored.
public enum CoordinateParser {
    private static let coordinatePairPattern = Pattern(
        #"^\s*(?:loc:\s*)?([+-]?\d{1,3}(?:\.\d+)?)\s*[,;\s]\s*([+-]?\d{1,3}(?:\.\d+)?)\s*$"#,
        caseInsensitive: true
    )

    public static func parse(_ text: String) -> LatLng? {
        guard let match = coordinatePairPattern.matchEntire(text) else {
            return nil
        }
        guard let latitude = Double(match.groups[0]) else {
            return nil
        }
        guard let longitude = Double(match.groups[1]) else {
            return nil
        }
        if !CoordinateRules.isValid(latitude: latitude, longitude: longitude) {
            return nil
        }
        return LatLng(latitude: latitude, longitude: longitude)
    }
}
