import Nav2PilotKit
import SwiftUI

struct SendView: View {
    let viewModel: MainViewModel
    let openDevices: () -> Void
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    BrandHeader()
                        .padding(.leading, 4)
                    searchSection()
                    if !viewModel.choices.isEmpty {
                        ChoicesCard(viewModel: viewModel)
                    }
                    DestinationCard(viewModel: viewModel)
                    RouteSection(viewModel: viewModel)
                    VStack(alignment: .leading, spacing: 8) {
                        DeviceCard(viewModel: viewModel, onOpenDevices: openDevices)
                        Text("The device must be online. It keeps the destination until the car goes offroad or the device restarts.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.top, 8)
                .padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                SendBar(viewModel: viewModel)
            }
            // the header with the logo replaces the large title
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func searchSection() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Where to?")
                .font(.title3.weight(.semibold))
                .padding(.leading, 4)
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search a place or paste a link", text: $query)
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
                    Button {
                        runSearch(query)
                    } label: {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.title2)
                            .accessibilityLabel("Search")
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 50)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(searchFocused ? Color.accentColor : Theme.cardBorder, lineWidth: searchFocused ? 1.5 : 1)
            )
            HStack(spacing: 10) {
                Text("Address, coordinates (lat, lng) or map link")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
                Spacer(minLength: 0)
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
                .controlSize(.small)
                // secondary to the search: neutral instead of the send blue
                .tint(Theme.neutralAction)
                .disabled(viewModel.resolving)
            }
            if !viewModel.resolveError.isEmpty {
                Label(viewModel.resolveError, systemImage: "exclamationmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(Theme.error)
                    .padding(.horizontal, 4)
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
