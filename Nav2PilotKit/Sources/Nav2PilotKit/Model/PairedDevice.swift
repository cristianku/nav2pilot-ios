import Foundation

/// Which remote backend is used to reach a device.
public enum BackendKind: String {
    case commaAthena = "comma_athena"
    case sunnylink = "sunnylink"

    public static func fromId(_ id: String) -> BackendKind {
        if id == BackendKind.sunnylink.rawValue {
            return .sunnylink
        }
        return .commaAthena
    }
}

public struct PairedDevice: Equatable, Identifiable {
    public var dongleId: String
    public var alias: String
    public var deviceType: String
    /// Unix timestamp in seconds, as returned by `last_athena_ping` in /v1/me/devices/. 0 when unknown.
    public var lastAthenaPingSeconds: Int64
    public var isOwner: Bool
    public var backend: BackendKind
    public var addedManually: Bool

    public init(
        dongleId: String,
        alias: String,
        deviceType: String = "",
        lastAthenaPingSeconds: Int64 = 0,
        isOwner: Bool = true,
        backend: BackendKind = .commaAthena,
        addedManually: Bool = false
    ) {
        self.dongleId = dongleId
        self.alias = alias
        self.deviceType = deviceType
        self.lastAthenaPingSeconds = lastAthenaPingSeconds
        self.isOwner = isOwner
        self.backend = backend
        self.addedManually = addedManually
    }

    public var id: String {
        return dongleId
    }

    public func displayName() -> String {
        if !alias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return alias
        }
        return dongleId
    }
}

public enum DongleIdRules {
    public static func normalize(_ text: String) -> String {
        return text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// comma API schema: "A unique 16-character hexadecimal string", pattern ^[0-9a-f]{16}$
    public static func isValid(_ dongleId: String) -> Bool {
        if dongleId.count != 16 {
            return false
        }
        let allowed = "0123456789abcdef"
        for character in dongleId {
            if !allowed.contains(character) {
                return false
            }
        }
        return true
    }
}
