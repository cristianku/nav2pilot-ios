import Foundation
import Observation

public enum ConnectionState: Equatable {
    case unknown
    case checking
    case online(DeviceStatus)
    case unreachable(String)
}

/// What the route map needs: the user's Mapbox token, the Directions API and the phone's position.
public struct RoutePlanning {
    public let mapboxTokenStore: TokenStore
    public let verifier: MapboxTokenVerifier
    public let directions: MapboxDirections
    public let location: LocationProvider

    public init(mapboxTokenStore: TokenStore, verifier: MapboxTokenVerifier, directions: MapboxDirections, location: LocationProvider) {
        self.mapboxTokenStore = mapboxTokenStore
        self.verifier = verifier
        self.directions = directions
        self.location = location
    }
}

public struct SendFeedback: Equatable {
    public let success: Bool
    public let message: String
    public let time: Date
}

/// State and actions shared by the app screens and the share extension.
///
/// Every action is `async` and returns when its work is done, so the UI wraps calls in a Task and the
/// tests simply await them. A newer resolve or connection check makes the result of an older one obsolete.
@MainActor
@Observable
public final class MainViewModel {
    // destination
    public private(set) var destination: Destination?
    public private(set) var destinationSource = ""
    public private(set) var resolving = false
    public private(set) var resolveError = ""
    public private(set) var choices: [Destination] = []

    // device commands
    public private(set) var connection = ConnectionState.unknown
    public private(set) var sending = false
    public private(set) var feedback: SendFeedback?

    // account and devices
    public private(set) var hasToken = false
    public private(set) var tokenExpirySeconds: Int64?
    public private(set) var accountEmail = ""
    public private(set) var accountBusy = false
    public private(set) var accountMessage = ""
    public var tokenSheetVisible = false
    public private(set) var refreshingDevices = false
    public private(set) var devicesMessage = ""
    public private(set) var geocoderAvailable = true

    // Mapbox account and route preview
    public private(set) var hasMapboxToken = false
    public private(set) var mapboxBusy = false
    public private(set) var mapboxMessage = ""
    public var mapboxSheetVisible = false
    public private(set) var routes: [RoutePreview] = []
    public private(set) var selectedRouteIndex = 0
    public private(set) var stops: [Destination] = []
    public private(set) var routesLoading = false
    public private(set) var routesMessage = ""
    public private(set) var origin: LatLng?

    // stored data
    public private(set) var devices: [PairedDevice] = []
    public private(set) var selectedDongleId = ""
    public private(set) var favorites: [Favorite] = []

    /// Incremented when the Send tab should be brought to front (share received, favorite picked).
    public private(set) var showSendTabRequest = 0

    private let resolver: DestinationResolver
    private let placeSearch: PlaceSearch
    private let transports: TransportRegistry
    private let commaTransport: CommaAthenaTransport
    private let tokenStore: TokenStore
    private let favoritesRepository: FavoritesRepository
    private let deviceRepository: DeviceRepository
    private let now: () -> Date
    private let routePlanning: RoutePlanning?

    private var resolveGeneration = 0
    private var connectionGeneration = 0
    private var routesGeneration = 0

    public init(
        resolver: DestinationResolver,
        placeSearch: PlaceSearch,
        transports: TransportRegistry,
        tokenStore: TokenStore,
        favoritesRepository: FavoritesRepository,
        deviceRepository: DeviceRepository,
        routePlanning: RoutePlanning? = nil,
        now: @escaping () -> Date = { Date() }
    ) {
        self.resolver = resolver
        self.placeSearch = placeSearch
        self.transports = transports
        self.commaTransport = transports.comma
        self.tokenStore = tokenStore
        self.favoritesRepository = favoritesRepository
        self.deviceRepository = deviceRepository
        self.now = now
        self.routePlanning = routePlanning
        geocoderAvailable = placeSearch.isAvailable()
        copyStoredData()
    }

    /// Reads the token state and checks the selected device. Called when a screen appears.
    public func start() async {
        refreshTokenState()
        await checkConnection()
    }

    /// Re-reads devices, favorites and the token: the share extension may have changed them.
    public func reloadStoredData() {
        deviceRepository.reload()
        favoritesRepository.reload()
        copyStoredData()
        refreshTokenState()
    }

    // MARK: - destination input

    public func handleShare(text: String, subject: String) async {
        requestSendTab()
        await resolve {
            await self.resolver.resolveShared(text: text, subject: subject)
        }
    }

    public func handleLink(_ link: String) async {
        requestSendTab()
        await resolve {
            await self.resolver.resolveLink(link, title: "", details: "", source: DestinationResolver.sourceLink)
        }
    }

