import Foundation

/// Mapbox endpoints. Each user signs up for their own free Mapbox account and pastes its default public token:
/// Mapbox has no API for a third-party app to create an account or a token.
public enum MapboxEndpoints {
    public static let signupUrl = "https://account.mapbox.com/auth/signup/"
    public static let tokensPageUrl = "https://console.mapbox.com/account/access-tokens/"

    /// Tokens API, "Retrieve a token": answers {"code": "TokenValid" | "TokenInvalid" | "TokenExpired" | ...}.
    public static let tokenCheckUrl = "https://api.mapbox.com/tokens/v2"

    /// Directions API v5, same profile as the device's navd (openpilot selfdrive/navigation/navd.py).
    public static let directionsUrl = "https://api.mapbox.com/directions/v5/mapbox/driving-traffic/"
}

public enum MapboxTokenRules {
    /// Public tokens start with "pk."; secret ("sk.") and temporary ("tk.") tokens must not be stored in an app.
    public static func isPublicToken(_ token: String) -> Bool {
        if !token.hasPrefix("pk.") {
            return false
        }
        return token.components(separatedBy: ".").count == 3
    }

    public static func isSecretToken(_ token: String) -> Bool {
        return token.hasPrefix("sk.")
    }
}

public enum MapboxTokenCheck: Equatable {
    case valid
    case rejected(String)
    case failed(TransportError)
}

/// Checks a Mapbox token with the Tokens API before it is stored.
public final class MapboxTokenVerifier {
    private let http: HttpClient

    public init(http: HttpClient) {
        self.http = http
    }

    public func verify(_ token: String) async -> MapboxTokenCheck {
        var components = URLComponents(string: MapboxEndpoints.tokenCheckUrl)
        components?.queryItems = [URLQueryItem(name: "access_token", value: token)]
        guard let url = components?.url?.absoluteString else {
            return .failed(.invalidRequest("Invalid token"))
        }

        let response: HttpResponse
        do {
            response = try await http.execute(HttpRequest(method: "GET", url: url, headers: ["Accept": "application/json"]))
        } catch {
            return .failed(.network(error.localizedDescription))
        }
        guard let json = Json.parseObject(response.body) else {
            return .failed(.httpFailure(code: response.code, detail: ErrorText.fromHttpBody(response.body)))
        }
        let code = Json.string(json, "code")
        if code == "TokenValid" {
            return .valid
        }
        if code.isEmpty {
            return .failed(.httpFailure(code: response.code, detail: ErrorText.fromHttpBody(response.body)))
        }
        return .rejected(code)
    }
}
