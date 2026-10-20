import Foundation

public struct Favorite: Equatable, Identifiable {
    public let id: String
    public let destination: Destination

    public init(id: String, destination: Destination) {
        self.id = id
        self.destination = destination
    }
}

/// JSON encoding of locally stored, non-secret data (same format as the Android app).
public enum JsonCodec {
    static func destinationToJson(_ destination: Destination) -> [String: Any] {
        return [
            "latitude": destination.latitude,
            "longitude": destination.longitude,
            "name": destination.name,
            "details": destination.details,
            "approximate": destination.approximate,
        ]
    }

    static func destinationFromJson(_ json: [String: Any]) -> Destination? {
        guard let latitude = Json.double(json, "latitude") else {
            return nil
        }
        guard let longitude = Json.double(json, "longitude") else {
            return nil
        }
        if !CoordinateRules.isValid(latitude: latitude, longitude: longitude) {
            return nil
        }
        return Destination(
            latitude: latitude,
            longitude: longitude,
            name: Json.string(json, "name"),
            details: Json.string(json, "details"),
            approximate: Json.bool(json, "approximate", defaultValue: false)
        )
    }

    public static func favoritesToJson(_ favorites: [Favorite]) -> String {
        var array: [[String: Any]] = []
        for favorite in favorites {
            array.append([
                "id": favorite.id,
                "destination": destinationToJson(favorite.destination),
            ])
        }
        return Json.serialize(array)
    }

    public static func favoritesFromJson(_ text: String) -> [Favorite] {
        var favorites: [Favorite] = []
        guard let array = Json.parseArray(text) else {
            return favorites
        }
        for element in array {
            guard let item = element as? [String: Any] else {
                continue
            }
            let id = Json.string(item, "id")
            if id.isEmpty {
                continue
            }
            guard let destinationJson = item["destination"] as? [String: Any] else {
                continue
            }
            guard let destination = destinationFromJson(destinationJson) else {
                continue
            }
            favorites.append(Favorite(id: id, destination: destination))
        }
        return favorites
    }

    public static func devicesToJson(_ devices: [PairedDevice]) -> String {
        var array: [[String: Any]] = []
        for device in devices {
            var item: [String: Any] = [
                "dongle_id": device.dongleId,
                "alias": device.alias,
                "device_type": device.deviceType,
                "last_athena_ping": NSNumber(value: device.lastAthenaPingSeconds),
                "is_owner": device.isOwner,
                "backend": device.backend.rawValue,
                "added_manually": device.addedManually,
            ]
            if let prime = device.prime {
                item["prime"] = prime
            }
            array.append(item)
        }
        return Json.serialize(array)
    }

    public static func devicesFromJson(_ text: String) -> [PairedDevice] {
        var devices: [PairedDevice] = []
        guard let array = Json.parseArray(text) else {
            return devices
        }
        for element in array {
            guard let item = element as? [String: Any] else {
                continue
            }
            let dongleId = Json.string(item, "dongle_id")
            if dongleId.isEmpty {
                continue
            }
            devices.append(
                PairedDevice(
                    dongleId: dongleId,
                    alias: Json.string(item, "alias"),
                    deviceType: Json.string(item, "device_type"),
                    lastAthenaPingSeconds: Json.int64(item, "last_athena_ping", defaultValue: 0),
                    isOwner: Json.bool(item, "is_owner", defaultValue: true),
                    backend: BackendKind.fromId(Json.string(item, "backend")),
                    addedManually: Json.bool(item, "added_manually", defaultValue: false),
                    prime: Json.optionalBool(item, "prime")
                )
            )
        }
        return devices
    }
}
