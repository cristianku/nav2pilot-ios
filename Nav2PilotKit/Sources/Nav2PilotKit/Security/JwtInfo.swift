import Foundation

/// Reads public claims of a JWT for display only (RFC 7519). The signature is not verified here:
/// the comma API verifies it on every request.
public enum JwtInfo {
    public static func looksLikeJwt(_ token: String) -> Bool {
        let parts = token.components(separatedBy: ".")
        if parts.count != 3 {
            return false
        }
        for part in parts {
            if part.isEmpty {
                return false
            }
        }
        for character in token {
            if character.isWhitespace {
                return false
            }
        }
        return true
    }

    /// The "exp" claim (seconds since epoch), or nil when absent or unreadable.
    public static func expirySeconds(_ token: String) -> Int64? {
        guard let payload = payload(token) else {
            return nil
        }
        guard let number = payload["exp"] as? NSNumber else {
            return nil
        }
        let expiry = number.int64Value
        if expiry <= 0 {
            return nil
        }
        return expiry
    }

    private static func payload(_ token: String) -> [String: Any]? {
        if !looksLikeJwt(token) {
            return nil
        }
        let encodedPayload = token.components(separatedBy: ".")[1]
        guard let data = base64UrlDecode(encodedPayload) else {
            return nil
        }
        return Json.parseObject(String(decoding: data, as: UTF8.self))
    }

    /// Base64url without padding (RFC 7515 appendix C) to Data.
    private static func base64UrlDecode(_ text: String) -> Data? {
        var base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder == 1 {
            return nil
        }
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: base64)
    }
}
