import XCTest
@testable import Nav2PilotKit

final class CommaAthenaTransportTests: XCTestCase {
    private var http = FakeHttpClient()
    private var token: String? = "secret.jwt.token"
    private var transport: CommaAthenaTransport!
    private let device = PairedDevice(dongleId: Fixtures.dongleId, alias: "Peugeot 3008")
    private let destination = Destination(latitude: 45.4642, longitude: 9.19, name: "Duomo", details: "Milano")

    override func setUp() {
        super.setUp()
        http = FakeHttpClient()
        token = "secret.jwt.token"
        transport = CommaAthenaTransport(http: http, tokenProvider: { [unowned self] in
            return self.token
        })
    }

    private func failure<T>(_ result: Result<T, TransportError>, file: StaticString = #filePath, line: UInt = #line) -> TransportError? {
        switch result {
        case .success(let value):
            XCTFail("expected failure but got \(value)", file: file, line: line)
            return nil
        case .failure(let error):
            return error
        }
    }

    func testSetDestinationPostsJsonRpcToAthena() async {
        http.respond(200, #"{"jsonrpc": "2.0", "id": 0, "result": {"success": 1}}"#)

        let result = await transport.setDestination(device, destination)

        XCTAssertEqual(.success(Delivery(queued: false, note: "")), result)
        XCTAssertEqual(1, http.requests.count)
        let request = http.requests[0]
        XCTAssertEqual("POST", request.method)
        XCTAssertEqual("https://athena.comma.ai/" + Fixtures.dongleId, request.url)
        XCTAssertEqual("JWT secret.jwt.token", request.headers["Authorization"])
        XCTAssertEqual("application/json", request.headers["Content-Type"])

        let body = jsonObject(request.body)
        XCTAssertEqual("setNavDestination", body["method"] as? String)
        XCTAssertEqual("2.0", body["jsonrpc"] as? String)
        XCTAssertEqual(0, body["id"] as? Int)
        let params = body["params"] as? [String: Any] ?? [:]
        XCTAssertEqual(45.4642, params["latitude"] as? Double)
        XCTAssertEqual(9.19, params["longitude"] as? Double)
        // athenad's setNavDestination(latitude, longitude) has no other parameters; extra keys would be -32602
        XCTAssertEqual(2, params.count)
    }

    func testClearDestinationSendsNoParams() async {
        http.respond(200, #"{"jsonrpc": "2.0", "id": 0, "result": {"success": 1}}"#)

        let result = await transport.clearDestination(device)

        XCTAssertEqual(.success(Delivery(queued: false, note: "")), result)
        let body = jsonObject(http.requests[0].body)
        XCTAssertEqual("clearNavDestination", body["method"] as? String)
        XCTAssertNil(body["params"])
    }

    func testDeviceRejectionIsReported() async {
        http.respond(200, #"{"jsonrpc": "2.0", "id": 0, "result": {"success": 0, "error": "Invalid destination coordinates"}}"#)

        let error = failure(await transport.setDestination(device, destination))

        XCTAssertEqual(.deviceRejected("Invalid destination coordinates"), error)
    }

    func testMissingMethodMeansNoNavAlpha() async {
        // shape of openpilot system/athena/rpc.py dumps_error
        http.respond(200, #"{"jsonrpc": "2.0", "id": 0, "error": {"code": -32601, "message": "method not found: setNavDestination"}}"#)

        let error = failure(await transport.setDestination(device, destination))

        XCTAssertEqual(.methodNotAvailable("setNavDestination"), error)
        XCTAssertTrue(TransportErrorText.describe(error!).contains("Nav Alpha"))
    }

    func testOldSetNavDestinationWithoutNavAlphaParam() async {
        // real answer of sunnypilot 2026.003.000 without Nav Alpha (2026-10-17)
        http.respond(200, #"{"jsonrpc": "2.0", "id": 0, "error": {"code": -32000, "message": "'NavDestination'"}}"#)

        let error = failure(await transport.setDestination(device, destination))

        XCTAssertEqual(.methodNotAvailable("setNavDestination"), error)
        XCTAssertTrue(TransportErrorText.describe(error!).contains("Nav Alpha"))
    }

    func testInvalidParamsAndServerErrors() async {
        http.respond(200, #"{"jsonrpc": "2.0", "id": 0, "error": {"code": -32602, "message": "unexpected keyword argument"}}"#)
        let result1 = await transport.setDestination(device, destination)
        XCTAssertEqual(.invalidRequest("unexpected keyword argument"), failure(result1))

        http.respond(200, #"{"jsonrpc": "2.0", "id": 0, "error": {"code": -32000, "message": "boom"}}"#)
        let result2 = await transport.setDestination(device, destination)
        XCTAssertEqual(.deviceError("boom"), failure(result2))
    }

    func testQueuedResultString() async {
        // api.comma.ai: "For queued messages, result is string containing `Device offline, message queued`"
        http.respond(200, #"{"jsonrpc": "2.0", "id": 0, "result": "Device offline, message queued"}"#)

        let result = await transport.setDestination(device, destination)

        XCTAssertEqual(.success(Delivery(queued: true, note: "Device offline, message queued")), result)
    }

    func testHttpStatusMapping() async {
        http.respond(401, #"{"error": "unauthorized"}"#)
        let result3 = await transport.setDestination(device, destination)
        XCTAssertEqual(.unauthorized, failure(result3))
        http.respond(403, "")
        let result4 = await transport.setDestination(device, destination)
        XCTAssertEqual(.forbidden, failure(result4))
        http.respond(429, "")
        let result5 = await transport.setDestination(device, destination)
        XCTAssertEqual(.rateLimited, failure(result5))
        // illustrative body: athena's real error body for an unknown or offline device is not documented
        http.respond(404, #"{"error": "Device not found"}"#)
        let result6 = await transport.setDestination(device, destination)
        XCTAssertEqual(.httpFailure(code: 404, detail: "Device not found"), failure(result6))
    }

    func testNetworkErrorDoesNotLeakTheToken() async {
        http.fail("connect timed out")

        let error = failure(await transport.setDestination(device, destination))

        XCTAssertEqual(.network("connect timed out"), error)
        XCTAssertFalse(TransportErrorText.describe(error!).contains("secret"))
        XCTAssertFalse(http.requests[0].description.contains("secret"))
    }

    func testNoTokenNoRequest() async {
        token = nil

        let result7 = await transport.setDestination(device, destination)
        XCTAssertEqual(.noToken, failure(result7))
        let result8 = await transport.listDevices()
        XCTAssertEqual(.noToken, failure(result8))
        XCTAssertTrue(http.requests.isEmpty)
    }

    func testInvalidInputIsRejectedLocally() async {
        let badDevice = PairedDevice(dongleId: "not-a-dongle", alias: "x")
        let result9 = await transport.setDestination(badDevice, destination)
        XCTAssertEqual(.invalidRequest("Invalid dongle ID"), failure(result9))
        let outOfRange = await transport.setDestination(device, Destination(latitude: 95, longitude: 0))
        XCTAssertEqual(.invalidRequest("Coordinates out of range"), failure(outOfRange))
        XCTAssertTrue(http.requests.isEmpty)
    }

    func testCheckStatusUsesGetVersion() async {
        http.respond(
            200,
            #"{"jsonrpc": "2.0", "id": 0, "result": {"version": "0.10.1", "remote": "github.com/sunnypilot/sunnypilot", "branch": "feature/nav-alpha", "commit": "689f3a1", "commit_date": "2026-10-17"}}"#
        )

        let result = await transport.checkStatus(device)

        guard case .success(let status) = result else {
            return XCTFail("got \(result)")
        }
        XCTAssertEqual("0.10.1", status.version)
        XCTAssertEqual("feature/nav-alpha", status.branch)
        XCTAssertEqual("getVersion", jsonObject(http.requests[0].body)["method"] as? String)
    }

    func testListDevicesParsesTheDocumentedFields() async {
        http.respond(
            200,
            #"""
            [
              {"dongle_id": "1a2b3c4d5e6f7a8b", "alias": "Peugeot 3008", "device_type": "three", "last_athena_ping": 1760700000, "is_owner": true, "prime": false},
              {"dongle_id": "ffffffffffffffff", "alias": null, "device_type": "mici", "last_athena_ping": null, "is_owner": false},
              {"dongle_id": "bad", "alias": "ignored"}
            ]
            """#
        )

        guard case .success(let devices) = await transport.listDevices() else {
            return XCTFail("listDevices failed")
        }

        let request = http.requests[0]
        XCTAssertEqual("GET", request.method)
        XCTAssertEqual("https://api.commadotai.com/v1/me/devices/", request.url)
        XCTAssertEqual("JWT secret.jwt.token", request.headers["Authorization"])

        XCTAssertEqual(2, devices.count)
        XCTAssertEqual(
            PairedDevice(dongleId: "1a2b3c4d5e6f7a8b", alias: "Peugeot 3008", deviceType: "three", lastAthenaPingSeconds: 1760700000, isOwner: true, backend: .commaAthena, addedManually: false, prime: false),
            devices[0]
        )
        XCTAssertTrue(devices[0].needsMapboxForRoutes())
        // no "prime" field: unknown, which also counts as no prime
        XCTAssertNil(devices[1].prime)
        XCTAssertTrue(devices[1].needsMapboxForRoutes())
        XCTAssertEqual("", devices[1].alias)
        XCTAssertEqual(0, devices[1].lastAthenaPingSeconds)
        XCTAssertFalse(devices[1].isOwner)
        XCTAssertEqual("ffffffffffffffff", devices[1].displayName())
    }

    func testVerifyTokenUsesTheGivenTokenNotTheStoredOne() async {
        http.respond(200, #"{"email": "driver@example.com", "id": "abcdef0123456789", "username": null}"#)

        let result = await transport.verifyToken("candidate.jwt.value")

        XCTAssertEqual(.success(AccountInfo(email: "driver@example.com")), result)
        let request = http.requests[0]
        XCTAssertEqual("https://api.commadotai.com/v1/me/", request.url)
        XCTAssertEqual("JWT candidate.jwt.value", request.headers["Authorization"])
    }

    func testSunnylinkIsAnExplicitStub() async {
        let sunnylink = SunnylinkTransport()
        XCTAssertFalse(sunnylink.implemented)
        var sunnylinkDevice = device
        sunnylinkDevice.backend = .sunnylink
        let error = failure(await sunnylink.setDestination(sunnylinkDevice, destination))
        XCTAssertEqual(.notImplemented(SunnylinkTransport.reason), error)

        let registry = TransportRegistry(comma: transport, sunnylink: sunnylink)
        XCTAssertTrue(registry.forDevice(device) === transport)
        XCTAssertTrue(registry.forDevice(sunnylinkDevice) === sunnylink)
    }
}

final class JsonRpcTests: XCTestCase {
    func testRequestWithoutParams() {
        let json = jsonObject(JsonRpc.buildRequest(method: "getVersion", params: nil))
        XCTAssertEqual("getVersion", json["method"] as? String)
        XCTAssertEqual("2.0", json["jsonrpc"] as? String)
        XCTAssertEqual(0, json["id"] as? Int)
        XCTAssertNil(json["params"])
    }

    func testParsesResultErrorAndGarbage() {
        if case .result(let value) = JsonRpc.parseResponse(#"{"jsonrpc":"2.0","id":0,"result":{"success":1}}"#) {
            XCTAssertNotNil(value as? [String: Any])
        } else {
            XCTFail("expected a result")
        }

        if case .result(let value) = JsonRpc.parseResponse(#"{"jsonrpc":"2.0","id":0,"result":null}"#) {
            XCTAssertNil(value)
        } else {
            XCTFail("expected a null result")
        }

        if case .error(let code, let message) = JsonRpc.parseResponse(#"{"jsonrpc":"2.0","id":0,"error":{"code":-32601,"message":"method not found: x"}}"#) {
            XCTAssertEqual(-32601, code)
            XCTAssertEqual("method not found: x", message)
        } else {
            XCTFail("expected an error")
        }

        if case .error(let code, let message) = JsonRpc.parseResponse(#"{"error":"plain"}"#) {
            XCTAssertEqual(0, code)
            XCTAssertEqual("plain", message)
        } else {
            XCTFail("expected an error")
        }

        if case .malformed = JsonRpc.parseResponse("<html>bad gateway</html>") {
        } else {
            XCTFail("expected malformed")
        }
        if case .malformed = JsonRpc.parseResponse(#"{"jsonrpc":"2.0","id":0}"#) {
        } else {
            XCTFail("expected malformed")
        }
    }

    func testErrorTextIsShortAndSingleLine() {
        let long = String(repeating: "x", count: 500)
        XCTAssertLessThanOrEqual(ErrorText.shorten(long).count, 201)
        XCTAssertEqual("a b", ErrorText.shorten("a\nb"))
        XCTAssertEqual("Device not found", ErrorText.fromHttpBody(#"{"error":"Device not found"}"#))
        XCTAssertEqual("not json", ErrorText.fromHttpBody("not json"))
    }
}
