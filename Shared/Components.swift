import Nav2PilotKit
import SwiftUI
import UIKit

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

// MARK: - Theme

extension UIColor {
    convenience init(hex: UInt32) {
        let red = CGFloat((hex >> 16) & 0xFF) / 255
        let green = CGFloat((hex >> 8) & 0xFF) / 255
        let blue = CGFloat(hex & 0xFF) / 255
        self.init(red: red, green: green, blue: blue, alpha: 1)
    }
}

extension Color {
    /// A colour that follows the light / dark appearance.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            if traits.userInterfaceStyle == .dark {
                return UIColor(hex: dark)
            }
            return UIColor(hex: light)
        })
    }
}

/// Colours shared with the Android app: the logo's night blue and cyan. The cyan is also the AccentColor asset.
enum Theme {
    static let background = Color(light: 0xF3F6FA, dark: 0x010E30)
    static let card = Color(light: 0xFFFFFF, dark: 0x0A1A44)
    static let cardBorder = Color(light: 0xDCE2EB, dark: 0x22336A)
    static let mutedFill = Color(light: 0xEAF0F6, dark: 0x13275C)
    /// cyan of the road markings in the logo: dark enough for text on white, bright on the dark surfaces
    static let brand = Color(light: 0x007C96, dark: 0x00D5E8)
    static let brandSoft = Color(light: 0xD2F3F8, dark: 0x00475A)
    static let accentSoft = Color(light: 0xD2F3F8, dark: 0x00475A)
    /// text on the cyan accent: white on the dark cyan of the light theme, night blue on the bright cyan
    static let onAccent = Color(light: 0xFFFFFF, dark: 0x010E30)
    /// background of secondary system buttons that only take a tint (PasteButton)
    static let neutralAction = Color(light: 0x556477, dark: 0x3A4A62)
    // status colours stay apart from the brand and always come with an icon and a text
    static let success = Color(light: 0x1E7D3A, dark: 0x6FD38A)
    static let warning = Color(light: 0x8A5300, dark: 0xF2B45C)
    static let error = Color(light: 0xB3261E, dark: 0xF2B8B5)

    static let screenPadding: CGFloat = 20
    static let cardRadius: CGFloat = 18
}

private struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(Theme.cardBorder, lineWidth: 1)
            )
    }
}

extension View {
    /// White (dark: navy) card with a thin border.
    func cardStyle() -> some View {
        return modifier(CardBackground())
    }
}

/// The logo artwork on its own navy square, also in the light theme.
struct BrandLogo: View {
    let size: CGFloat

