import Foundation

/// HTTP client on an ephemeral URLSession: no cache, no cookies, nothing written to disk.
public final class URLSessionHttpClient: HttpClient {
    private let userAgent: String
    private let session: URLSession

    private static let maxBodyBytes = 1_000_000

    public init(userAgent: String, requestTimeoutSeconds: TimeInterval = 30) {
        self.userAgent = userAgent
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = requestTimeoutSeconds
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        session = URLSession(configuration: configuration)
    }

    public func execute(_ request: HttpRequest) async throws -> HttpResponse {
        guard let url = URL(string: request.url) else {
            throw HttpClientError("Invalid URL")
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method
        urlRequest.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        if let body = request.body {
            urlRequest.httpBody = Data(body.utf8)
        }

        var delegate: URLSessionTaskDelegate?
        if !request.followRedirects {
            delegate = RedirectBlocker()
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest, delegate: delegate)
        } catch {
            throw HttpClientError(error.localizedDescription)
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HttpClientError("Not an HTTP response")
        }

        var headers: [String: [String]] = [:]
        for (key, value) in httpResponse.allHeaderFields {
            if let name = key as? String {
                headers[name] = ["\(value)"]
            }
        }

        var body = ""
        if request.readBody {
            if data.count > URLSessionHttpClient.maxBodyBytes {
                throw HttpClientError("Response body larger than \(URLSessionHttpClient.maxBodyBytes) bytes")
            }
            body = String(decoding: data, as: UTF8.self)
        }
        return HttpResponse(code: httpResponse.statusCode, headers: headers, body: body)
    }
}

/// Hands the 3xx response back to the caller instead of following it.
private final class RedirectBlocker: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
