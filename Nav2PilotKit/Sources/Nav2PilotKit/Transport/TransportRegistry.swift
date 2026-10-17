import Foundation

public final class TransportRegistry {
    public let comma: CommaAthenaTransport
    public let sunnylink: SunnylinkTransport

    public init(comma: CommaAthenaTransport, sunnylink: SunnylinkTransport) {
        self.comma = comma
        self.sunnylink = sunnylink
    }

    public func forBackend(_ kind: BackendKind) -> NavigationTransport {
        if kind == .sunnylink {
            return sunnylink
        }
        return comma
    }

    public func forDevice(_ device: PairedDevice) -> NavigationTransport {
        return forBackend(device.backend)
    }
}

public enum TransportErrorText {
    public static func describe(_ error: TransportError) -> String {
        switch error {
        case .noToken:
            return "No comma token stored. Add one in Devices."
        case .unauthorized:
            return "The comma token was rejected (HTTP 401). It may be expired: generate a new one."
        case .forbidden:
            return "This account has no access to the device (HTTP 403)."
        case .rateLimited:
            return "Too many requests (HTTP 429). Try again in a moment."
        case .methodNotAvailable(let method):
            return "The device does not support \(method). It needs openpilot or sunnypilot with Nav Alpha."
        case .deviceRejected(let reason):
            return "Rejected by the device: \(reason)"
        case .invalidRequest(let reason):
            return "Invalid request: \(reason)"
        case .deviceError(let reason):
            return "Device error: \(reason)"
        case .httpFailure(let code, let detail):
            return "Device unreachable or request refused (HTTP \(code)): \(detail)"
        case .network(let detail):
            return "Network error: \(detail)"
        case .malformed(let detail):
            return "Unexpected response: \(detail)"
        case .notImplemented(let reason):
            return reason
        }
    }
}
