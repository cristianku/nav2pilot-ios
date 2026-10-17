import XCTest
@testable import Nav2PilotKit

/// Real network calls, skipped unless NAV2PILOT_NETWORK_TESTS=1 (CI and normal runs stay offline).
/// No comma token is used: only the public Google short link and Apple's map search are contacted.
final class NetworkIntegrationTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["NAV2PILOT_NETWORK_TESTS"] == "1", "network tests disabled")
    }

    func testRealGoogleShortLinkResolvesToThePin() async {
        let http = URLSessionHttpClient(userAgent: "Nav2Pilot-tests")
        let result = await ShortLinkResolver(http: http).resolve(Fixtures.shortLink)

        XCTAssertEqual("", result.networkError)
        let destination = foundDestination(result.result)
        XCTAssertEqual(43.695783, destination?.latitude ?? 0, accuracy: 0.0001)
        XCTAssertEqual(7.260654, destination?.longitude ?? 0, accuracy: 0.0001)
        XCTAssertEqual(false, destination?.approximate)
    }

    func testRealAppleMapsLegacyLinkRedirectsToPlace() async throws {
        let http = URLSessionHttpClient(userAgent: "Nav2Pilot-tests")
        let response = try await http.execute(
            HttpRequest(method: "GET", url: "https://maps.apple.com/?ll=45.4642,9.19&q=Duomo", followRedirects: false, readBody: false)
        )
        XCTAssertTrue(response.isRedirect())
        XCTAssertEqual("/place?coordinate=45.4642%2C9.19&name=Duomo", response.header("Location"))
    }

    func testMapKitSearchFindsAnAddress() async throws {
        let results = try await MapKitPlaceSearch().search("Piazza del Duomo, Milano", maxResults: 5)
        XCTAssertFalse(results.isEmpty)
        XCTAssertEqual(45.464, results[0].latitude, accuracy: 0.01)
        XCTAssertEqual(9.19, results[0].longitude, accuracy: 0.01)
    }
}

/// Read-only calls with a real comma token, skipped unless NAV2PILOT_COMMA_TOKEN is set:
/// token check, device list and getVersion. It never sends or clears a destination.
final class CommaAccountIntegrationTests: XCTestCase {
    private var token = ""

    override func setUpWithError() throws {
        token = ProcessInfo.processInfo.environment["NAV2PILOT_COMMA_TOKEN"] ?? ""
        try XCTSkipIf(token.isEmpty, "NAV2PILOT_COMMA_TOKEN not set")
    }

    func testTokenDevicesAndStatus() async {
        let http = URLSessionHttpClient(userAgent: "Nav2Pilot-tests")
        let currentToken = token
        let transport = CommaAthenaTransport(http: http, tokenProvider: {
            return currentToken
        })

        let account = await transport.verifyToken(token)
        guard case .success = account else {
            return XCTFail("token check failed: \(account)")
        }

        let devicesResult = await transport.listDevices()
        guard case .success(let devices) = devicesResult else {
            return XCTFail("device list failed: \(devicesResult)")
        }
        XCTAssertFalse(devices.isEmpty)
        for device in devices {
            let status = await transport.checkStatus(device)
            // an offroad or sleeping device is a valid answer too; it just must not be an auth problem
            if case .failure(let error) = status {
                XCTAssertNotEqual(.unauthorized, error)
                print("\(device.dongleId): \(TransportErrorText.describe(error))")
            } else if case .success(let deviceStatus) = status {
                print("\(device.dongleId): online \(deviceStatus.version) \(deviceStatus.branch)")
            }
        }
    }
}