    var body: some View {
        Image("BrandLogo")
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Logo and name: the header of the Send screen.
struct BrandHeader: View {
    var logoSize: CGFloat = 38
    var titleFont: Font = .title2.weight(.bold)

    var body: some View {
        HStack(spacing: logoSize * 0.3) {
            BrandLogo(size: logoSize)
            Text("Nav2Pilot")
                .font(titleFont)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Small uppercase label above a card.
struct SectionLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.uppercased())
            .font(.footnote.weight(.medium))
            .kerning(0.6)
            .foregroundStyle(.secondary)
            .padding(.leading, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

/// SF Symbol on a round tinted background, at the start of a card row.
struct IconBadge: View {
    let systemName: String
    let tint: Color
    let background: Color
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(background, in: Circle())
            .accessibilityHidden(true)
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

// MARK: - Destination

struct ChoicesCard: View {
    let viewModel: MainViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("Choose a result")
            VStack(spacing: 0) {
                ForEach(0..<viewModel.choices.count, id: \.self) { index in
                    let choice = viewModel.choices[index]
                    if index > 0 {
                        Divider()
                            .padding(.leading, 68)
                    }
                    Button {
                        viewModel.chooseCandidate(choice)
                    } label: {
                        HStack(spacing: 16) {
                            IconBadge(systemName: "mappin", tint: Theme.brand, background: Theme.brandSoft, size: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(choice.displayName())
                                    .foregroundStyle(.primary)
                                let second = secondLine(choice)
                                if !second.isEmpty {
                                    Text(second)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .cardStyle()
        }
    }

    /// The coordinates only when nothing else tells the places apart.
    private func secondLine(_ choice: Destination) -> String {
        if !choice.details.isEmpty {
            return choice.details
        }
        if choice.displayName() != choice.coordinatesText() {
            return choice.coordinatesText()
        }
        return ""
    }
}

struct DestinationCard: View {
    let viewModel: MainViewModel
    var showsMapLinks = true
    var allowsClear = true
    @State private var detailsVisible = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("Destination")
            Group {
                if let destination = viewModel.destination {
                    details(destination)
                } else {
                    empty()
                }
            }
            .cardStyle()
        }
        // a new destination starts with the details folded
        .onChange(of: viewModel.destination) {
            detailsVisible = false
        }
    }

    private func empty() -> some View {
        HStack(spacing: 16) {
            IconBadge(systemName: "mappin.and.ellipse", tint: .secondary, background: Theme.mutedFill)
            VStack(alignment: .leading, spacing: 2) {
                Text("No destination yet")
                    .font(.subheadline.weight(.semibold))
                Text("Search above, or share a place from Google Maps or Apple Maps.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
    }

    private func details(_ destination: Destination) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 0) {
                IconBadge(systemName: "mappin", tint: Theme.brand, background: Theme.brandSoft)
                    .padding(.trailing, 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(destination.displayName())
                        .font(.title3.weight(.semibold))
                        .textSelection(.enabled)
                    if !destination.details.isEmpty {
                        Text(destination.details)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 2)
                Spacer(minLength: 4)
                favoriteButton(destination)
                if allowsClear {
                    Button {
                        viewModel.clearSelection()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .frame(width: 40, height: 44)
                            .accessibilityLabel("Clear destination")
                    }
                    .buttonStyle(.borderless)
                    .padding(.top, -6)
                }
            }

            // needed to decide whether to send it, so never folded away
            if destination.approximate {
                Label("Approximate: the link only had the map centre. Check it on the map.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.warning)
                    .padding(.leading, 56)
            }

            if detailsVisible {
                VStack(alignment: .leading, spacing: 2) {
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
                }
                .padding(.leading, 56)
            }

            HStack {
                if showsMapLinks {
                    mapMenu(destination)
                }
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        detailsVisible.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        if detailsVisible {
                            Text("Hide details")
                            Image(systemName: "chevron.up")
                        } else {
                            Text("Details")
                            Image(systemName: "chevron.down")
                        }
                    }
                    .font(.subheadline)
                }
                .buttonStyle(.borderless)
            }
            .padding(.leading, 56)
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .padding(.vertical, 14)
    }

    private func favoriteButton(_ destination: Destination) -> some View {
        Button {
            viewModel.toggleFavorite()
        } label: {
            if viewModel.isFavorite(destination) {
                Image(systemName: "heart.fill")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 40, height: 44)
                    .accessibilityLabel("Remove from favorites")
            } else {
                Image(systemName: "heart")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 40, height: 44)
                    .accessibilityLabel("Add to favorites")
            }
        }
        .buttonStyle(.borderless)
        .padding(.top, -6)
    }

    /// One "Open in Maps" action instead of a row per map app.
    private func mapMenu(_ destination: Destination) -> some View {
        Menu {
            if let appleUrl = MapLinks.appleMaps(destination) {
                Link(destination: appleUrl) {
                    Label("Apple Maps", systemImage: "map")
                }
            }
            if let googleUrl = MapLinks.googleMaps(destination) {
                Link(destination: googleUrl) {
                    Label("Google Maps", systemImage: "globe")
                }
            }
        } label: {
            Label("Open in Maps", systemImage: "map")
                .font(.subheadline)
        }
    }
}

// MARK: - Device

/// The name shown for a car: its alias, otherwise its type. Never the bare dongle ID.
enum CarName {
    static func of(_ device: PairedDevice) -> String {
        if !device.alias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return device.alias
        }
        if !device.deviceType.isEmpty {
            return "comma " + device.deviceType
        }
        return "comma device"
    }
}

struct DeviceCard: View {
    let viewModel: MainViewModel
    /// Shown when there is no token or no device; nil in the share extension.
    var onOpenDevices: (() -> Void)?
    var showsClearOnDevice = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("Device")
            Group {
                if viewModel.devices.isEmpty {
                    missing()
                } else {
                    picker()
                }
            }
            .cardStyle()
        }
    }

    private func missing() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                IconBadge(systemName: "car.fill", tint: .secondary, background: Theme.mutedFill)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title())
                        .font(.subheadline.weight(.semibold))
                    Text(hint())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            if let openDevices = onOpenDevices {
                Button("Open Devices", action: openDevices)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.roundedRectangle(radius: 12))
                    .padding(.leading, 56)
            }
        }
        .padding(16)
    }

