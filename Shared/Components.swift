import Nav2PilotKit
import SwiftUI

// Views used by both the app and the share extension.

enum Formatting {
    static func time(_ date: Date) -> String {
        return date.formatted(date: .omitted, time: .shortened)
    }

    static func date(epochSeconds: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(epochSeconds))
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    static func lastSeen(epochSeconds: Int64) -> String {
        if epochSeconds <= 0 {
            return "never seen by athena"
        }
        let date = Date(timeIntervalSince1970: TimeInterval(epochSeconds))
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return "athena ping " + formatter.localizedString(for: date, relativeTo: Date())
    }
}

/// Links that open the destination in a map app, so the pin can be checked before sending it.
enum MapLinks {
    /// Apple Map Links: ll is the pin and q its label (maps.apple.com turns it into /place?coordinate=&name=).
    static func appleMaps(_ destination: Destination) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "maps.apple.com"
        components.path = "/"
        components.queryItems = [
            URLQueryItem(name: "ll", value: coordinatePair(destination)),
            URLQueryItem(name: "q", value: destination.displayName()),
        ]
        return components.url
    }

    /// Google Maps URLs API: https://developers.google.com/maps/documentation/urls/get-started
    static func googleMaps(_ destination: Destination) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.google.com"
        components.path = "/maps/search/"
        components.queryItems = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "query", value: coordinatePair(destination)),
        ]
        return components.url
    }

    private static func coordinatePair(_ destination: Destination) -> String {
        return String(format: "%.6f,%.6f", locale: Locale(identifier: "en_US_POSIX"), destination.latitude, destination.longitude)
    }
}

struct ChoicesSection: View {
    let viewModel: MainViewModel

