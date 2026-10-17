import Foundation

/// Small helpers around JSONSerialization, with the same lenient rules as Android's org.json usage.
enum Json {
    /// The top-level value of `text`, or nil when it is not JSON.
    static func parse(_ text: String) -> Any? {
        guard let data = text.data(using: .utf8) else {
            return nil
        }
        return try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    static func parseObject(_ text: String) -> [String: Any]? {
        return parse(text) as? [String: Any]
    }

    static func parseArray(_ text: String) -> [Any]? {
        return parse(text) as? [Any]
    }

    static func serialize(_ value: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) else {
            return ""
        }
        return String(decoding: data, as: UTF8.self)
    }

    static func isNull(_ object: [String: Any], _ key: String) -> Bool {
        guard let value = object[key] else {
            return true
        }
        return value is NSNull
    }

    /// "" for a missing or null value; numbers and booleans are converted to text.
    static func string(_ object: [String: Any], _ key: String) -> String {
        guard let value = object[key] else {
            return ""
        }
        if let text = value as? String {
            return text
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return ""
    }

    static func int64(_ object: [String: Any], _ key: String, defaultValue: Int64) -> Int64 {
        if let number = object[key] as? NSNumber {
            return number.int64Value
        }
        return defaultValue
    }

    static func double(_ object: [String: Any], _ key: String) -> Double? {
        if let number = object[key] as? NSNumber {
            return number.doubleValue
        }
        return nil
    }

    static func bool(_ object: [String: Any], _ key: String, defaultValue: Bool) -> Bool {
        if let number = object[key] as? NSNumber {
            return number.boolValue
        }
        return defaultValue
    }
}
