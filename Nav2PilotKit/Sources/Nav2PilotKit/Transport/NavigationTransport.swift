import Foundation

public enum TransportError: Error, Equatable {
    case noToken
    case unauthorized
    case forbidden
    case rateLimited
    case methodNotAvailable(String)
    case deviceRejected(String)
    case invalidRequest(String)
    case deviceError(String)
    case httpFailure(code: Int, detail: String)
    case network(String)
    case malformed(String)
    case notImplemented(String)
}

/// Software running on the device, from athenad's getVersion.
public struct DeviceStatus: Equatable {
    public let version: String
    public let branch: String
    public let remote: String
    public let commit: String

    public init(version: String, branch: String, remote: String, commit: String) {
        self.version = version
        self.branch = branch
        self.remote = remote
        self.commit = commit
    }
}

/// How the backend acknowledged a command.
public struct Delivery: Equatable {
    /// True when the backend stored the command for later delivery instead of reaching the device.
    public let queued: Bool
    public let note: String
}

public struct AccountInfo: Equatable {
    public let email: String
}

/// A backend able to deliver navigation commands to a device.
///
/// Implementations: CommaAthenaTransport (comma athena JSON-RPC, verified) and SunnylinkTransport (stub).
public protocol NavigationTransport: AnyObject {
    var kind: BackendKind { get }
    var displayName: String { get }
    var implemented: Bool { get }

    func listDevices() async -> Result<[PairedDevice], TransportError>

    func checkStatus(_ device: PairedDevice) async -> Result<DeviceStatus, TransportError>

    func setDestination(_ device: PairedDevice, _ destination: Destination) async -> Result<Delivery, TransportError>

    /// The destination with waypoints in driving order. Falls back to the destination alone when the device
    /// has no waypoint support; Delivery.note then says so.
    func setRoute(_ device: PairedDevice, _ destination: Destination, waypoints: [RouteWaypoint]) async -> Result<Delivery, TransportError>

    func clearDestination(_ device: PairedDevice) async -> Result<Delivery, TransportError>

    /// The user's Mapbox public token, for the route requests of the device itself; an empty token removes it.
    func setMapboxToken(_ device: PairedDevice, _ token: String) async -> Result<Delivery, TransportError>
}
