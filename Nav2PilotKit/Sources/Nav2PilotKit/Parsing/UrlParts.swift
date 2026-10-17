import Foundation

public struct QueryParameter: Equatable {
    public let name: String
    public let value: String
}

/// Minimal, lenient URL splitter.
///
/// Foundation's URL rejects or rewrites many real map links (unencoded spaces, '|' and similar), so
/// the URL is split by hand. `path` and `query` stay percent-encoded; `parameters` are decoded.
public struct UrlParts {
    public let scheme: String
    public let host: String
    public let path: String
    public let query: String
    public let parameters: [QueryParameter]

    public func parameter(_ name: String) -> String? {
        for parameter in parameters {
            if parameter.name == name {
                return parameter.value
            }
        }
        return nil
    }

    public static func parse(_ url: String) -> UrlParts? {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let schemeSeparator = trimmed.range(of: "://") else {
            return nil
        }
        if schemeSeparator.lowerBound == trimmed.startIndex {
            return nil
        }
        let scheme = String(trimmed[trimmed.startIndex..<schemeSeparator.lowerBound]).lowercased()
        let afterScheme = String(trimmed[schemeSeparator.upperBound...])

        var authorityEnd = afterScheme.endIndex
        for index in afterScheme.indices {
            let character = afterScheme[index]
            if character == "/" || character == "?" || character == "#" {
                authorityEnd = index
                break
            }
        }
        var host = String(afterScheme[afterScheme.startIndex..<authorityEnd])
        var rest = String(afterScheme[authorityEnd...])

        if let userInfoEnd = host.lastIndex(of: "@") {
            host = String(host[host.index(after: userInfoEnd)...])
        }
        if let portStart = host.firstIndex(of: ":") {
            host = String(host[host.startIndex..<portStart])
        }
        host = host.lowercased()
        if host.isEmpty {
            return nil
        }

        if let fragmentStart = rest.firstIndex(of: "#") {
            rest = String(rest[rest.startIndex..<fragmentStart])
        }

        var path = rest
        var query = ""
        if let queryStart = rest.firstIndex(of: "?") {
            path = String(rest[rest.startIndex..<queryStart])
            query = String(rest[rest.index(after: queryStart)...])
        }

        return UrlParts(scheme: scheme, host: host, path: path, query: query, parameters: parseQuery(query))
    }

    public static func parseQuery(_ query: String) -> [QueryParameter] {
        var parameters: [QueryParameter] = []
        if query.isEmpty {
            return parameters
        }
        for pair in query.components(separatedBy: "&") {
            if pair.isEmpty {
                continue
            }
            if let equalsIndex = pair.firstIndex(of: "=") {
                let name = decode(String(pair[pair.startIndex..<equalsIndex]))
                let value = decode(String(pair[pair.index(after: equalsIndex)...]))
                parameters.append(QueryParameter(name: name, value: value))
            } else {
                parameters.append(QueryParameter(name: decode(pair), value: ""))
            }
        }
        return parameters
    }

    /// Percent-decodes `text`; '+' becomes a space, as Google Maps uses it for spaces in paths and queries.
    /// Malformed percent escapes leave the text as it is (apart from '+').
    public static func decode(_ text: String) -> String {
        let withSpaces = text.replacingOccurrences(of: "+", with: " ")
        if let decoded = withSpaces.removingPercentEncoding {
            return decoded
        }
        return withSpaces
    }
}
