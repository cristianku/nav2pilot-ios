import MapboxMaps
import Nav2PilotKit
import SwiftUI

/// Route preview on a Mapbox map: the fastest route and its alternatives, stops added with a long press.
/// What is picked here is what the device follows (sunnypilot setNavRoute).
struct RouteSection: View {
    let viewModel: MainViewModel

    var body: some View {
        if viewModel.routePlanningAvailable && viewModel.destination != nil {
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel("Route")
                if viewModel.hasMapboxToken {
                    plannedRoute()
                        .cardStyle()
                    Text("Long-press the map to add a stop. The device follows the route you pick: through your stops, or through points of the alternative.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.top, 2)
                } else {
                    setup()
                        .cardStyle()
                }
            }
            // the first plan, and a new one for every new destination
            .task(id: viewModel.destination) {
                await viewModel.refreshRoutes()
            }
        }
    }

    /// Optional: a compact prompt, so it does not stand between the destination and the send button.
    private func setup() -> some View {
        HStack(spacing: 16) {
            IconBadge(systemName: "map", tint: Theme.brand, background: Theme.brandSoft)
            VStack(alignment: .leading, spacing: 2) {
                Text("Route preview")
                    .font(.subheadline.weight(.semibold))
                Text("Optional, with a free Mapbox account.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Set up Mapbox") {
                viewModel.showMapboxSheet()
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            .fixedSize()
        }
        .padding(16)
    }

    private func plannedRoute() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let token = viewModel.mapboxAccessToken() {
                RouteMap(viewModel: viewModel, accessToken: token)
                    .frame(height: 280)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: Theme.cardRadius, topTrailingRadius: Theme.cardRadius, style: .continuous))
            }
            if viewModel.routesLoading {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Computing routes…")
                        .foregroundStyle(.secondary)
                }
                .padding(16)
            }
            if !viewModel.routesMessage.isEmpty {
                Label(viewModel.routesMessage, systemImage: "exclamationmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(Theme.error)
                    .padding(16)
            }
            ForEach(0..<viewModel.routes.count, id: \.self) { index in
                if index > 0 {
                    Divider()
                        .padding(.leading, 52)
                }
                RouteRow(
                    route: viewModel.routes[index],
                    index: index,
                    selected: index == viewModel.selectedRouteIndex,
                    onSelect: {
                        viewModel.selectRoute(index)
                    }
                )
            }
            if !viewModel.stops.isEmpty {
                Divider()
                Text("Stops")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
            }
            ForEach(0..<viewModel.stops.count, id: \.self) { index in
                let stop = viewModel.stops[index]
                HStack(spacing: 12) {
                    Image(systemName: "\(index + 1).circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white, .orange)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(stop.name)
                        Text(stop.coordinatesText())
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        Task {
                            await viewModel.removeStop(at: index)
                        }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Theme.error)
                            .frame(width: 44, height: 44)
                            .accessibilityLabel("Remove stop \(index + 1), \(stop.name)")
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.leading, 16)
                .padding(.trailing, 6)
                .padding(.vertical, 2)
            }
        }
    }
}

private struct RouteRow: View {
    let route: RoutePreview
    let index: Int
    let selected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.tint)
                } else {
                    Image(systemName: "circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(RouteFormatting.duration(route.durationSeconds) + " · " + RouteFormatting.distance(route.distanceMeters))
                        .font(selected ? .body.weight(.semibold) : .body)
                        .foregroundStyle(selected ? .primary : .secondary)
                    Text(subtitle())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func subtitle() -> String {
        var text = "Fastest"
        if index > 0 {
            text = "Alternative \(index)"
        }
        if !route.summary.isEmpty {
            text += " · " + route.summary
        }
        return text
    }
}

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

/// The Mapbox map: routes (the picked one on top, in the accent colour), the destination and the stops.
private struct RouteMap: View {
    let viewModel: MainViewModel
    @State private var viewport: Viewport = .idle

    init(viewModel: MainViewModel, accessToken: String) {
        self.viewModel = viewModel
        // the user's own public token, read from the Keychain
        MapboxOptions.accessToken = accessToken
    }

    var body: some View {
        Map(viewport: $viewport) {
            ForEvery(drawOrder(), id: \.self) { index in
                PolylineAnnotation(lineCoordinates: coordinates(viewModel.routes[index].coordinates))
                    .lineColor(StyleColor(lineColor(index)))
                    .lineWidth(index == viewModel.selectedRouteIndex ? 7 : 5)
                    .onTapGesture {
                        viewModel.selectRoute(index)
                    }
            }
            ForEvery(0..<viewModel.stops.count, id: \.self) { index in
                MapViewAnnotation(coordinate: coordinate(viewModel.stops[index])) {
                    Image(systemName: "\(index + 1).circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white, .orange)
                }
            }
            if let destination = viewModel.destination {
                MapViewAnnotation(coordinate: coordinate(destination)) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.title)
                        .foregroundStyle(.white, .red)
                }
            }
            // a long press anywhere on the map adds a stop there
            LongPressInteraction { context in
                Task {
                    await viewModel.addStop(latitude: context.coordinate.latitude, longitude: context.coordinate.longitude)
                }
                return true
            }
        }
        .onAppear {
            fit()
        }
        .onChange(of: viewModel.routes) {
            fit()
        }
    }

    /// Unpicked routes first, so the picked one is drawn on top.
    private func drawOrder() -> [Int] {
        var order: [Int] = []
        for index in 0..<viewModel.routes.count {
            if index != viewModel.selectedRouteIndex {
                order.append(index)
            }
        }
        if viewModel.selectedRouteIndex < viewModel.routes.count {
            order.append(viewModel.selectedRouteIndex)
        }
        return order
    }

    private func lineColor(_ index: Int) -> UIColor {
        if index == viewModel.selectedRouteIndex {
            return UIColor(named: "AccentColor") ?? .systemGreen
        }
        return UIColor.systemGray
    }

    private func fit() {
        var points: [CLLocationCoordinate2D] = []
        for route in viewModel.routes {
            points.append(contentsOf: coordinates(route.coordinates))
        }
        if let destination = viewModel.destination {
            points.append(coordinate(destination))
        }
        if let origin = viewModel.origin {
            points.append(CLLocationCoordinate2D(latitude: origin.latitude, longitude: origin.longitude))
        }
        if points.isEmpty {
            return
        }
        // only the destination (no routes yet): an overview of one point would zoom in to the maximum
        if points.count == 1 {
            viewport = .camera(center: points[0], zoom: 13)
            return
        }
        viewport = .overview(geometry: MultiPoint(points), geometryPadding: EdgeInsets(top: 40, leading: 30, bottom: 40, trailing: 30))
    }

    private func coordinates(_ points: [LatLng]) -> [CLLocationCoordinate2D] {
        var result: [CLLocationCoordinate2D] = []
        for point in points {
            result.append(CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude))
        }
        return result
    }

    private func coordinate(_ destination: Destination) -> CLLocationCoordinate2D {
        return CLLocationCoordinate2D(latitude: destination.latitude, longitude: destination.longitude)
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
