import Foundation

public final class FavoritesRepository {
    public static let keyFavorites = "favorites"

    private let store: KeyValueStore
    public private(set) var favorites: [Favorite] = []

    public init(store: KeyValueStore) {
        self.store = store
        reload()
    }

    /// Reads the stored list again (the share extension may have changed it).
    public func reload() {
        guard let text = store.getString(FavoritesRepository.keyFavorites) else {
            favorites = []
            return
        }
        favorites = JsonCodec.favoritesFromJson(text)
    }

    /// Adds `destination`; a favorite at the same location is returned instead of duplicated.
    @discardableResult
    public func add(_ destination: Destination) -> Favorite {
        if let existing = findByLocation(destination) {
            return existing
        }
        let favorite = Favorite(id: UUID().uuidString, destination: destination)
        var updated = favorites
        updated.append(favorite)
        save(updated)
        return favorite
    }

    public func remove(_ id: String) {
        var updated: [Favorite] = []
        for favorite in favorites {
            if favorite.id != id {
                updated.append(favorite)
            }
        }
        save(updated)
    }

    public func findByLocation(_ destination: Destination) -> Favorite? {
        for favorite in favorites {
            if favorite.destination.sameLocationAs(destination) {
                return favorite
            }
        }
        return nil
    }

    private func save(_ updated: [Favorite]) {
        store.putString(FavoritesRepository.keyFavorites, JsonCodec.favoritesToJson(updated))
        favorites = updated
    }
}