    public func search(_ text: String) async {
        await resolve {
            await self.resolver.resolveTyped(text)
        }
    }

    public func chooseCandidate(_ candidate: Destination) {
        destination = candidate
        destinationSource = DestinationResolver.sourceSearch
        choices = []
        resolveError = ""
        feedback = nil
        destinationChanged()
    }

    public func selectFavorite(_ favorite: Favorite) {
        resolveGeneration += 1
        destination = favorite.destination
        destinationSource = DestinationResolver.sourceFavorite
        choices = []
        resolving = false
        resolveError = ""
        feedback = nil
        requestSendTab()
        destinationChanged()
    }

    /// Send button on a favorite: select it (brings the Send tab up, where the feedback shows) and send it.
    public func sendFavorite(_ favorite: Favorite) async {
        if sending {
            return
        }
        selectFavorite(favorite)
        await sendDestination()
    }

    public func clearSelection() {
        resolveGeneration += 1
        destination = nil
        destinationSource = ""
        choices = []
        resolving = false
        resolveError = ""
        feedback = nil
        destinationChanged()
    }

    public func isFavorite(_ candidate: Destination?) -> Bool {
        guard let candidate = candidate else {
            return false
        }
        // reads the observed `favorites`, so views showing the heart update when it changes
        for favorite in favorites {
            if favorite.destination.sameLocationAs(candidate) {
                return true
            }
        }
        return false
    }

    public func toggleFavorite() {
        guard let current = destination else {
            return
        }
        if let existing = favoritesRepository.findByLocation(current) {
            favoritesRepository.remove(existing.id)
        } else {
            favoritesRepository.add(current)
        }
        favorites = favoritesRepository.favorites
    }

    public func removeFavorite(_ id: String) {
        favoritesRepository.remove(id)
        favorites = favoritesRepository.favorites
    }

    private func resolve(_ work: () async -> ResolveOutcome) async {
        resolveGeneration += 1
        let generation = resolveGeneration
        resolving = true
        resolveError = ""
        choices = []

        let outcome = await work()
        if generation != resolveGeneration {
            // cancelled or replaced by a newer request
            return
        }
        apply(outcome)
    }

    private func apply(_ outcome: ResolveOutcome) {
        resolving = false
        switch outcome {
        case .resolved(let resolved, let source):
            destination = resolved
            destinationSource = source
            choices = []
            resolveError = ""
            feedback = nil
            destinationChanged()
        case .choices(_, let candidates):
            choices = candidates
            resolveError = ""
        case .failed(let reason):
            choices = []
            resolveError = reason
        }
    }

    private func requestSendTab() {
        showSendTabRequest += 1
    }

    // MARK: - device commands

    public func selectedDevice() -> PairedDevice? {
        return deviceRepository.selectedDevice()
    }

    public func selectDevice(_ dongleId: String) async {
        deviceRepository.select(dongleId)
        copyStoredData()
        connection = .unknown
        feedback = nil
        await checkConnection()
    }

    public func checkConnection() async {
        connectionGeneration += 1
        let generation = connectionGeneration
        guard let device = deviceRepository.selectedDevice() else {
            connection = .unknown
            return
        }
        if device.backend == .commaAthena && !hasToken {
            connection = .unknown
            return
        }
        connection = .checking
        let result = await transports.forDevice(device).checkStatus(device)
        if generation != connectionGeneration {
            return
        }
        switch result {
        case .success(let status):
            connection = .online(status)
        case .failure(let error):
            connection = .unreachable(TransportErrorText.describe(error))
        }
    }

    public func sendDestination() async {
        guard let current = destination else {
            return
        }
        guard let device = deviceRepository.selectedDevice() else {
            return
        }
        if sending {
            return
        }
        sending = true
        feedback = nil
        let waypoints = plannedWaypoints()
        let result: Result<Delivery, TransportError>
        if waypoints.isEmpty {
            result = await transports.forDevice(device).setDestination(device, current)
        } else {
            result = await transports.forDevice(device).setRoute(device, current, waypoints: waypoints)
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
            feedback = SendFeedback(success: true, message: message, time: now())
        case .failure(let error):
            feedback = SendFeedback(success: false, message: TransportErrorText.describe(error), time: now())
        }
        sending = false
    }

    public func clearDestinationOnDevice() async {
        guard let device = deviceRepository.selectedDevice() else {
            return
        }
        if sending {
            return
        }
        sending = true
        feedback = nil
        let result = await transports.forDevice(device).clearDestination(device)
        switch result {
        case .success:
            feedback = SendFeedback(success: true, message: "Destination cleared on \(device.displayName()).", time: now())
        case .failure(let error):
            feedback = SendFeedback(success: false, message: TransportErrorText.describe(error), time: now())
        }
        sending = false
    }

