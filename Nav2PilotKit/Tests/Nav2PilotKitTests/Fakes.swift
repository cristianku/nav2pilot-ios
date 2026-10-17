import Foundation
@testable import Nav2PilotKit

/// Returns scripted responses in order and records every request.
final class FakeHttpClient: HttpClient {
    private enum Scripted {
        case response(HttpResponse)
        case failure(String)
    }

    var requests: [HttpRequest] = []
    private var responses: [Scripted] = []

    func respond(_ code: Int, _ body: String = "", headers: [String: [String]] = [:]) {
        responses.append(.response(HttpResponse(code: code, headers: headers, body: body)))
    }

    func redirect(_ location: String, code: Int = 302) {
        responses.append(.response(HttpResponse(code: code, headers: ["Location": [location]], body: "")))
    }

    func fail(_ message: String) {
        responses.append(.failure(message))
    }

    func execute(_ request: HttpRequest) async throws -> HttpResponse {
        requests.append(request)
        if responses.isEmpty {
            throw HttpClientError("Unexpected request: \(request)")
        }
        let next = responses.removeFirst()
        switch next {
        case .response(let response):
            return response
        case .failure(let message):
            throw HttpClientError(message)
        }
    }
}

final class InMemoryKeyValueStore: KeyValueStore {
    var values: [String: String] = [:]

    func getString(_ key: String) -> String? {
        return values[key]
    }

    func putString(_ key: String, _ value: String) {
        values[key] = value
    }

    func remove(_ key: String) {
        values.removeValue(forKey: key)
    }
}

/// Stand-in for the Keychain, which needs an entitlement that `swift test` does not have.
final class InMemorySecretStore: SecretStore {
    var values: [String: String] = [:]
    var failWrite = false

    func read(_ key: String) -> String? {
        return values[key]
    }

    func write(_ key: String, _ value: String) throws {
        if failWrite {
            throw KeychainError(status: -34018)
        }
        values[key] = value
    }

    func delete(_ key: String) {
        values.removeValue(forKey: key)
    }
}

final class FakePlaceSearch: PlaceSearch {
    private let available: Bool
    var queries: [String] = []
    var results: [String: [Destination]] = [:]
    var error: Error?

    init(available: Bool = true) {
        self.available = available
    }

    func isAvailable() -> Bool {
        return available
    }

    func search(_ query: String, maxResults: Int) async throws -> [Destination] {
        queries.append(query)
        if let failure = error {
            throw failure
        }
        return results[query] ?? []
    }
}

enum Fixtures {
    /// Location header returned by https://maps.app.goo.gl/gqhGPJxrF8E7MX479 (public link, fetched 2026-10-17).
    static let shortLink = "https://maps.app.goo.gl/gqhGPJxrF8E7MX479"
    static let shortLinkTarget =
        "https://www.google.com/maps/place/Copenhagen+Coffee+Lab/@43.6764552,6.9908374,10.65z/data=!4m7!3m6!1s0x12cdd180e7e5b347:0x641651765156f103!8m2!3d43.695783!4d7.260654!15sChVjb3BlbmhhZ2VuIGNvZmZlZSBsYWIiA4gBAVoXIhVjb3BlbmhhZ2VuIGNvZmZlZSBsYWKSAQtjb2ZmZWVfc2hvcKoBaAoNL2cvMTFma3l5NzhqMBABKhkiFWNvcGVuaGFnZW4gY29mZmVlIGxhYigAMh8QASIb36relNgo72m7fjH03ff9bDQMKo5st-5JVOBFMhkQAiIVY29wZW5oYWdlbiBjb2ZmZWUgbGFi4AEA!16s%2Fg%2F11v0gzh078?entry=tts&g_ep=EgoyMDI1MDgxOS4wIPu8ASoASAFQAw%3D%3D&skid=bc0eadd9-6b3f-4bc0-afc7-0d81f9387036"

    /// Location header of the second hop seen from a Swiss IP (2026-10-17): the consent page wrapping the Maps URL.
    static let consentRedirect =
        "https://consent.google.com/ml?continue=https://www.google.com/maps/place/Copenhagen%2BCoffee%2BLab/@43.6764552,6.9908374,10.65z/data%3D!4m7!3m6!1s0x12cdd180e7e5b347:0x641651765156f103!8m2!3d43.695783!4d7.260654!15sChVjb3BlbmhhZ2VuIGNvZmZlZSBsYWIiA4gBAVoXIhVjb3BlbmhhZ2VuIGNvZmZlZSBsYWKSAQtjb2ZmZWVfc2hvcKoBaAoNL2cvMTFma3l5NzhqMBABKhkiFWNvcGVuaGFnZW4gY29mZmVlIGxhYigAMh8QASIb36relNgo72m7fjH03ff9bDQMKo5st-5JVOBFMhkQAiIVY29wZW5oYWdlbiBjb2ZmZWUgbGFi4AEA!16s%252Fg%252F11v0gzh078?entry%3Dtts%26g_ep%3DEgoyMDI1MDgxOS4wIPu8ASoASAFQAw%253D%253D%26skid%3Dbc0eadd9-6b3f-4bc0-afc7-0d81f9387036&gl=CH&m=0&pc=m&uxe=eomtm&cm=2&hl=de&src=1"

    static let dongleId = "1a2b3c4d5e6f7a8b"

    /// Unsigned test JWT: header {"alg":"none"}, payload {"identity":"test","exp":1893456000}.
    static let testJwt = "eyJhbGciOiJub25lIn0.eyJpZGVudGl0eSI6InRlc3QiLCJleHAiOjE4OTM0NTYwMDB9.c2ln"
}

func foundDestination(_ result: LinkParseResult, file: StaticString = #filePath, line: UInt = #line) -> Destination? {
    switch result {
    case .found(let destination):
        return destination
    default:
        return nil
    }
}

func queryText(_ result: LinkParseResult) -> String? {
    switch result {
    case .query(let text):
        return text
    default:
        return nil
    }
}

func jsonObject(_ text: String?) -> [String: Any] {
    guard let text = text, let data = text.data(using: .utf8) else {
        return [:]
    }
    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return [:]
    }
    return object
}
