import Foundation

public enum GoogleHosts {
    // google.com, google.it, google.co.uk, google.com.au, with optional www. or maps. prefix
    private static let googleHostPattern = Pattern(#"^(www\.|maps\.)?google\.(com|[a-z]{2}|co\.[a-z]{2}|com\.[a-z]{2})$"#)

    public static let consentHost = "consent.google.com"

    public static func isGoogleHost(_ host: String) -> Bool {
        return googleHostPattern.matches(host)
    }

    public static func isShortLink(_ parts: UrlParts) -> Bool {
        if parts.host == "maps.app.goo.gl" {
            return true
        }
        if parts.host == "goo.gl" && parts.path.hasPrefix("/maps") {
            return true
        }
        return false
    }

    public static func isGoogleMapsUrl(_ parts: UrlParts) -> Bool {
        if parts.scheme != "https" && parts.scheme != "http" {
            return false
        }
        if !isGoogleHost(parts.host) {
            return false
        }
        if parts.host.hasPrefix("maps.") {
            return true
        }
        if parts.path == "/maps" || parts.path.hasPrefix("/maps/") {
            return true
        }
        return false
    }
}

public enum AppleMapsHosts {
    /// Host of Apple's map links (unified Maps URLs and the older Map Links).
    public static let mapsHost = "maps.apple.com"

    /// Host of the short links Apple Maps puts in its share sheet (maps.apple/p/...).
    public static let shortLinkHost = "maps.apple"

    public static func isAppleMapsUrl(_ parts: UrlParts) -> Bool {
        if parts.scheme != "https" && parts.scheme != "http" {
            return false
        }
        return parts.host == mapsHost
    }

    public static func isShortLink(_ parts: UrlParts) -> Bool {
        if parts.scheme != "https" && parts.scheme != "http" {
            return false
        }
        return parts.host == shortLinkHost
    }
}
