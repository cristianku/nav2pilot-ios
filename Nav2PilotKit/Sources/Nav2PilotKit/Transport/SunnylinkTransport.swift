import Foundation

/// sunnylink backend: NOT IMPLEMENTED.
///
/// What is verified (README "sunnylink"):
/// - On the device, sunnylinkd registers the same JSON-RPC dispatcher as athenad, so setNavDestination
///   and clearNavDestination are reachable over the sunnylink websocket.
/// - The public sunnylink web frontend ships generated types for
///   POST https://athena.sunnylink.ai/navigation/{deviceId}/set_destination, but no documentation,
///   and its users authenticate through the frontend's own Logto OIDC client.
///
/// Not verified: an API contract and a supported way for a third-party app to obtain a sunnylink token.
/// Until both exist this backend reports notImplemented instead of guessing.
public final class SunnylinkTransport: NavigationTransport {
    public static let reason = "sunnylink has no documented public API for third-party apps yet. Use the comma backend."

    public let kind = BackendKind.sunnylink
    public let displayName = "sunnylink"
    public let implemented = false

    public init() {}

    public func listDevices() async -> Result<[PairedDevice], TransportError> {
        return .failure(.notImplemented(SunnylinkTransport.reason))
    }

    public func checkStatus(_ device: PairedDevice) async -> Result<DeviceStatus, TransportError> {
        return .failure(.notImplemented(SunnylinkTransport.reason))
    }

    public func setDestination(_ device: PairedDevice, _ destination: Destination) async -> Result<Delivery, TransportError> {
        return .failure(.notImplemented(SunnylinkTransport.reason))
    }

    public func setRoute(_ device: PairedDevice, _ destination: Destination, waypoints: [RouteWaypoint]) async -> Result<Delivery, TransportError> {
        return .failure(.notImplemented(SunnylinkTransport.reason))
    }

    public func clearDestination(_ device: PairedDevice) async -> Result<Delivery, TransportError> {
        return .failure(.notImplemented(SunnylinkTransport.reason))
    }
}
