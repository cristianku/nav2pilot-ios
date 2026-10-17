import Nav2PilotKit
import SwiftUI

struct DevicesView: View {
    @Bindable var viewModel: MainViewModel
    @State private var addDeviceVisible = false

    var body: some View {
        NavigationStack {
            Form {
                accountSection()
                devicesSection()
                Section {
                    Button {
                        addDeviceVisible = true
                    } label: {
                        Label("Add device by dongle ID", systemImage: "plus")
                    }
                }
                mapboxSection()
                backendsSection()
            }
            .navigationTitle("Devices")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if viewModel.refreshingDevices {
                        ProgressView()
                    } else {
                        Button {
                            Task {
                                await viewModel.refreshDevices()
                            }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .accessibilityLabel("Refresh devices from comma")
                        }
                        .disabled(!viewModel.hasToken)
                    }
                }
            }
            .sheet(isPresented: $viewModel.tokenSheetVisible) {
                TokenSheet(viewModel: viewModel)
            }
            .sheet(isPresented: $addDeviceVisible) {
                AddDeviceSheet(viewModel: viewModel)
            }
        }
    }

    private func accountSection() -> some View {
        Section("comma account") {
            if viewModel.hasToken {
                Label("Token stored in the iOS Keychain", systemImage: "lock.fill")
                if !viewModel.accountEmail.isEmpty {
                    Text(viewModel.accountEmail)
                        .foregroundStyle(.secondary)
                }
                Text(expiryText())
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Replace token") {
                    viewModel.showTokenSheet()
                }
                Button("Remove token", role: .destructive) {
                    viewModel.removeToken()
                }
            } else {
                Text("Sign in at jwt.comma.ai with the account your device is paired to, copy the token and paste it here.")
                    .font(.subheadline)
                Button("Add token") {
                    viewModel.showTokenSheet()
                }
                if let url = URL(string: CommaEndpoints.tokenPageUrl) {
                    Link("Open jwt.comma.ai", destination: url)
                }
            }
        }
    }

    private func expiryText() -> String {
        guard let expiry = viewModel.tokenExpirySeconds else {
            return "Expiry not readable from the token."
        }
        if TimeInterval(expiry) < Date().timeIntervalSince1970 {
            return "Expired on " + Formatting.date(epochSeconds: expiry) + ". Generate a new token."
        }
        return "Expires " + Formatting.date(epochSeconds: expiry)
    }

    private func devicesSection() -> some View {
        Section {
            if viewModel.devices.isEmpty {
                Text("No devices. Refresh after adding a token, or add one by dongle ID.")
                    .foregroundStyle(.secondary)
            }
            ForEach(viewModel.devices) { device in
                DeviceRow(device: device, selected: device.dongleId == viewModel.selectedDongleId) {
                    Task {
                        await viewModel.selectDevice(device.dongleId)
                    }
                }
                .swipeActions {
                    if device.addedManually {
                        Button(role: .destructive) {
                            Task {
                                await viewModel.removeDevice(device.dongleId)
                            }
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                }
            }
        } header: {
            Text("Devices")
        } footer: {
            if !viewModel.devicesMessage.isEmpty {
                Text(viewModel.devicesMessage)
            }
        }
    }

    private func mapboxSection() -> some View {
        Section {
            if viewModel.hasMapboxToken {
                Label("Mapbox token stored in the iOS Keychain", systemImage: "lock.fill")
                Button("Replace Mapbox token") {
                    viewModel.showMapboxSheet()
                }
                Button("Remove Mapbox token", role: .destructive) {
                    viewModel.removeMapboxToken()
                }
            } else {
                Text("Optional: with your own free Mapbox account the Send tab shows the routes on a map, to pick one and add stops.")
                    .font(.subheadline)
                Button("Set up Mapbox") {
                    viewModel.showMapboxSheet()
                }
            }
        } header: {
            Text("Route map (Mapbox)")
        }
    }

    private func backendsSection() -> some View {
        Section("Backends") {
            VStack(alignment: .leading, spacing: 6) {
                Text("comma athena: available")
                    .font(.subheadline.weight(.semibold))
                Text("Sends setNavDestination / clearNavDestination to the device.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("sunnylink: not available")
                    .font(.subheadline.weight(.semibold))
                Text(SunnylinkTransport.reason)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct DeviceRow: View {
    let device: PairedDevice
    let selected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                } else {
                    Image(systemName: "circle")
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.displayName())
                        .foregroundStyle(.primary)
                    Text(device.dongleId)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Text(details())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func details() -> String {
        var text = ""
        if !device.deviceType.isEmpty {
            text = "comma " + device.deviceType + " · "
        }
        if device.addedManually {
            text += "added by hand"
        } else {
            text += Formatting.lastSeen(epochSeconds: device.lastAthenaPingSeconds)
        }
        if !device.isOwner {
            text += " · read-only access"
        }
        return text
    }
}

private struct TokenSheet: View {
    let viewModel: MainViewModel
    @State private var token = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("JWT", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    PasteButton(payloadType: String.self) { strings in
                        guard let text = strings.first else {
                            return
                        }
                        Task { @MainActor in
                            token = text
                        }
                    }
                    .labelStyle(.titleAndIcon)
                } footer: {
                    Text("The token is checked with the comma API, then stored in the Keychain of this iPhone only.")
                }
                if !viewModel.accountMessage.isEmpty {
                    Section {
                        Text(viewModel.accountMessage)
                            .foregroundStyle(.red)
                    }
                }
                Section {
                    if let url = URL(string: CommaEndpoints.tokenPageUrl) {
                        Link("Open jwt.comma.ai", destination: url)
                    }
                }
            }
            .navigationTitle("comma token")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.hideTokenSheet()
                    }
                    .disabled(viewModel.accountBusy)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.accountBusy {
                        ProgressView()
                    } else {
                        Button("Verify and save") {
                            Task {
                                await viewModel.saveToken(token)
                            }
                        }
                        .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .interactiveDismissDisabled(viewModel.accountBusy)
        }
    }
}

private struct AddDeviceSheet: View {
    let viewModel: MainViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var dongleId = ""
    @State private var alias = ""
    @State private var error = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Dongle ID (16 hex characters)", text: $dongleId)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                    TextField("Name (optional)", text: $alias)
                } footer: {
                    Text("Backend: comma athena. The dongle ID is in the device settings.")
                }
                if !error.isEmpty {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Add device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        Task {
                            let result = await viewModel.addManualDevice(dongleIdText: dongleId, alias: alias)
                            if result.isEmpty {
                                dismiss()
                            } else {
                                error = result
                            }
                        }
                    }
                }
            }
        }
    }
}
