import Foundation

/// comma athena backend.
///
/// - Device list: GET {api}/v1/me/devices/ with "Authorization: JWT <token>".
/// - Commands: JSON-RPC 2.0 POSTed to https://athena.comma.ai/<dongle_id>, relayed by athena to the
///   device's athenad websocket.
/// - setNavDestination(latitude, longitude) and clearNavDestination() are the athenad methods of
///   openpilot / sunnypilot Nav Alpha. Only latitude and longitude are sent: the current athenad
///   signature has no other parameters and rejects unknown ones with JSON-RPC error -32602.
public final class CommaAthenaTransport: NavigationTransport {
    public let kind = BackendKind.commaAthena
    public let displayName = "comma athena"
    public let implemented = true

    private let http: HttpClient
    private let tokenProvider: () -> String?
    private let apiBaseUrl: String
    private let athenaBaseUrl: String

    public init(
        http: HttpClient,
        tokenProvider: @escaping () -> String?,
        apiBaseUrl: String = CommaEndpoints.apiBaseUrl,
        athenaBaseUrl: String = CommaEndpoints.athenaBaseUrl
    ) {
        self.http = http
        self.tokenProvider = tokenProvider
        self.apiBaseUrl = apiBaseUrl
        self.athenaBaseUrl = athenaBaseUrl
    }

    /// Checks a token before it is stored. The token is only used for this request.
    public func verifyToken(_ token: String) async -> Result<AccountInfo, TransportError> {
        let responseResult = await get(apiBaseUrl + CommaEndpoints.profilePath, token: token)
        switch responseResult {
        case .failure(let error):
            return .failure(error)
        case .success(let response):
            guard let profile = Json.parseObject(response.body) else {
                return .failure(.malformed(ErrorText.shorten(response.body)))
            }
            return .success(AccountInfo(email: Json.string(profile, "email")))
        }
    }

    public func listDevices() async -> Result<[PairedDevice], TransportError> {
        guard let token = tokenProvider() else {
            return .failure(.noToken)
        }
        let responseResult = await get(apiBaseUrl + CommaEndpoints.devicesPath, token: token)
        switch responseResult {
        case .failure(let error):
            return .failure(error)
        case .success(let response):
            guard let devices = CommaAthenaTransport.parseDevices(response.body) else {
                return .failure(.malformed(ErrorText.shorten(response.body)))
            }
            return .success(devices)
        }
    }

    public func checkStatus(_ device: PairedDevice) async -> Result<DeviceStatus, TransportError> {
        let rpcResult = await callAthena(device, method: CommaEndpoints.methodGetVersion, params: nil)
        switch rpcResult {
        case .failure(let error):
            return .failure(error)
        case .success(let rpc):
            switch rpc {
            case .error(_, let message):
                return .failure(.deviceError(message))
            case .malformed(let detail):
                return .failure(.malformed(detail))
            case .result(let value):
                guard let object = value as? [String: Any] else {
                    return .failure(.malformed(ErrorText.shorten("\(value ?? "null")")))
                }
                return .success(
                    DeviceStatus(
                        version: Json.string(object, "version"),
                        branch: Json.string(object, "branch"),
                        remote: Json.string(object, "remote"),
                        commit: Json.string(object, "commit")
                    )
                )
            }
        }
    }

    public func setDestination(_ device: PairedDevice, _ destination: Destination) async -> Result<Delivery, TransportError> {
        if !CoordinateRules.isValid(latitude: destination.latitude, longitude: destination.longitude) {
            return .failure(.invalidRequest("Coordinates out of range"))
        }
        let params: [String: Any] = [
            "latitude": destination.latitude,
            "longitude": destination.longitude,
        ]
        let rpcResult = await callAthena(device, method: CommaEndpoints.methodSetNavDestination, params: params)
        return interpretCommandResult(rpcResult, method: CommaEndpoints.methodSetNavDestination)
    }

    public func setRoute(_ device: PairedDevice, _ destination: Destination, waypoints: [RouteWaypoint]) async -> Result<Delivery, TransportError> {
        if waypoints.isEmpty {
            return await setDestination(device, destination)
        }
        if !CoordinateRules.isValid(latitude: destination.latitude, longitude: destination.longitude) {
            return .failure(.invalidRequest("Coordinates out of range"))
        }
        var waypointParams: [[String: Any]] = []
        for waypoint in waypoints {
            if !CoordinateRules.isValid(latitude: waypoint.latitude, longitude: waypoint.longitude) {
                return .failure(.invalidRequest("Waypoint out of range"))
            }
            waypointParams.append([
                "latitude": waypoint.latitude,
                "longitude": waypoint.longitude,
                "via": waypoint.via,
            ])
        }
        let params: [String: Any] = [
            "latitude": destination.latitude,
            "longitude": destination.longitude,
            "waypoints": waypointParams,
        ]
        let rpcResult = await callAthena(device, method: CommaEndpoints.methodSetNavRoute, params: params)
        let result = interpretCommandResult(rpcResult, method: CommaEndpoints.methodSetNavRoute)
        // comma's Nav Alpha has no setNavRoute: send the destination alone, the device picks its own route
        if case .failure(.methodNotAvailable(CommaEndpoints.methodSetNavRoute)) = result {
            let fallback = await setDestination(device, destination)
            if case .success(let delivery) = fallback {
                return .success(Delivery(queued: delivery.queued, note: CommaAthenaTransport.noWaypointsNote))
            }
            return fallback
        }
        return result
    }