    // MARK: - account and devices

    public func showTokenSheet() {
        accountMessage = ""
        tokenSheetVisible = true
    }

    public func hideTokenSheet() {
        accountMessage = ""
        tokenSheetVisible = false
    }

    /// Verifies `rawToken` against the comma API and stores it in the Keychain only when it is accepted.
    public func saveToken(_ rawToken: String) async {
        let token = TokenStore.normalize(rawToken)
        if token.isEmpty {
            accountMessage = "Paste a token first."
            return
        }
        if !JwtInfo.looksLikeJwt(token) {
            accountMessage = "This does not look like a JWT (three parts separated by dots)."
            return
        }
        accountBusy = true
        accountMessage = ""
        let result = await commaTransport.verifyToken(token)
        switch result {
        case .success(let account):
            do {
                try tokenStore.save(token)
            } catch {
                accountBusy = false
                accountMessage = "Token not saved. " + error.localizedDescription
                return
            }
            accountBusy = false
            tokenSheetVisible = false
            accountEmail = account.email
            accountMessage = ""
            refreshTokenState()
            await refreshDevices()
        case .failure(let error):
            accountBusy = false
            accountMessage = "Token not saved. " + TransportErrorText.describe(error)
        }
    }

    public func removeToken() {
        tokenStore.clear()
        hasToken = false
        tokenExpirySeconds = nil
        accountEmail = ""
        connection = .unknown
    }

    public func refreshDevices() async {
        if refreshingDevices {
            return
        }
        refreshingDevices = true
        devicesMessage = ""
        let result = await commaTransport.listDevices()
        switch result {
        case .success(let accountDevices):
            deviceRepository.replaceAccountDevices(accountDevices)
            copyStoredData()
            var message = "\(accountDevices.count) device(s) on the comma account."
            if accountDevices.isEmpty {
                message = "No devices on this comma account."
            }
            refreshingDevices = false
            devicesMessage = message
            await checkConnection()
        case .failure(let error):
            refreshingDevices = false
            devicesMessage = TransportErrorText.describe(error)
        }
    }

    /// Returns an error message, or "" when the device was added.
    public func addManualDevice(dongleIdText: String, alias: String) async -> String {
        let dongleId = DongleIdRules.normalize(dongleIdText)
        if !DongleIdRules.isValid(dongleId) {
            return "A dongle ID is 16 hexadecimal characters (0-9, a-f)."
        }
        let device = PairedDevice(
            dongleId: dongleId,
            alias: alias.trimmingCharacters(in: .whitespacesAndNewlines),
            backend: .commaAthena,
            addedManually: true
        )
        if !deviceRepository.addManual(device) {
            return "This device is already in the list."
        }
        copyStoredData()
        if deviceRepository.devices.count == 1 {
            await checkConnection()
        }
        return ""
    }

    public func removeDevice(_ dongleId: String) async {
        let wasSelected = deviceRepository.selectedDongleId == dongleId
        deviceRepository.remove(dongleId)
        copyStoredData()
        if wasSelected {
            connection = .unknown
            await checkConnection()
        }
    }

    // MARK: - Mapbox account and route preview

    public var routePlanningAvailable: Bool {
        return routePlanning != nil
    }

    /// The user's Mapbox public token, for the map view.
    public func mapboxAccessToken() -> String? {
        return routePlanning?.mapboxTokenStore.load()
    }

    public func showMapboxSheet() {
        mapboxMessage = ""
        mapboxSheetVisible = true
    }

    public func hideMapboxSheet() {
        mapboxMessage = ""
        mapboxSheetVisible = false
    }

    /// Checks `rawToken` with Mapbox's Tokens API and stores it in the Keychain only when it is a valid public token.
    public func saveMapboxToken(_ rawToken: String) async {
        guard let planning = routePlanning else {
            return
        }
        let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if token.isEmpty {
            mapboxMessage = "Paste a token first."
            return
        }
        if MapboxTokenRules.isSecretToken(token) {
            mapboxMessage = "This is a secret token (sk.). Paste your Default public token (pk.) instead."
            return
        }
        if !MapboxTokenRules.isPublicToken(token) {
            mapboxMessage = "A Mapbox public token starts with pk. (Default public token on the Tokens page)."
            return
        }
        mapboxBusy = true
        mapboxMessage = ""
        let check = await planning.verifier.verify(token)
        switch check {
        case .valid:
            do {
                try planning.mapboxTokenStore.save(token)
            } catch {
                mapboxBusy = false
                mapboxMessage = "Token not saved. " + error.localizedDescription
                return
            }
            mapboxBusy = false
            mapboxSheetVisible = false
            hasMapboxToken = true
            await refreshRoutes()
        case .rejected(let code):
            mapboxBusy = false
            mapboxMessage = "Token not saved: Mapbox answered \(code)."
        case .failed(let error):
            mapboxBusy = false
            mapboxMessage = "Token not saved. " + TransportErrorText.describe(error)
        }
    }

