import Foundation

/// What the CarPlay screen shows and does, without the CarPlay framework so that `swift test` covers it.
///
/// Setup (comma token, Mapbox token, cars, favorites) stays on the iPhone: CarPlay apps must not show it, and
/// must not ask people to pick up the iPhone, so the texts only say what is missing.
@MainActor
public final class CarScreenModel {
    /// CPPointOfInterestTemplate shows at most 12 places.
    public static let maximumPlaces = 12

    private let tokenStore: TokenStore
    private let deviceRepository: DeviceRepository
    private let favoritesRepository: FavoritesRepository
    private let transports: TransportRegistry
    private let sender: DestinationSender

    public init(
        tokenStore: TokenStore,
        deviceRepository: DeviceRepository,
        favoritesRepository: FavoritesRepository,
        transports: TransportRegistry,
        mapboxTokenStore: TokenStore?
    ) {
        self.tokenStore = tokenStore
        self.deviceRepository = deviceRepository
        self.favoritesRepository = favoritesRepository
        self.transports = transports
        self.sender = DestinationSender(transports: transports, mapboxToken: {
            return mapboxTokenStore?.load()
        })
    }

    public var devices: [PairedDevice] {
        return deviceRepository.devices
    }

    public var favorites: [Favorite] {
        return favoritesRepository.favorites
    }

    public func selectedDevice() -> PairedDevice? {
        return deviceRepository.selectedDevice()
    }

    public func select(_ dongleId: String) {
        deviceRepository.select(dongleId)
    }

    /// Reads again what the app or the share extension changed (they write the same App Group).
    public func reload() {
        deviceRepository.reload()
        favoritesRepository.reload()
    }

    /// What is missing before anything can be sent, or nil.
    public func setupMessage() -> String? {
        if !tokenStore.hasToken() {
            return "No comma account in Nav2Pilot yet."
        }
        if deviceRepository.selectedDevice() == nil {
            return "No car in Nav2Pilot yet."
        }
        return nil
    }

    /// The destination alone: CarPlay has no route preview, so the car picks its own route.
    public func send(_ destination: Destination) async -> SendOutcome {
        guard let device = deviceRepository.selectedDevice() else {
            return SendOutcome(success: false, message: "No car in Nav2Pilot yet.")
        }
        return await sender.send(destination, to: device, waypoints: [])
    }

    public func clearDestination() async -> SendOutcome {
        guard let device = deviceRepository.selectedDevice() else {
            return SendOutcome(success: false, message: "No car in Nav2Pilot yet.")
        }
        let result = await transports.forDevice(device).clearDestination(device)
        switch result {
        case .success:
            return SendOutcome(success: true, message: "Destination cleared on \(device.displayName()).")
        case .failure(let error):
            return SendOutcome(success: false, message: TransportErrorText.describe(error))
        }
    }

    /// One line for the car list: online with the software version, or why it is not reachable.
    public func status(of device: PairedDevice) async -> String {
        let result = await transports.forDevice(device).checkStatus(device)
        switch result {
        case .success(let status):
            var text = "Online"
            if !status.version.isEmpty {
                text += " · " + status.version
            }
            if !status.branch.isEmpty {
                text += " (" + status.branch + ")"
            }
            return text
        case .failure(let error):
            return "Not reachable: " + TransportErrorText.describe(error)
        }
    }

    /// The nearest favorites first when the position is known, otherwise in the order they were added.
    public static func nearestFirst(_ favorites: [Favorite], from position: LatLng?, limit: Int) -> [Favorite] {
        var ordered = favorites
        if let here = position {
            ordered = favorites.sorted { first, second in
                return distanceMeters(first, from: here) < distanceMeters(second, from: here)
            }
        }
        if ordered.count > limit {
            return Array(ordered.prefix(limit))
        }
        return ordered
    }

    public static func distanceMeters(_ favorite: Favorite, from position: LatLng) -> Double {
        let destination = favorite.destination
        return RouteShaping.distanceMeters(position, LatLng(latitude: destination.latitude, longitude: destination.longitude))
    }
}
