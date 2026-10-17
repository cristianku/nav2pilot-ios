import Foundation

/// Stores a token (the comma JWT, the user's Mapbox token) in the Keychain. The plain token is never logged,
/// never written anywhere else and never shown again in the UI after it is saved.
public final class TokenStore {
    public static let keyCommaToken = "comma_token"
    public static let keyMapboxToken = "mapbox_token"

    private let secrets: SecretStore
    private let key: String

    public init(secrets: SecretStore, key: String = TokenStore.keyCommaToken) {
        self.secrets = secrets
        self.key = key
    }

    public func save(_ token: String) throws {
        try secrets.write(key, TokenStore.normalize(token))
    }

    /// The token, or nil when none is stored.
    public func load() -> String? {
        guard let token = secrets.read(key) else {
            return nil
        }
        if token.isEmpty {
            return nil
        }
        return token
    }

    public func hasToken() -> Bool {
        return load() != nil
    }

    public func clear() {
        secrets.delete(key)
    }

    /// Accepts a pasted header value too ("JWT eyJ...").
    public static func normalize(_ token: String) -> String {
        var cleaned = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.lowercased().hasPrefix("jwt ") {
            cleaned = String(cleaned.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if cleaned.lowercased().hasPrefix("bearer ") {
            cleaned = String(cleaned.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return cleaned
    }
}
