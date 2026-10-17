import Foundation

/// Address / place search.
public protocol PlaceSearch: AnyObject {
    func isAvailable() -> Bool

    func search(_ query: String, maxResults: Int) async throws -> [Destination]
}
