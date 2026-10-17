import Foundation

public struct ShortLinkResult: Equatable {
    public let result: LinkParseResult
    public let finalUrl: String
    public let networkError: String
}

/// Expands short map links (maps.app.goo.gl, maps.apple/p/...) by following HTTP redirects one hop at a
/// time, reading only the Location header, and stops as soon as a hop contains a place pin.
///
/// - Only Google Maps and Apple Maps hosts are contacted; any other redirect target ends the walk.
/// - consent.google.com (EU cookie consent interstitial) is not fetched: its `continue` parameter
///   already carries the original Maps URL.
public final class ShortLinkResolver {
    private let http: HttpClient
    private let maxHops: Int

    public init(http: HttpClient, maxHops: Int = 6) {
        self.http = http
        self.maxHops = maxHops
    }

    public func resolve(_ startUrl: String) async -> ShortLinkResult {
        var currentUrl = startUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        var best = LinkParseResult.notRecognized
        var networkError = ""
        var hop = 0

        while hop <= maxHops {
            let parsed = MapLinkParser.parse(currentUrl)
            if MapLinkParser.rank(parsed) > MapLinkParser.rank(best) {
                best = parsed
            }
            if MapLinkParser.rank(best) == MapLinkParser.exactRank {
                break
            }

            guard let parts = UrlParts.parse(currentUrl) else {
                break
            }

            if parts.host == GoogleHosts.consentHost {
                let continueUrl = parts.parameter("continue") ?? ""
                if continueUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    break
                }
                currentUrl = continueUrl
                hop += 1
                continue
            }

            if !isAllowedToFetch(parts) {
                break
            }
            if hop == maxHops {
                break
            }

            let request = HttpRequest(
                method: "GET",
                url: upgradeToHttps(currentUrl),
                followRedirects: false,
                readBody: false
            )
            let response: HttpResponse
            do {
                response = try await http.execute(request)
            } catch {
                networkError = error.localizedDescription
                break
            }
            if !response.isRedirect() {
                break
            }
            guard let location = response.header("Location") else {
                break
            }
            currentUrl = absoluteUrl(baseUrl: currentUrl, location: location)
            hop += 1
        }

        return ShortLinkResult(result: best, finalUrl: currentUrl, networkError: networkError)
    }

    private func isAllowedToFetch(_ parts: UrlParts) -> Bool {
        if parts.scheme != "https" && parts.scheme != "http" {
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
        if AppleMapsHosts.isAppleMapsUrl(parts) {
            return true
        }
        return false
    }

    private func upgradeToHttps(_ url: String) -> String {
        if url.lowercased().hasPrefix("http://") {
            return "https://" + url.dropFirst("http://".count)
        }
        return url
    }

    private func absoluteUrl(baseUrl: String, location: String) -> String {
        let lowercase = location.lowercased()
        if lowercase.hasPrefix("https://") || lowercase.hasPrefix("http://") {
            return location
        }
        guard let parts = UrlParts.parse(baseUrl) else {
            return location
        }
        // Location headers seen from Google and Apple are absolute or start with "/".
        if location.hasPrefix("/") {
            return parts.scheme + "://" + parts.host + location
        }
        guard let base = URL(string: baseUrl), let resolved = URL(string: location, relativeTo: base) else {
            return location
        }
        return resolved.absoluteString
    }
}
