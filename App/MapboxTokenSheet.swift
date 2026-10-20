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
                    Text("The token is checked with Mapbox, then stored in the Keychain of this iPhone and sent to your comma device, which asks Mapbox for its routes with it.")
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
