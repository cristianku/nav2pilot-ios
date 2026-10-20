import Nav2PilotKit
import SwiftUI

enum RouteFormatting {
    static func duration(_ seconds: Double) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 {
            return "\(max(1, minutes)) min"
        }
        return "\(minutes / 60) h \(String(format: "%02d", minutes % 60)) min"
    }

    static func distance(_ meters: Double) -> String {
        if meters < 1000 {
            return "\(Int(meters.rounded())) m"
        }
        return String(format: "%.1f km", meters / 1000)
    }
}

/// Mapbox setup: each user has their own free account and pastes its default public token.
struct MapboxTokenSheet: View {
    let viewModel: MainViewModel
    @State private var token = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("1. Create a free Mapbox account and confirm the e-mail.")
                        Text("2. Add a payment card in the account: without one Mapbox gives only a trial token with low limits. With a card the free tier applies, enough for personal use.")
                        Text("3. On the Tokens page copy the Default public token (it starts with pk.). Never the secret one (sk.).")
                        Text("4. Paste it here. If you rotate the token on Mapbox later, paste the new one again.")
                    }
                    .font(.subheadline)
                    if let signup = URL(string: MapboxEndpoints.signupUrl) {
                        Link(destination: signup) {
                            Label("Create a free Mapbox account", systemImage: "person.badge.plus")
                        }
                    }
                    if let tokens = URL(string: MapboxEndpoints.tokensPageUrl) {
                        Link(destination: tokens) {
                            Label("Open the Mapbox Tokens page", systemImage: "key")
                        }
                    }
                }
                Section {
                    SecureField("pk.…", text: $token)
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
                    Text("The token is checked with Mapbox and stored in the Keychain of this iPhone. Automatic transfer to the comma needs a compatible build; official builds need manual configuration.")
                }
                Section("Configure Mapbox on the comma") {
                    DisclosureGroup("Keep official openpilot / sunnypilot") {
                        Text("Requires Nav Alpha. Configure the token yourself once:")
                        Text("1. Enable SSH on the comma and add your GitHub SSH key. From a computer on the same network, connect with ssh comma@COMMA_IP.")
                        Text("2. Back up /data/continue.sh, then edit it. Add this line before the command that starts openpilot, replacing the placeholder with your public token. Keep the existing startup commands.")
                        Text("export MAPBOX_TOKEN='pk.REPLACE_WITH_YOUR_PUBLIC_TOKEN'")
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                        Text("3. Save, check with bash -n /data/continue.sh, then reboot the comma while parked. An export in the SSH session alone is not persistent.")
                        Text("Update or remove this line yourself when changing or removing the token. Manual setup enables Mapbox routing; selected alternatives and stops still need a compatible build.")
                        Link("Open the complete manual setup guide", destination: URL(string: "https://github.com/cristianku/nav2pilot-ios#configure-mapbox-on-the-comma")!)
                    }
                    DisclosureGroup("Install a compatible build") {
                        Text("For automatic token transfer and waypoint support, install one of these builds on the comma.")
                        Link("cristianku/openpilot:nav-alpha", destination: URL(string: "https://github.com/cristianku/openpilot/tree/nav-alpha")!)
                        Text("Installer URL: installer.comma.ai/cristianku/nav-alpha")
                            .font(.caption)
                            .textSelection(.enabled)
                        Link("cristianku/openpilot:sunny-nav-alpha (not yet published)", destination: URL(string: "https://github.com/cristianku/openpilot/tree/sunny-nav-alpha")!)
                    }
                }
                if !viewModel.mapboxMessage.isEmpty {
                    Section {
                        Text(viewModel.mapboxMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Mapbox")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.hideMapboxSheet()
                    }
                    .disabled(viewModel.mapboxBusy)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.mapboxBusy {
                        ProgressView()
                    } else {
                        Button("Verify and save") {
                            Task {
                                await viewModel.saveMapboxToken(token)
                            }
                        }
                        .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .interactiveDismissDisabled(viewModel.mapboxBusy)
        }
    }
}
