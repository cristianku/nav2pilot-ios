import Nav2PilotKit
import SwiftUI

struct SendView: View {
    let viewModel: MainViewModel
    let openDevices: () -> Void
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                searchSection()
                if !viewModel.choices.isEmpty {
                    ChoicesSection(viewModel: viewModel)
                }
                DestinationSection(viewModel: viewModel)
                RouteSection(viewModel: viewModel)
                DeviceSection(viewModel: viewModel, onOpenDevices: openDevices)
                SendActionsSection(viewModel: viewModel)
            }
            .navigationTitle("Nav2Pilot")
        }
    }

    private func searchSection() -> some View {
        Section {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Address, lat, lng or map link", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($searchFocused)
                    .onSubmit {
                        runSearch(query)
                    }
                if viewModel.resolving {
                    ProgressView()
                } else if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Clear search")
                    }
                    .buttonStyle(.borderless)
                }
            }
            HStack {
                Button("Search") {
                    runSearch(query)
                }
                .buttonStyle(.borderless)
                .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.resolving)
                Spacer()
                // PasteButton reads the clipboard only when tapped, without the iOS paste permission prompt.
                PasteButton(payloadType: String.self) { strings in
                    guard let text = strings.first else {
                        return
                    }
                    Task { @MainActor in
                        query = text
                        runSearch(text)
                    }
                }
                .labelStyle(.titleAndIcon)
                .buttonBorderShape(.capsule)
                .disabled(viewModel.resolving)
            }
            if !viewModel.resolveError.isEmpty {
                Text(viewModel.resolveError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private func runSearch(_ text: String) {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return
        }
        searchFocused = false
        Task {
            await viewModel.search(text)
        }
    }
}
