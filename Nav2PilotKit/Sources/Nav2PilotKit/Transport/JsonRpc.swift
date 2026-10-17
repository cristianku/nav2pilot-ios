import Foundation

public enum RpcResponse {
    /// `result` member: a dictionary, String, NSNumber or nil (JSON null).
    case result(Any?)
    case error(code: Int, message: String)
    case malformed(String)
}

/// JSON-RPC 2.0 messages as used by athena.
///
/// Request shape from the comma API schema (JSONRPCPayload: method, jsonrpc "2.0", id 0, optional params).
/// Error shape from openpilot system/athena/rpc.py dumps_error: {"error": {"code": ..., "message": ...}}.
public enum JsonRpc {
    public static let methodNotFound = -32601
    public static let invalidParams = -32602

    public static func buildRequest(method: String, params: [String: Any]?) -> String {
        var request: [String: Any] = [:]
        request["method"] = method
        if let params = params {
            request["params"] = params
        }
        request["jsonrpc"] = "2.0"
        request["id"] = 0
        return Json.serialize(request)
    }

    public static func parseResponse(_ body: String) -> RpcResponse {
        guard let json = Json.parseObject(body) else {
            return .malformed(ErrorText.shorten(body))
        }

        if !Json.isNull(json, "error") {
            let error = json["error"]
            if let errorObject = error as? [String: Any] {
                var code = 0
                if let number = errorObject["code"] as? NSNumber {
                    code = number.intValue
                }
                return .error(code: code, message: Json.string(errorObject, "message"))
            }
            if let text = error as? String {
                return .error(code: 0, message: text)
            }
            return .error(code: 0, message: "\(error ?? "")")
        }

        if let result = json["result"] {
            if result is NSNull {
                return .result(nil)
            }
            return .result(result)
        }

        return .malformed(ErrorText.shorten(body))
    }
}

public enum ErrorText {
    private static let maxLength = 200

    public static func shorten(_ text: String) -> String {
        let singleLine = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespaces)
        if singleLine.count <= maxLength {
            return singleLine
        }
        return String(singleLine.prefix(maxLength)) + "…"
    }

    /// Best-effort human readable detail from an HTTP error body.
    public static func fromHttpBody(_ body: String) -> String {
        if let json = Json.parseObject(body) {
            for key in ["description", "error", "message"] {
                if let value = json[key] as? String {
                    if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        return shorten(value)
                    }
                }
            }
        }
        return shorten(body)
    }
}
