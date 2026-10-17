import Foundation

/// comma endpoints used by Nav2Pilot. Every value is documented; sources are listed in README "Verified API".
public enum CommaEndpoints {
    /// REST API host: https://api.comma.ai docs; openpilot common/api/comma_connect.py API_HOST.
    public static let apiBaseUrl = "https://api.commadotai.com"

    /// Athena HTTP: "POST /:dongle_id" on https://athena.comma.ai (api.comma.ai docs, comma-api openapi.yaml).
    public static let athenaBaseUrl = "https://athena.comma.ai"

    /// Profile of the authenticated user (openpilot tools/lib/auth.py validates tokens with it).
    /// With the trailing slash: "/v1/me" answers 308 to "/v1/me/" (checked 2026-10-17), and URLSession
    /// drops the Authorization header when it follows that redirect.
    public static let profilePath = "/v1/me/"

    /// "List devices owned or readable by authenticated user" (api.comma.ai docs).
    public static let devicesPath = "/v1/me/devices/"

    /// Where users generate a JWT (api.comma.ai docs, "Authentication").
    public static let tokenPageUrl = "https://jwt.comma.ai"

    public static let methodSetNavDestination = "setNavDestination"
    /// sunnypilot (cristianku/sunnypilot feature/nav-alpha, sunnypilot/navd/athena.py): destination plus waypoints.
    public static let methodSetNavRoute = "setNavRoute"
    public static let methodClearNavDestination = "clearNavDestination"
    public static let methodGetVersion = "getVersion"
}
