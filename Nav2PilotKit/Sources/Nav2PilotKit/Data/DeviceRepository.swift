import Foundation

/// Paired devices (from the comma account and added by hand) and the currently selected one.
public final class DeviceRepository {
    public static let keyDevices = "devices"
    public static let keySelected = "selected_dongle_id"

    private let store: KeyValueStore
    public private(set) var devices: [PairedDevice] = []
    public private(set) var selectedDongleId = ""

    public init(store: KeyValueStore) {
        self.store = store
        reload()
    }

    /// Reads the stored devices and selection again (the share extension may have changed them).
    public func reload() {
        if let text = store.getString(DeviceRepository.keyDevices) {
            devices = JsonCodec.devicesFromJson(text)
        } else {
            devices = []
        }
        selectedDongleId = store.getString(DeviceRepository.keySelected) ?? ""
        ensureValidSelection()
    }

    /// Replaces the devices that came from the account with `accountDevices`.
    /// Manually added devices stay, unless the account now lists the same dongle ID.
    public func replaceAccountDevices(_ accountDevices: [PairedDevice]) {
        var updated: [PairedDevice] = []
        for device in accountDevices {
            var accountDevice = device
            accountDevice.addedManually = false
            updated.append(accountDevice)
        }
        for device in devices {
            if device.addedManually && !containsId(accountDevices, device.dongleId) {
                updated.append(device)
            }
        }
        saveDevices(updated)
        ensureValidSelection()
    }

    /// False when a device with the same dongle ID already exists.
    @discardableResult
    public func addManual(_ device: PairedDevice) -> Bool {
        if containsId(devices, device.dongleId) {
            return false
        }
        var manualDevice = device
        manualDevice.addedManually = true
        var updated = devices
        updated.append(manualDevice)
        saveDevices(updated)
        ensureValidSelection()
        return true
    }

    public func remove(_ dongleId: String) {
        var updated: [PairedDevice] = []
        for device in devices {
            if device.dongleId != dongleId {
                updated.append(device)
            }
        }
        saveDevices(updated)
        ensureValidSelection()
    }

    public func select(_ dongleId: String) {
        if !containsId(devices, dongleId) {
            return
        }
        saveSelection(dongleId)
    }

    public func selectedDevice() -> PairedDevice? {
        for device in devices {
            if device.dongleId == selectedDongleId {
                return device
            }
        }
        return nil
    }

    private func ensureValidSelection() {
        if containsId(devices, selectedDongleId) {
            return
        }
        if devices.isEmpty {
            saveSelection("")
        } else {
            saveSelection(devices[0].dongleId)
        }
    }

    private func containsId(_ list: [PairedDevice], _ dongleId: String) -> Bool {
        for device in list {
            if device.dongleId == dongleId {
                return true
            }
        }
        return false
    }

    private func saveDevices(_ updated: [PairedDevice]) {
        store.putString(DeviceRepository.keyDevices, JsonCodec.devicesToJson(updated))
        devices = updated
    }

    private func saveSelection(_ dongleId: String) {
        if dongleId.isEmpty {
            store.remove(DeviceRepository.keySelected)
        } else {
            store.putString(DeviceRepository.keySelected, dongleId)
        }
        selectedDongleId = dongleId
    }
}