    var body: some View {
        Section("Choose a result") {
            ForEach(0..<viewModel.choices.count, id: \.self) { index in
                let choice = viewModel.choices[index]
                Button {
                    viewModel.chooseCandidate(choice)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(choice.displayName())
                            .foregroundStyle(.primary)
                        Text(secondLine(choice))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func secondLine(_ choice: Destination) -> String {
        if choice.details.isEmpty {
            return choice.coordinatesText()
        }
        return choice.details + " · " + choice.coordinatesText()
    }
}

struct DestinationSection: View {
    let viewModel: MainViewModel
    var showsMapLinks = true
    var allowsClear = true

    var body: some View {
        Section("Destination") {
            if let destination = viewModel.destination {
                details(destination)
                if showsMapLinks {
                    mapLinks(destination)
                }
            } else {
                Label("No destination yet. Share a place from Google Maps or Apple Maps, or search above.", systemImage: "mappin.and.ellipse")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func details(_ destination: Destination) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(destination.displayName())
                    .font(.title3.weight(.semibold))
                Spacer(minLength: 0)
                Button {
                    viewModel.toggleFavorite()
                } label: {
                    if viewModel.isFavorite(destination) {
                        Image(systemName: "heart.fill")
                            .accessibilityLabel("Remove from favorites")
                    } else {
                        Image(systemName: "heart")
                            .accessibilityLabel("Add to favorites")
                    }
                }
                .buttonStyle(.borderless)
                if allowsClear {
                    Button {
                        viewModel.clearSelection()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Clear destination")
                    }
                    .buttonStyle(.borderless)
                }
            }
            if !destination.details.isEmpty {
                Text(destination.details)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            // without a name the title already shows the coordinates
            if destination.displayName() != destination.coordinatesText() {
                Text(destination.coordinatesText())
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
            }
            if !viewModel.destinationSource.isEmpty {
                Text("From: " + viewModel.destinationSource)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if destination.approximate {
                Label("Approximate: the link only had the map centre. Check it on the map.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func mapLinks(_ destination: Destination) -> some View {
        if let appleUrl = MapLinks.appleMaps(destination) {
            Link(destination: appleUrl) {
                Label("Show in Apple Maps", systemImage: "map")
            }
        }
        if let googleUrl = MapLinks.googleMaps(destination) {
            Link(destination: googleUrl) {
                Label("Show in Google Maps", systemImage: "globe")
            }
        }
    }
}

struct DeviceSection: View {
    let viewModel: MainViewModel
    /// Shown when there is no token or no device; nil in the share extension.
    var onOpenDevices: (() -> Void)?

    var body: some View {
        Section("Device") {
            if !viewModel.hasToken || viewModel.devices.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(hint())
                        .foregroundStyle(.secondary)
                    if let openDevices = onOpenDevices {
                        Button("Open Devices", action: openDevices)
                            .buttonStyle(.bordered)
                    }
                }
                .padding(.vertical, 2)
            }
            if !viewModel.devices.isEmpty {
                Picker("Send to", selection: selectionBinding()) {
                    ForEach(viewModel.devices) { device in
                        Text(device.displayName()).tag(device.dongleId)
                    }
                }
                HStack {
                    ConnectionIndicator(connection: viewModel.connection)
                    Spacer(minLength: 8)
                    Button {
                        Task {
                            await viewModel.checkConnection()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .accessibilityLabel("Check connection")
                    }
                    .buttonStyle(.borderless)
                    .disabled(viewModel.connection == .checking)
                }
            }
        }
    }

    private func hint() -> String {
        if !viewModel.hasToken {
            if onOpenDevices == nil {
                return "Open Nav2Pilot and add your comma token in Devices first."
            }
            return "Add your comma token to list your devices."
        }
        return "No devices yet."
    }

    private func selectionBinding() -> Binding<String> {
        return Binding(
            get: {
                return viewModel.selectedDongleId
            },
            set: { dongleId in
                Task {
                    await viewModel.selectDevice(dongleId)
                }
            }
        )
    }
}

struct ConnectionIndicator: View {
    let connection: ConnectionState

    var body: some View {
        HStack(spacing: 8) {
            if connection == .checking {
                ProgressView()
                    .controlSize(.small)
            } else {
                Circle()
                    .fill(dotColor())
                    .frame(width: 10, height: 10)
            }
            Text(text())
                .font(.subheadline)
        }
    }

    private func dotColor() -> Color {
        switch connection {
        case .online:
            return .green
        case .unreachable:
            return .red
        case .checking, .unknown:
            return .secondary
        }
    }

    private func text() -> String {
        switch connection {
        case .online(let status):
            var description = "Online"
            if !status.version.isEmpty {
                description += " · " + status.version
            }
            if !status.branch.isEmpty {
                description += " (" + status.branch + ")"
            }
            return description
        case .checking:
            return "Checking connection…"
        case .unreachable(let message):
            return message
        case .unknown:
            return "Connection not checked"
        }
    }
}

struct SendActionsSection: View {
    let viewModel: MainViewModel
    var showsClearOnDevice = true

    var body: some View {
        Section {
            Button {
                Task {
                    await viewModel.sendDestination()
                }
            } label: {
                HStack(spacing: 8) {
                    if viewModel.sending {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "paperplane.fill")
                    }
                    Text(sendLabel())
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canSend())
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            // right under the button, so the result is visible without scrolling
            if let feedback = viewModel.feedback {
                FeedbackRow(feedback: feedback)
            }

            if showsClearOnDevice {
                Button("Clear destination on device") {
                    Task {
                        await viewModel.clearDestinationOnDevice()
                    }
                }
                .disabled(viewModel.selectedDevice() == nil || viewModel.sending)
            }
        } footer: {
            Text("The device must be online. It keeps the destination until the car goes offroad or the device restarts.")
        }
    }

    private func sendLabel() -> String {
        if let device = viewModel.selectedDevice() {
            return "Send to " + device.displayName()
        }
        return "Send destination"
    }

    private func canSend() -> Bool {
        return viewModel.destination != nil && viewModel.selectedDevice() != nil && !viewModel.sending
    }
}

struct FeedbackRow: View {
    let feedback: SendFeedback

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if feedback.success {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Image(systemName: "exclamationmark.octagon.fill")
                    .foregroundStyle(.red)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(feedback.message)
                Text(Formatting.time(feedback.time))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
    }
}
