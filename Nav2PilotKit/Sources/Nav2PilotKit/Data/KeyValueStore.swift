import Foundation

/// Small string key-value storage, so repositories can be unit tested without UserDefaults.
public protocol KeyValueStore: AnyObject {
    func getString(_ key: String) -> String?
    func putString(_ key: String, _ value: String)
    func remove(_ key: String)
}

/// UserDefaults of the App Group, shared by the app and the share extension. Holds non-secret data only.
public final class UserDefaultsStore: KeyValueStore {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public func getString(_ key: String) -> String? {
        return defaults.string(forKey: key)
    }

    public func putString(_ key: String, _ value: String) {
        defaults.set(value, forKey: key)
    }

    public func remove(_ key: String) {
        defaults.removeObject(forKey: key)
    }
}