    public func removeMapboxToken() {
        routePlanning?.mapboxTokenStore.clear()
        hasMapboxToken = false
        routesGeneration += 1
        routes = []
        routesLoading = false
        routesMessage = ""
    }

    /// Route previews from the phone's position to the destination through the stops.
    public func refreshRoutes() async {
        routesGeneration += 1
        let generation = routesGeneration
        guard let planning = routePlanning, let target = destination, hasMapboxToken else {
            routes = []
            routesLoading = false
            routesMessage = ""
            return
        }
        routesLoading = true
        routesMessage = ""

        let position = await planning.location.currentLocation()
        if generation != routesGeneration {
            return
        }
        origin = position
        guard let start = position else {
            routes = []
            routesLoading = false
            routesMessage = "The route preview starts from this phone's position: allow location access in Settings."
            return
        }

        var stopPoints: [LatLng] = []
        for stop in stops {
            stopPoints.append(LatLng(latitude: stop.latitude, longitude: stop.longitude))
        }
        let result = await planning.directions.routes(
            from: start,
            stops: stopPoints,
            to: LatLng(latitude: target.latitude, longitude: target.longitude)
        )
        if generation != routesGeneration {
            return
        }
        routesLoading = false
        switch result {
        case .success(let found):
            routes = found
            if selectedRouteIndex >= found.count {
                selectedRouteIndex = 0
            }
            if found.isEmpty {
                routesMessage = "Mapbox found no route."
            }
        case .failure(let error):
            routes = []
            selectedRouteIndex = 0
            if error == .unauthorized {
                routesMessage = "Mapbox rejected the token (HTTP 401). Check it in Devices."
            } else {
                routesMessage = TransportErrorText.describe(error)
            }
        }
    }

    public func selectRoute(_ index: Int) {
        if index < 0 || index >= routes.count {
            return
        }
        selectedRouteIndex = index
        feedback = nil
    }

    /// Adds a stop before the destination, in the order they are added.
    public func addStop(latitude: Double, longitude: Double) async {
        if !CoordinateRules.isValid(latitude: latitude, longitude: longitude) {
            return
        }
        if destination == nil || stops.count >= MainViewModel.maxStops {
            return
        }
        stops.append(Destination(latitude: latitude, longitude: longitude, name: "Stop \(stops.count + 1)"))
        selectedRouteIndex = 0
        feedback = nil
        await refreshRoutes()
    }

    public func removeStop(at index: Int) async {
        if index < 0 || index >= stops.count {
            return
        }
        stops.remove(at: index)
        var renamed: [Destination] = []
        for (position, stop) in stops.enumerated() {
            var updated = stop
            updated.name = "Stop \(position + 1)"
            renamed.append(updated)
        }
        stops = renamed
        selectedRouteIndex = 0
        feedback = nil
        await refreshRoutes()
    }

    /// What the device gets besides the destination: the stops, or via points of the alternative picked on the map.
    func plannedWaypoints() -> [RouteWaypoint] {
        var waypoints: [RouteWaypoint] = []
        for stop in stops {
            waypoints.append(RouteWaypoint(latitude: stop.latitude, longitude: stop.longitude, via: false))
        }
        if waypoints.isEmpty && selectedRouteIndex > 0 && selectedRouteIndex < routes.count {
            waypoints = RouteShaping.viaPoints(along: routes[selectedRouteIndex])
        }
        return waypoints
    }

    // sunnypilot setNavRoute accepts 20 waypoints; three are left for the via points of an alternative
    public static let maxStops = 10

    /// A new destination starts a new plan. The map view asks for the routes (refreshRoutes) when it sees the change.
    private func destinationChanged() {
        routesGeneration += 1
        stops = []
        selectedRouteIndex = 0
        routes = []
        routesLoading = false
        routesMessage = ""
    }

    private func refreshTokenState() {
        if let planning = routePlanning {
            hasMapboxToken = planning.mapboxTokenStore.hasToken()
        }
        guard let token = tokenStore.load() else {
            hasToken = false
            tokenExpirySeconds = nil
            return
        }
        hasToken = true
        tokenExpirySeconds = JwtInfo.expirySeconds(token)
    }

    private func copyStoredData() {
        devices = deviceRepository.devices
        selectedDongleId = deviceRepository.selectedDongleId
        favorites = favoritesRepository.favorites
    }
}
