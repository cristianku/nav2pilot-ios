import Foundation

public struct HttpRequest: CustomStringConvertible {
    public let method: String
    public let url: String
    public let headers: [String: String]
    public let body: String?
    public let followRedirects: Bool
    public let readBody: Bool

    public init(
        method: String,
        url: String,
        headers: [String: String] = [:],
        body: String? = nil,
        followRedirects: Bool = true,
        readBody: Bool = true
    ) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
        self.followRedirects = followRedirects
        self.readBody = readBody
    }

    // Headers are left out and an access_token query parameter is masked: both can carry a token.
    public var description: String {
        return "HttpRequest(\(method) \(HttpRequest.maskAccessToken(url)))"
    }

    static func maskAccessToken(_ url: String) -> String {
        guard let range = url.range(of: "access_token=") else {
            return url
        }
        var end = url.endIndex
        if let ampersand = url[range.upperBound...].firstIndex(of: "&") {
            end = ampersand
        }
        return url.replacingCharacters(in: range.upperBound..<end, with: "***")
    }
}

public struct HttpResponse {
    public let code: Int
    public let headers: [String: [String]]
    public let body: String

    public init(code: Int, headers: [String: [String]] = [:], body: String = "") {
        self.code = code
        self.headers = headers
        self.body = body
    }

    public func header(_ name: String) -> String? {
        for (headerName, values) in headers {
            if headerName.caseInsensitiveCompare(name) == .orderedSame && !values.isEmpty {
                return values[0]
            }
        }
        return nil
    }

    public func isSuccessful() -> Bool {
        return code >= 200 && code <= 299
    }

    public func isRedirect() -> Bool {
        return code >= 300 && code <= 399
    }
}

/// A network failure with a message that is safe to show (it never contains the token).
public struct HttpClientError: Error, LocalizedError, Equatable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? {
        return message
    }
}

public protocol HttpClient: AnyObject {
    func execute(_ request: HttpRequest) async throws -> HttpResponse
}