    private func picker() -> some View {
        HStack(spacing: 4) {
            Menu {
                ForEach(viewModel.devices) { device in
                    Button {
                        Task {
                            await viewModel.selectDevice(device.dongleId)
                        }
                    } label: {
                        if device.dongleId == viewModel.selectedDongleId {
                            Label(CarName.of(device), systemImage: "checkmark")
                        } else {
                            Text(CarName.of(device))
                        }
                    }
                }
            } label: {
                HStack(spacing: 16) {
                    IconBadge(systemName: "car.fill", tint: Color.accentColor, background: Theme.accentSoft)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(deviceName())
                                .font(.body.weight(.semibold))
                                .lineLimit(1)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        if viewModel.selectedDevice() != nil {
                            ConnectionIndicator(connection: viewModel.connection)
                        }
                    }
                    .foregroundStyle(.primary)
                    Spacer(minLength: 0)
                }
                .padding(.leading, 16)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Send to " + deviceName())
            .accessibilityHint("Choose the device")

            if viewModel.connection == .checking {
                ProgressView()
                    .frame(width: 44, height: 44)
            } else {
                Button {
                    Task {
                        await viewModel.checkConnection()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 44, height: 44)
                        .accessibilityLabel("Check connection")
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.selectedDevice() == nil)
            }

            if showsClearOnDevice {
                Menu {
                    Button("Clear destination on device", role: .destructive) {
                        Task {
                            await viewModel.clearDestinationOnDevice()
                        }
                    }
                    .disabled(viewModel.selectedDevice() == nil || viewModel.sending)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .frame(width: 44, height: 44)
                        .accessibilityLabel("More device actions")
                }
            }
        }
        .padding(.trailing, 8)
    }

    private func deviceName() -> String {
        if let device = viewModel.selectedDevice() {
            return CarName.of(device)
        }
        return "Select a device"
    }

    private func title() -> String {
        if !viewModel.hasToken {
            return "Connect your comma account"
        }
        return "No devices yet"
    }

    private func hint() -> String {
        if !viewModel.hasToken {
            if onOpenDevices == nil {
                return "Open Nav2Pilot and add your comma token in Devices first."
            }
            return "Add your comma token to list your devices."
        }
        return "Refresh the list in Devices."
    }
}

/// The state of the last check only: an old ping is no proof the device is reachable now.
struct ConnectionIndicator: View {
    let connection: ConnectionState

    var body: some View {
        HStack(spacing: 6) {
            if connection == .checking {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Circle()
                    .fill(dotColor())
                    .frame(width: 8, height: 8)
            }
            Text(text())
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private func dotColor() -> Color {
        switch connection {
        case .online:
            return Theme.success
        case .unreachable:
            return Theme.error
        case .checking, .unknown:
            return .secondary
        }
    }

    private func text() -> String {
        switch connection {
        case .online:
            return "Online"
        case .checking:
            return "Checking connection…"
        case .unreachable(let message):
            return message
        case .unknown:
            return "Connection not checked"
        }
    }
}

// MARK: - Send

/// The send button and its result, kept above the tab bar while the content scrolls.
struct SendBar: View {
    let viewModel: MainViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                Task {
                    await viewModel.sendDestination()
                }
            } label: {
                HStack(spacing: 10) {
                    if viewModel.sending {
                        ProgressView()
                    } else {
                        Image(systemName: "paperplane.fill")
                    }
                    Text(sendLabel())
                        .fontWeight(.semibold)
                        .lineLimit(1)
                }
                .foregroundStyle(canSend() ? Theme.onAccent : Color.secondary)
                .frame(maxWidth: .infinity, minHeight: 34)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 14))
            .controlSize(.large)
            .disabled(!canSend())

            // right under the button, so the result is visible without scrolling
            if let feedback = viewModel.feedback {
                FeedbackRow(feedback: feedback)
                    .padding(.horizontal, 4)
            } else if !missing().isEmpty {
                Text(missing())
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        }
        .padding(.horizontal, Theme.screenPadding)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(Theme.background)
        .overlay(alignment: .top) {
            // in its own VStack: a bare Divider takes the axis of the nearest stack, and in the landscape layout
            // that is the HStack of the two panes, which turned it into a vertical line across the button
            VStack(spacing: 0) {
                Divider()
            }
        }
    }

    private func sendLabel() -> String {
        // with a route picked on the map the device gets that route, not only the destination
        if viewModel.routePlanningAvailable && viewModel.hasMapboxToken && !viewModel.routes.isEmpty {
            return "Send route to comma"
        }
        return "Send to comma"
    }

    private func canSend() -> Bool {
        return viewModel.destination != nil && viewModel.selectedDevice() != nil && !viewModel.sending
    }

    /// What is missing, next to the button that needs it.
    private func missing() -> String {
        if canSend() || viewModel.sending {
            return ""
        }
        if !viewModel.hasToken && viewModel.devices.isEmpty {
            return "Connect your comma account in Devices to send."
        }
        if viewModel.selectedDevice() == nil {
            return "Select a device to send to."
        }
        if viewModel.destination == nil {
            return "Search or share a place to send it."
        }
        return ""
    }
}

struct FeedbackRow: View {
    let feedback: SendFeedback

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if feedback.success {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.success)
            } else {
                Image(systemName: "exclamationmark.octagon.fill")
                    .foregroundStyle(Theme.error)
            }
            Text(feedback.message + " · " + Formatting.time(feedback.time))
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }
}
