import Nav2PilotKit
import SwiftUI

struct SendView: View {
    let viewModel: MainViewModel
    let openDevices: () -> Void
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    // narrower than this, or taller than wide, stays the phone layout
    private static let wideMinWidth: CGFloat = 600
    // the form's share of a wide screen; the map gets the rest
    private static let wideFormFraction: CGFloat = 0.42

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let size = geometry.size
                if size.width >= SendView.wideMinWidth && size.width > size.height {
                    wideLayout(size: size)
                } else {
                    narrowLayout()
                }
            }
            .background(Theme.background)
            // the header with the logo replaces the large title
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    /// Phone held upright: one column, the route between the destination and the device.
    private func narrowLayout() -> some View {
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
                deviceSection()
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SendBar(viewModel: viewModel)
        }
    }

    /// Landscape (car screens, iPad, a phone on its side): the form on the left, the map on the right.
    private func wideLayout(size: CGSize) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ScrollView {
                // no logo header: a landscape screen is short, the tab bar already names the app's sections
                VStack(alignment: .leading, spacing: 20) {
                    searchSection()
                    if !viewModel.choices.isEmpty {
                        ChoicesCard(viewModel: viewModel)
                    }
                    DestinationCard(viewModel: viewModel)
                    deviceSection()
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.top, 8)
                .padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                SendBar(viewModel: viewModel)
            }
            .frame(width: size.width * SendView.wideFormFraction)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if viewModel.routePlanningAvailable && viewModel.destination != nil {
                        // the map fills the visible pane; the route list scrolls below it
                        RouteSection(viewModel: viewModel, mapHeight: max(200, size.height - 60))
                    } else {
                        routePlaceholder()
                    }
                }
                .padding(.trailing, Theme.screenPadding)
                .padding(.top, 8)
                .padding(.bottom, 16)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func routePlaceholder() -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("Route")
            VStack(spacing: 12) {
                IconBadge(systemName: "map", tint: Theme.brand, background: Theme.brandSoft, size: 56)
                Text("No route yet")
                    .font(.headline)
                Text("Search or share a place: its routes show up here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
            .padding(.horizontal, 16)
            .cardStyle()
        }
    }

    private func deviceSection() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            DeviceCard(viewModel: viewModel, onOpenDevices: openDevices)
            Text("The device must be online. It keeps the destination until the car goes offroad or the device restarts.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
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
