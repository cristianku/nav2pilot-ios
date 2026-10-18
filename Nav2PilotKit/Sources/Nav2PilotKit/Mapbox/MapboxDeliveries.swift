import CryptoKit
import Foundation

/// Which device already got which Mapbox token, so a send delivers it only once per device and token.
///
/// Only a SHA-256 fingerprint of the token is kept, in the plain data store: the token itself stays in the Keychain.
public final class MapboxDeliveries {
    public static let keyPrefix = "mapbox_token_delivered_"

    private let store: KeyValueStore

    public init(store: KeyValueStore) {
        self.store = store
    }

    public func isDelivered(_ dongleId: String, token: String) -> Bool {
        guard let stored = store.getString(MapboxDeliveries.keyPrefix + dongleId) else {
            return false
        }
        return stored == MapboxDeliveries.fingerprint(token)
    }

    public func markDelivered(_ dongleId: String, token: String) {
        store.putString(MapboxDeliveries.keyPrefix + dongleId, MapboxDeliveries.fingerprint(token))
    }

    public func forget(_ dongleId: String) {
        store.remove(MapboxDeliveries.keyPrefix + dongleId)
    }

    static func fingerprint(_ token: String) -> String {
        let digest = SHA256.hash(data: Data(token.utf8))
        var hex = ""
        for byte in digest {
            hex += String(format: "%02x", byte)
        }
        return hex
    }
}
