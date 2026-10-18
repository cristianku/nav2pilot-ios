import Foundation

/// Manual dependency wiring, used by the app and by the share extension.
///
/// Both read the same data: devices and favorites in the App Group's UserDefaults, the comma token in
/// the shared Keychain access group (see the entitlements files).
public enum AppContainer {
    public static let appGroupIdentifier = "group.com.cristianku.nav2pilot"
    public static let keychainService = "com.cristianku.nav2pilot"

    @MainActor
    /// `withRoutePlanning`: the Mapbox route map, in the app only (the share extension sends the destination alone).
    public static func makeViewModel(bundle: Bundle = .main, withRoutePlanning: Bool = false) -> MainViewModel {
        var defaults = UserDefaults.standard
        if let groupDefaults = UserDefaults(suiteName: appGroupIdentifier) {
            defaults = groupDefaults
        }
        let dataStore = UserDefaultsStore(defaults: defaults)
        let tokenStore = TokenStore(secrets: KeychainSecretStore(service: keychainService))

        let httpClient = URLSessionHttpClient(userAgent: "Nav2Pilot/" + appVersion(bundle) + " (iOS)")
        let comma = CommaAthenaTransport(
            http: httpClient,
            tokenProvider: {
                return tokenStore.load()
            }
        )
        let placeSearch = MapKitPlaceSearch()
        let resolver = DestinationResolver(
            shortLinkResolver: ShortLinkResolver(http: httpClient),
            placeSearch: placeSearch
        )

        var routePlanning: RoutePlanning?
        if withRoutePlanning {
            let mapboxTokenStore = TokenStore(secrets: KeychainSecretStore(service: keychainService), key: TokenStore.keyMapboxToken)
            routePlanning = RoutePlanning(
                mapboxTokenStore: mapboxTokenStore,
                verifier: MapboxTokenVerifier(http: httpClient),
                directions: MapboxDirections(http: httpClient, tokenProvider: {
                    return mapboxTokenStore.load()
                }),
                location: CoreLocationProvider(),
                deliveries: MapboxDeliveries(store: dataStore)
            )
        }

        return MainViewModel(
            resolver: resolver,
            placeSearch: placeSearch,
            transports: TransportRegistry(comma: comma, sunnylink: SunnylinkTransport()),
            tokenStore: tokenStore,
            favoritesRepository: FavoritesRepository(store: dataStore),
            deviceRepository: DeviceRepository(store: dataStore),
            routePlanning: routePlanning
        )
    }

    private static func appVersion(_ bundle: Bundle) -> String {
        if let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
            return version
        }
        return "unknown"
    }
}
