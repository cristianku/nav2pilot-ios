import Foundation

public enum ResolveOutcome: Equatable {
    case resolved(Destination, source: String)
    case choices(query: String, candidates: [Destination])
    case failed(String)
}

/// Turns shared text, typed text or a map link into a destination.
public final class DestinationResolver {
    public static let sourceSharedLink = "Shared link"
    public static let sourceLink = "Map link"
    public static let sourceCoordinates = "Coordinates"
    public static let sourceSearch = "Search"
    public static let sourceMap = "Map"
    public static let sourceFavorite = "Favorite"

    private static let maxResults = 5

    private let shortLinkResolver: ShortLinkResolver
    private let placeSearch: PlaceSearch

    public init(shortLinkResolver: ShortLinkResolver, placeSearch: PlaceSearch) {
        self.shortLinkResolver = shortLinkResolver
        self.placeSearch = placeSearch
    }

    /// Text received through the share sheet (text and URL items, and the item title as subject).
    public func resolveShared(text: String, subject: String) async -> ResolveOutcome {
        let shared = ShareTextParser.parse(text, subject: subject)
        if !shared.link.isEmpty {
            return await resolveLink(shared.link, title: shared.title, details: shared.details, source: DestinationResolver.sourceSharedLink)
        }

        for line in TextLines.split(text) {
            if let coordinates = CoordinateParser.parse(line.trimmingCharacters(in: .whitespacesAndNewlines)) {
                let name = firstOtherLine(text, excludedLine: line)
                return .resolved(
                    Destination(latitude: coordinates.latitude, longitude: coordinates.longitude, name: name),
                    source: DestinationResolver.sourceCoordinates
                )
            }
        }

        if shared.textWithoutLink.isEmpty {
            return .failed("The shared content is empty.")
        }
        return await search([shared.textWithoutLink], nameHint: shared.title, source: DestinationResolver.sourceSearch)
    }

    /// Text typed or pasted in the search field: coordinates, a map link or an address.
    public func resolveTyped(_ text: String) async -> ResolveOutcome {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return .failed("Enter an address, coordinates or a map link.")
        }

        if let coordinates = CoordinateParser.parse(trimmed) {
            return .resolved(
                Destination(latitude: coordinates.latitude, longitude: coordinates.longitude),
                source: DestinationResolver.sourceCoordinates
            )
        }

        let shared = ShareTextParser.parse(trimmed, subject: "")
        if !shared.link.isEmpty {
            return await resolveLink(shared.link, title: shared.title, details: shared.details, source: DestinationResolver.sourceLink)
        }

        return await search([trimmed], nameHint: "", source: DestinationResolver.sourceSearch)
    }

    public func resolveLink(_ link: String, title: String, details: String, source: String) async -> ResolveOutcome {
        var result = MapLinkParser.parse(link)
        var networkError = ""

        if MapLinkParser.rank(result) < MapLinkParser.exactRank && needsExpansion(link) {
            let expanded = await shortLinkResolver.resolve(link)
            if MapLinkParser.rank(expanded.result) > MapLinkParser.rank(result) {
                result = expanded.result
            }
            networkError = expanded.networkError
        }

        switch result {
        case .found(let destination):
            return .resolved(applyHints(destination, title: title, details: details), source: source)
        case .query(let text):
            return await search(searchTexts(title: title, details: details, query: text), nameHint: title, source: source)
        case .notRecognized:
            break
        }

        if !title.isEmpty {
            return await search(searchTexts(title: title, details: details, query: ""), nameHint: title, source: source)
        }
        if !networkError.isEmpty {
            return .failed("Could not open the link: \(networkError)")
        }
        return .failed("This link does not contain a location.")
    }

    private func search(_ texts: [String], nameHint: String, source: String) async -> ResolveOutcome {
        if !placeSearch.isAvailable() {
            return .failed("Address search is not available. Enter coordinates instead.")
        }

        var lastError = ""
        var lastText = ""
        for text in texts {
            lastText = text
            let results: [Destination]
            do {
                results = try await placeSearch.search(text, maxResults: DestinationResolver.maxResults)
            } catch {
                lastError = error.localizedDescription
                continue
            }
            if results.count == 1 {
                var destination = results[0]
                if !nameHint.isEmpty {
                    destination.name = nameHint
                }
                return .resolved(destination, source: source)
            }
            if results.count > 1 {
                return .choices(query: text, candidates: results)
            }
        }

        if !lastError.isEmpty {
            return .failed("Search failed: \(lastError)")
        }
        return .failed("No results for \"\(lastText)\".")
    }

    private func needsExpansion(_ link: String) -> Bool {
        guard let parts = UrlParts.parse(link) else {
            return false
        }
        if GoogleHosts.isShortLink(parts) {
            return true
        }
        if GoogleHosts.isGoogleMapsUrl(parts) {
            return true
        }
        if AppleMapsHosts.isShortLink(parts) {
            return true
        }
        return false
    }

    private func applyHints(_ destination: Destination, title: String, details: String) -> Destination {
        var result = destination
        if result.name.isEmpty {
            result.name = title
        }
        if result.details.isEmpty {
            result.details = details
        }
        return result
    }

    /// Address lines are tried first: they geocode more reliably than a business name.
    private func searchTexts(title: String, details: String, query: String) -> [String] {
        var candidates: [String] = []
        if !details.isEmpty {
            candidates.append(details)
            if !title.isEmpty {
                candidates.append(title + ", " + details)
            }
        }
        if !query.isEmpty {
            candidates.append(query)
        }
        if !title.isEmpty {
            candidates.append(title)
        }

        var distinct: [String] = []
        for candidate in candidates {
            if !distinct.contains(candidate) {
                distinct.append(candidate)
            }
        }
        return distinct
    }

    private func firstOtherLine(_ text: String, excludedLine: String) -> String {
        for line in TextLines.split(text) {
            let cleaned = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty && line != excludedLine {
                return cleaned
            }
        }
        return ""
    }
}
