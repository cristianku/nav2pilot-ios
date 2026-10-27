import Foundation

/// How a send ended, with the text shown to the user.
public struct SendOutcome: Equatable {
    public let success: Bool
    public let message: String

    public init(success: Bool, message: String) {
        self.success = success
        self.message = message
    }
}

/// Sends a destination the same way from the app, the share extension and CarPlay: the user's Mapbox token
/// first, so the car's first route request already uses it, then the destination alone or with its waypoints.
public final class DestinationSender {
    private let transports: TransportRegistry
    private let mapboxToken: () -> String?

    public init(transports: TransportRegistry, mapboxToken: @escaping () -> String?) {
        self.transports = transports
        self.mapboxToken = mapboxToken
    }

    public func send(_ destination: Destination, to device: PairedDevice, waypoints: [RouteWaypoint]) async -> SendOutcome {
        let transport = transports.forDevice(device)
        if let token = mapboxToken() {
            // silent on purpose: a car that is off, or runs software without setMapboxToken, keeps routing as before
            _ = await transport.setMapboxToken(device, token)
        }
        let result: Result<Delivery, TransportError>
        if waypoints.isEmpty {
            result = await transport.setDestination(device, destination)
        } else {
            result = await transport.setRoute(device, destination, waypoints: waypoints)
        }
        switch result {
        case .success(let delivery):
            var message = "Destination sent to \(device.displayName())."
            if !waypoints.isEmpty {
                message = "Route sent to \(device.displayName())."
            }
            if delivery.queued {
                message = "Queued by athena: \(delivery.note)"
            } else if !delivery.note.isEmpty {
                message = "Destination sent to \(device.displayName()). " + delivery.note
            }
            return SendOutcome(success: true, message: message)
        case .failure(let error):
            return SendOutcome(success: false, message: TransportErrorText.describe(error))
        }
    }
}