    public static let noWaypointsNote = "The device has no waypoint support (setNavRoute): it got the destination only and picks its own route."

    public func setMapboxToken(_ device: PairedDevice, _ token: String) async -> Result<Delivery, TransportError> {
        let params: [String: Any] = ["token": token]
        let rpcResult = await callAthena(device, method: CommaEndpoints.methodSetMapboxToken, params: params)
        return interpretCommandResult(rpcResult, method: CommaEndpoints.methodSetMapboxToken)
    }

    public func clearDestination(_ device: PairedDevice) async -> Result<Delivery, TransportError> {
        let rpcResult = await callAthena(device, method: CommaEndpoints.methodClearNavDestination, params: nil)
        return interpretCommandResult(rpcResult, method: CommaEndpoints.methodClearNavDestination)
    }

    private func callAthena(_ device: PairedDevice, method: String, params: [String: Any]?) async -> Result<RpcResponse, TransportError> {
        guard let token = tokenProvider() else {
            return .failure(.noToken)
        }
        if !DongleIdRules.isValid(device.dongleId) {
            return .failure(.invalidRequest("Invalid dongle ID"))
        }
        let request = HttpRequest(
            method: "POST",
            url: athenaBaseUrl + "/" + device.dongleId,
            headers: [
                "Authorization": "JWT " + token,
                "Content-Type": "application/json",
                "Accept": "application/json",
            ],
            body: JsonRpc.buildRequest(method: method, params: params)
        )
        let responseResult = await execute(request)
        switch responseResult {
        case .failure(let error):
            return .failure(error)
        case .success(let response):
            return .success(JsonRpc.parseResponse(response.body))
        }
    }

    private func interpretCommandResult(_ rpcResult: Result<RpcResponse, TransportError>, method: String) -> Result<Delivery, TransportError> {
        let rpc: RpcResponse
        switch rpcResult {
        case .failure(let error):
            return .failure(error)
        case .success(let value):
            rpc = value
        }

        switch rpc {
        case .error(let code, let message):
            if code == JsonRpc.methodNotFound {
                return .failure(.methodNotAvailable(method))
            }
            if code == JsonRpc.invalidParams {
                return .failure(.invalidRequest(message))
            }
            // Builds without Nav Alpha can still carry the old athenad setNavDestination, which writes a
            // NavDestination param that their params_keys.h does not define: Params().put fails and the
            // dispatcher answers -32000 with the message "'NavDestination'" (seen on sunnypilot 2026.003.000).
            if message.contains("NavDestination") {
                return .failure(.methodNotAvailable(method))
            }
            return .failure(.deviceError(message))
        case .malformed(let detail):
            return .failure(.malformed(detail))
        case .result(let value):
            if let object = value as? [String: Any] {
                if isSuccess(object["success"]) {
                    return .success(Delivery(queued: false, note: ""))
                }
                var reason = "The device did not accept the command"
                if !Json.isNull(object, "error") {
                    reason = Json.string(object, "error")
                }
                return .failure(.deviceRejected(reason))
            }
            // api.comma.ai docs: for queued messages "result is string containing `Device offline, message queued`"
            if let text = value as? String {
                if text.lowercased().contains("queued") {
                    return .success(Delivery(queued: true, note: text))
                }
                return .failure(.malformed(ErrorText.shorten(text)))
            }
            return .failure(.malformed(ErrorText.shorten("\(value ?? "null")")))
        }
    }

    private func isSuccess(_ successValue: Any?) -> Bool {
        if let number = successValue as? NSNumber {
            return number.intValue == 1
        }
        return false
    }

    private func get(_ url: String, token: String) async -> Result<HttpResponse, TransportError> {
        let request = HttpRequest(
            method: "GET",
            url: url,
            headers: [
                "Authorization": "JWT " + token,
                "Accept": "application/json",
            ]
        )
        return await execute(request)
    }

    private func execute(_ request: HttpRequest) async -> Result<HttpResponse, TransportError> {
        let response: HttpResponse
        do {
            response = try await http.execute(request)
        } catch {
            return .failure(.network(error.localizedDescription))
        }

        if response.code == 401 {
            return .failure(.unauthorized)
        }
        if response.code == 403 {
            return .failure(.forbidden)
        }
        if response.code == 429 {
            return .failure(.rateLimited)
        }
        if !response.isSuccessful() {
            return .failure(.httpFailure(code: response.code, detail: ErrorText.fromHttpBody(response.body)))
        }
        return .success(response)
    }

    /// Devices from GET /v1/me/devices/; nil when the body is not a JSON array.
    public static func parseDevices(_ body: String) -> [PairedDevice]? {
        guard let array = Json.parseArray(body) else {
            return nil
        }
        var devices: [PairedDevice] = []
        for element in array {
            guard let item = element as? [String: Any] else {
                continue
            }
            let dongleId = DongleIdRules.normalize(Json.string(item, "dongle_id"))
            if !DongleIdRules.isValid(dongleId) {
                continue
            }
            devices.append(
                PairedDevice(
                    dongleId: dongleId,
                    alias: Json.string(item, "alias"),
                    deviceType: Json.string(item, "device_type"),
                    lastAthenaPingSeconds: Json.int64(item, "last_athena_ping", defaultValue: 0),
                    isOwner: Json.bool(item, "is_owner", defaultValue: true),
                    backend: .commaAthena,
                    addedManually: false
                )
            )
        }
        return devices
    }
}
