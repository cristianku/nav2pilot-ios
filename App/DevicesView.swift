import Nav2PilotKit
import SwiftUI

struct DevicesView: View {
    @Bindable var viewModel: MainViewModel
    @State private var connectionDetailsExpanded = false
    @State private var deviceToRemove: PairedDevice?

    var body: some View {
        NavigationStack {
            Form {
                // connected: the car comes first; otherwise the account is the next step
                if viewModel.hasToken {
                    carSection()
                    accountSection()
                } else {
                    accountSection()
                    carSection()
                }
                mapboxSection()
                connectionSection()
                aboutSection()
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Devices")
            .sheet(isPresented: $viewModel.tokenSheetVisible) {
                TokenSheet(viewModel: viewModel)
            }
            .confirmationDialog(removeTitle(), isPresented: removeDialogBinding(), titleVisibility: .visible) {
                Button("Remove", role: .destructive) {
                    if let device = deviceToRemove {
                        Task {
                            await viewModel.removeDevice(device.dongleId)
                        }
                    }
                    deviceToRemove = nil
                }
                Button("Cancel", role: .cancel) {
                    deviceToRemove = nil
                }
            } message: {
                Text(removeMessage())
            }
        }
    }

    // MARK: - Car

    private func carSection() -> some View {
        Section {
            if viewModel.devices.isEmpty {
                emptyCar()
            }
            ForEach(viewModel.devices) { device in
                let selected = device.dongleId == viewModel.selectedDongleId
                HStack(spacing: 4) {
                    DeviceRow(
                        device: device,
                        selected: selected,
                        // nothing to choose with a single car
                        showsSelection: viewModel.devices.count > 1
                    ) {
                        Task {
                            await viewModel.selectDevice(device.dongleId)
                        }
                    }
                    Spacer(minLength: 0)
                    deviceMenu(device)
                }
            }
        } header: {
            if viewModel.devices.count > 1 {
                Text("Your cars")
            } else {
                Text("Your car")
            }
        } footer: {
            if !viewModel.devicesMessage.isEmpty {
                Text(viewModel.devicesMessage)
            }
        }
        .listRowBackground(Theme.card)
    }

    @ViewBuilder
    private func emptyCar() -> some View {
        HStack(spacing: 14) {
            IconBadge(systemName: "car.fill", tint: .secondary, background: Theme.mutedFill)
            if viewModel.hasToken {
                Text("No car on this comma account yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Connect your comma account above to see your car.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        if viewModel.hasToken {
            refreshButton()
        }
    }

    private func refreshButton() -> some View {
        Button {
            Task {
                await viewModel.refreshDevices()
            }
        } label: {
            HStack {
                Label("Refresh from comma account", systemImage: "arrow.clockwise")
                if viewModel.refreshingDevices {
                    Spacer()
                    ProgressView()
                }
            }
        }
        .disabled(viewModel.refreshingDevices)
    }

    private func deviceMenu(_ device: PairedDevice) -> some View {
        Menu {
            Button {
                Task {
                    await viewModel.refreshDevices()
                }
            } label: {
                Label("Refresh from comma account", systemImage: "arrow.clockwise")
            }
            .disabled(!viewModel.hasToken || viewModel.refreshingDevices)
            Button(role: .destructive) {
                deviceToRemove = device
            } label: {
                Label("Remove car", systemImage: "trash")
            }
        } label: {
            if viewModel.refreshingDevices {
                ProgressView()
                    .frame(width: 44, height: 44)
            } else {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .accessibilityLabel("Actions for " + CarName.of(device))
            }
        }
    }

    private func removeDialogBinding() -> Binding<Bool> {
        return Binding(
            get: {
                return deviceToRemove != nil
            },
            set: { visible in
                if !visible {
                    deviceToRemove = nil
                }
            }
        )
    }

    private func removeTitle() -> String {
        if let device = deviceToRemove {
            return "Remove " + CarName.of(device) + "?"
        }
        return "Remove car?"
    }

    private func removeMessage() -> String {
        if let device = deviceToRemove, device.addedManually {
            return "It was added by hand, so it does not come back from the comma account."
        }
        return "It comes back with Refresh from comma account."
    }

    // MARK: - Account

    private func accountSection() -> some View {
        Section {
            if viewModel.hasToken {
                HStack(alignment: .center, spacing: 12) {
                    accountStatus()
                    Spacer(minLength: 8)
                    Menu("Manage") {
                        Button("Replace token") {
                            viewModel.showTokenSheet()
                        }
                        Button("Remove token", role: .destructive) {
                            viewModel.removeToken()
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Connect your comma account")
                        .font(.subheadline.weight(.semibold))
                    Text("Sign in at jwt.comma.ai with the account your device is paired to, copy the token and paste it here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
                Button("Add token") {
                    viewModel.showTokenSheet()
                }
                if let url = URL(string: CommaEndpoints.tokenPageUrl) {
                    Link("Open jwt.comma.ai", destination: url)
                }
            }
        } header: {
            Text("comma account")
        } footer: {
            if viewModel.hasToken {
                Text("Stored in the iOS Keychain of this iPhone only.")
            }
        }
        .listRowBackground(Theme.card)
    }

    /// "Saved", not "connected": the token is only checked when it is added.
    private func accountStatus() -> some View {
        HStack(alignment: .top, spacing: 12) {
            if tokenExpired() {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.warning)
            } else {
                Image(systemName: "lock.fill")
                    .foregroundStyle(Theme.success)
            }
            VStack(alignment: .leading, spacing: 2) {
                if tokenExpired() {
                    Text("Access needs renewal")
                } else {
                    Text("Credentials saved")
                }
                if !viewModel.accountEmail.isEmpty {
                    Text(viewModel.accountEmail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Text(expiryText())
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func tokenExpired() -> Bool {
        guard let expiry = viewModel.tokenExpirySeconds else {
            return false
        }
        return TimeInterval(expiry) < Date().timeIntervalSince1970
    }

    private func expiryText() -> String {
        guard let expiry = viewModel.tokenExpirySeconds else {
            return "Expiry not readable from the token."
        }
        if tokenExpired() {
            return "Expired on " + Formatting.date(epochSeconds: expiry) + ". Generate a new token."
        }
        return "Expires " + Formatting.date(epochSeconds: expiry)
    }

    // MARK: - Mapbox

    private func mapboxSection() -> some View {
        Section {
            if viewModel.hasMapboxToken {
                Label {
                    Text("Mapbox token saved")
                } icon: {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(Theme.success)
                }
                Button("Replace Mapbox token") {
                    viewModel.showMapboxSheet()
                }
                Button("Remove Mapbox token", role: .destructive) {
                    Task {
                        await viewModel.removeMapboxToken()
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mapbox routes (optional)")
                        .font(.subheadline.weight(.semibold))
                    Text("With your own free Mapbox account the car computes its routes with Mapbox instead of comma's route service, and the Send tab shows the routes on a map, to pick one and add stops.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
                Button("Set up Mapbox") {
                    viewModel.showMapboxSheet()
                }
            }
        } header: {
            Text("Maps and routes")
        } footer: {
            if viewModel.hasMapboxToken {
                Text("Stored in the iOS Keychain. Your car gets the token automatically with every destination you send. Removing it here also removes it from the selected car.")
            }
        }
        .listRowBackground(Theme.card)
    }

    // MARK: - Connection and about

    /// How the app reaches the car, folded: not needed day to day.
    private func connectionSection() -> some View {
        Section {
            DisclosureGroup("Connection details", isExpanded: $connectionDetailsExpanded) {
                // the technical identity of the selected car, kept out of the day-to-day view
                if let device = viewModel.selectedDevice() {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(CarName.of(device))
                            .font(.subheadline.weight(.semibold))
                        Text("Dongle ID " + device.dongleId)
                            .font(.footnote.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        if case .online(let status) = viewModel.connection {
                            Text(software(status))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("comma athena: available")
                        .font(.subheadline.weight(.semibold))
                    Text("Sends setNavDestination / clearNavDestination to the device.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("sunnylink: not available")
                        .font(.subheadline.weight(.semibold))
                    Text(SunnylinkTransport.reason)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listRowBackground(Theme.card)
    }

    private func aboutSection() -> some View {
        Section {
            VStack(spacing: 6) {
                BrandLogo(size: 68)
                    .padding(.bottom, 4)
                Text("Nav2Pilot")
                    .font(.headline)
                if !appVersion().isEmpty {
                    Text("Version " + appVersion())
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Text("An independent project, not affiliated with comma.ai or sunnypilot.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .listRowBackground(Color.clear)
            .accessibilityElement(children: .combine)
        }
    }

    private func software(_ status: DeviceStatus) -> String {
        var text = "Software " + status.version
        if !status.branch.isEmpty {
            text += " (" + status.branch + ")"
        }
        return text
    }

    private func appVersion() -> String {
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            return version
        }
        return ""
    }
}

private struct DeviceRow: View {
    let device: PairedDevice
    let selected: Bool
    let showsSelection: Bool
    let onSelect: () -> Void

    var body: some View {
        if showsSelection {
            Button(action: onSelect) {
                content()
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])
        } else {
            content()
        }
    }

    private func content() -> some View {
        HStack(spacing: 14) {
            if showsSelection {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.tint)
                } else {
                    Image(systemName: "circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            } else {
                IconBadge(systemName: "car.fill", tint: Color.accentColor, background: Theme.accentSoft)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(CarName.of(device))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(details())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
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
