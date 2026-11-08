import Nav2PilotKit
import SwiftUI

/// The only screen: the map fills it. Search, car, settings, places and favorites float on top; the destination panel comes
/// up from the bottom (phone) or sits in a column on the left (landscape: the driver's side in left-hand-drive cars)
/// once there is a destination.
struct MapScreenView: View {
    @Bindable var viewModel: MainViewModel
    let openSettings: () -> Void
    let openFavorites: () -> Void

    // the search pill: always there without a destination; with one, a tap on the map shows or hides it
    @State private var searchShown = false
    @State private var searchEditing = false
    @State private var query = ""
    @State private var panelSize = CGSize.zero
    @FocusState private var searchFocused: Bool
    // the part of the map in view, where the places are looked for; a box, so a map move does not redraw the screen
    @State private var mapArea = MapAreaBox()
    // a place tapped while there is already a destination: a stop, or the destination instead
    @State private var tappedPlace: Place?
    // "none found" and the errors of the places menu, for a few seconds
    @State private var placesNote = ""

    // narrower than this, or taller than wide, stays the phone layout
    private static let wideMinWidth: CGFloat = 600
    // the landscape panel: this share of the width, between a minimum and a maximum, the rest is map
    private static let widePanelFraction: CGFloat = 0.32
    private static let widePanelMinWidth: CGFloat = 280
    private static let widePanelMaxWidth: CGFloat = 360
    private static let buttonSize: CGFloat = 52
    private static let searchMaxWidth: CGFloat = 520

    var body: some View {
        // read here, in the body, so that SwiftUI redraws the map when any of them changes
        let content = MapContent(
            destination: viewModel.destination,
            stops: viewModel.stops,
            routes: viewModel.routes,
            selectedRouteIndex: viewModel.selectedRouteIndex,
            origin: viewModel.origin,
            recenterRequest: viewModel.recenterRequest,
            places: viewModel.places
        )
        let token = mapboxToken()
        GeometryReader { geometry in
            let wide = geometry.size.width >= MapScreenView.wideMinWidth && geometry.size.width > geometry.size.height
            // the geometry stops at the safe area, so this is the width left by the side system bars
            let panelWidth = MapScreenView.widePanelWidth(availableWidth: geometry.size.width)
            ZStack(alignment: .topLeading) {
                NavMapView(
                    content: content,
                    mapboxToken: token,
                    insets: mapInsets(wide: wide, panelWidth: panelWidth, safeArea: geometry.safeAreaInsets),
                    onTap: {
                        mapTapped()
                    },
                    onLongPress: { latitude, longitude in
                        longPressed(latitude: latitude, longitude: longitude)
                    },
                    onSelectRoute: { index in
                        viewModel.selectRoute(index)
                    },
                    onTapPlace: { index in
                        placeTapped(index)
                    },
                    onAreaChange: { area in
                        mapArea.value = area
                    }
                )
                .ignoresSafeArea()

                if viewModel.destination != nil {
                    panel(wide: wide, panelWidth: panelWidth, leadingSafeArea: geometry.safeAreaInsets.leading)
                }

                topControls(wide: wide, panelWidth: panelWidth)

                // with a destination the panel has all it needs: no buttons on the map to distract
                if viewModel.destination == nil {
                    bottomButtons()
                }

                if !placesNote.isEmpty {
                    placesNoteView()
                }
            }
        }
        .confirmationDialog(
            tappedPlace?.name ?? "",
            isPresented: Binding(
                get: { tappedPlace != nil },
                set: { shown in
                    if !shown {
                        tappedPlace = nil
                    }
                }
            ),
            titleVisibility: .visible,
            presenting: tappedPlace
        ) { place in
            if viewModel.stops.count < MainViewModel.maxStops {
                Button("Add as stop") {
                    Task {
                        await viewModel.addStop(latitude: place.latitude, longitude: place.longitude)
                    }
                }
            }
            Button("Go here instead") {
                viewModel.choosePlace(place)
            }
            Button("Cancel", role: .cancel) {}
        } message: { place in
            Text(MapScreenView.placeDescription(place))
        }
        .task(id: viewModel.placesMessageRequest) {
            if viewModel.placesMessageRequest == 0 {
                return
            }
            placesNote = viewModel.placesMessage
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled {
                placesNote = ""
            }
        }
        .task {
            // the map opens on the phone's position, as in Google Maps; the first call asks for the permission
            await viewModel.refreshMyLocation(recenter: false)
        }
        // the first plan, and a new one for every new destination
        .task(id: viewModel.destination) {
            if viewModel.destination != nil {
                searchEditing = false
                searchShown = false
                searchFocused = false
                await viewModel.refreshRoutes()
            }
        }
    }

    // MARK: - layout

    private static func widePanelWidth(availableWidth: CGFloat) -> CGFloat {
        var width = availableWidth * MapScreenView.widePanelFraction
        if width < MapScreenView.widePanelMinWidth {
            width = MapScreenView.widePanelMinWidth
        } else if width > MapScreenView.widePanelMaxWidth {
            width = MapScreenView.widePanelMaxWidth
        }
        return width
    }

    private func mapInsets(wide: Bool, panelWidth: CGFloat, safeArea: EdgeInsets) -> MapInsets {
        var insets = MapInsets()
        // the top controls: one row, two with the car and the places under the search and the settings
        insets.top = safeArea.top + 76
        if secondRowVisible() {
            insets.top += MapScreenView.buttonSize + 10
        }
        // Apple's legal label must stay visible: with a destination above the panel on the phone, right of it in
        // landscape (no buttons then); without one above the favorites and recentre buttons
        if viewModel.destination != nil {
            if wide {
                // the panel also covers the leading safe area
                insets.leading = safeArea.leading + panelWidth
                insets.bottom = safeArea.bottom
            } else {
                insets.bottom = panelSize.height
            }
        } else {
            let buttonsHeight = MapScreenView.buttonSize + 24
            insets.bottom = safeArea.bottom + buttonsHeight
        }
        return insets
    }

    private func searchVisible() -> Bool {
        return viewModel.destination == nil || searchShown || searchEditing
    }

    private func secondRowVisible() -> Bool {
        return !searchEditing && (searchVisible() || viewModel.placesAvailable)
    }

    private func mapboxToken() -> String? {
        if !viewModel.hasMapboxToken {
            return nil
        }
        return viewModel.mapboxAccessToken()
    }

    private func mapTapped() {
        if searchEditing {
            stopEditing()
        } else if viewModel.destination != nil {
            searchShown.toggle()
        }
    }

    private func longPressed(latitude: Double, longitude: Double) {
        if viewModel.destination == nil {
            viewModel.pickOnMap(latitude: latitude, longitude: longitude)
        } else {
            Task {
                await viewModel.addStop(latitude: latitude, longitude: longitude)
            }
        }
    }

    /// With no destination yet the place becomes it; otherwise the user picks: a stop, or the destination instead.
    private func placeTapped(_ index: Int) {
        if index >= viewModel.places.count {
            return
        }
        let place = viewModel.places[index]
        guard let current = viewModel.destination else {
            viewModel.choosePlace(place)
            return
        }
        if !place.toDestination().sameLocationAs(current) {
            tappedPlace = place
        }
    }

    /// The address, then the kind of place when the name does not say it already and whether it is open now:
    /// "Fast food · Open · Closes 23:00".
    private static func placeDescription(_ place: Place) -> String {
        var lines: [String] = []
        if !place.details.isEmpty {
            lines.append(place.details)
        }
        var parts: [String] = []
        // an unnamed place is already called by its category
        var label = PlaceKinds.label(place.kind)
        if label.isEmpty {
            label = place.category.singular
        }
        if place.name != label && place.name != place.category.singular {
            parts.append(label)
        }
        // an alert shows plain text: the open or closed without its colour
        if let info = place.info, let hours = OpeningHours.parse(info.openingHours) {
            parts.append(hours.statusText(at: Date()).text)
        }
        if !parts.isEmpty {
            lines.append(parts.joined(separator: " · "))
        }
        return lines.joined(separator: "\n")
    }

    private func placesNoteView() -> some View {
        VStack {
            Spacer()
            Text(placesNote)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Theme.card, in: Capsule())
                .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
                .padding(.horizontal, 24)
                .padding(.bottom, viewModel.destination == nil ? MapScreenView.buttonSize + 32 : panelSize.height + 16)
        }
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    private func stopEditing() {
        searchEditing = false
        searchFocused = false
        viewModel.dismissChoices()
    }

    // MARK: - top: search and settings, the car under the search (in its place when the search is hidden), the places
    // under the settings

    private func topControls(wide: Bool, panelWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Group {
                    if searchVisible() {
                        searchBox()
                    } else {
                        carButton()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // while typing the search gets the whole row, as in Google Maps
                if !searchEditing {
                    MapButton(systemName: "gearshape.fill", label: "Settings", action: openSettings)
                }
            }
            if secondRowVisible() {
                HStack(alignment: .top, spacing: 8) {
                    Group {
                        if searchVisible() {
                            carButton()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if viewModel.placesAvailable {
                        PlacesButton(viewModel: viewModel, area: {
                            return mapArea.value
                        })
                    }
                }
            }
        }
        .padding(.leading, (wide && viewModel.destination != nil ? panelWidth : 0) + 12)
        .padding(.trailing, 12)
        .padding(.top, 8)
    }

    @ViewBuilder
    private func searchBox() -> some View {
        if !searchEditing {
            Button {
                searchEditing = true
                searchFocused = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Theme.brand)
                    Text(viewModel.resolving ? "Looking it up…" : "Where to?")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: MapScreenView.searchMaxWidth, minHeight: MapScreenView.buttonSize)
                .background(Theme.card, in: Capsule())
                .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Search a place")
        } else {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Button {
                        stopEditing()
                    } label: {
                        Image(systemName: "chevron.backward")
                            .font(.body.weight(.semibold))
                            .frame(width: 44, height: 44)
                            .accessibilityLabel("Close search")
                    }
                    .buttonStyle(.borderless)
                    TextField("Search or paste a link", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .focused($searchFocused)
                        .onSubmit {
                            runSearch(query)
                        }
                        // suggestions as the letters come; Return still runs the full search
                        .onChange(of: query) { _, text in
                            viewModel.typeSearch(text)
                        }
                    if viewModel.resolving {
                        ProgressView()
                            .frame(width: 44, height: 44)
                    } else if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                                .frame(width: 44, height: 44)
                                .accessibilityLabel("Clear search")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding(.leading, 4)
                .padding(.trailing, 8)
                .frame(minHeight: MapScreenView.buttonSize)

                if query.isEmpty {
                    Divider()
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
                    .tint(Theme.neutralAction)
                    .disabled(viewModel.resolving)
                    .padding(12)
                }

                if !viewModel.geocoderAvailable {
                    Text("Address search is unavailable. Coordinates and map links still work.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                }

                if !viewModel.resolveError.isEmpty {
                    Label(viewModel.resolveError, systemImage: "exclamationmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(Theme.error)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                }

                if !viewModel.choices.isEmpty {
                    Divider()
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            // each row gets its place, not an index: the rows follow the opening hours too, and a row
                            // redrawn for them after the list emptied would read past its end
                            ForEach(Array(viewModel.choices.enumerated()), id: \.offset) { _, choice in
                                choiceRow(choice)
                            }
                        }
                    }
                    .frame(maxHeight: 320)
                } else if !viewModel.resolving && !viewModel.suggestions.isEmpty && !query.isEmpty {
                    Divider()
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(viewModel.suggestions.enumerated()), id: \.offset) { _, suggestion in
                                choiceRow(suggestion)
                            }
                        }
                    }
                    .frame(maxHeight: 320)
                }
            }
            .frame(maxWidth: MapScreenView.searchMaxWidth)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
        }
    }

    /// A search result: its kind, where it is and how far, and whether it is open now when OpenStreetMap has its
    /// opening hours.
    private func choiceRow(_ choice: Destination) -> some View {
        let openingHours = viewModel.info(for: choice).openingHours
        return Button {
            viewModel.chooseCandidate(choice)
        } label: {
            HStack(spacing: 14) {
                KindIcon(kind: viewModel.kind(for: choice))
                VStack(alignment: .leading, spacing: 2) {
                    Text(choice.displayName())
                        .foregroundStyle(.primary)
                    let caption = choiceCaption(choice)
                    if !caption.isEmpty {
                        Text(caption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if OpeningHours.parse(openingHours) != nil {
                        KindAndStatusLine(label: "", openingHours: openingHours)
                            .font(.caption)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// "Furniture store · Grüssenweg 21, 4133 Pratteln · 5 km": what it is, where, and how far when the phone's
    /// position is known; the coordinates only when nothing else tells the places apart.
    private func choiceCaption(_ choice: Destination) -> String {
        var parts: [String] = []
        let label = viewModel.kindLabel(for: choice)
        if !label.isEmpty {
            parts.append(label)
        }
        if !choice.details.isEmpty {
            parts.append(choice.details)
        } else if choice.displayName() != choice.coordinatesText() {
            parts.append(choice.coordinatesText())
        }
        if let here = viewModel.origin {
            let there = LatLng(latitude: choice.latitude, longitude: choice.longitude)
            parts.append(RouteFormatting.distance(RouteShaping.distanceMeters(here, there)))
        }
        return parts.joined(separator: " · ")
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

    /// The selected car with its online dot; a tap opens the car menu.
    @ViewBuilder
    private func carButton() -> some View {
        if !viewModel.hasToken || viewModel.devices.isEmpty {
            Button(action: openSettings) {
                carLabel(name: "Add your car", showsDot: false)
            }
            .buttonStyle(.plain)
        } else {
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
                Divider()
                Button {
                    Task {
                        await viewModel.checkConnection()
                    }
                } label: {
                    Label("Check connection", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.selectedDevice() == nil)
                Button(role: .destructive) {
                    Task {
                        await viewModel.clearDestinationOnDevice()
                    }
                } label: {
                    Label("Clear destination on the car", systemImage: "xmark.circle")
                }
                .disabled(viewModel.selectedDevice() == nil || viewModel.sending)
            } label: {
                carLabel(name: selectedCarName(), showsDot: viewModel.selectedDevice() != nil)
            }
        }
    }

    private func carLabel(name: String, showsDot: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "car.fill")
                .foregroundStyle(Theme.brand)
                .overlay(alignment: .topTrailing) {
                    if showsDot {
                        Circle()
                            .fill(connectionColor())
                            .frame(width: 9, height: 9)
                            .overlay(Circle().stroke(Theme.card, lineWidth: 2))
                            .offset(x: 4, y: -3)
                    }
                }
            Text(name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(maxWidth: 160, alignment: .leading)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: MapScreenView.buttonSize)
        .background(Theme.card, in: Capsule())
        .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Car: " + name)
    }

    private func selectedCarName() -> String {
        if let device = viewModel.selectedDevice() {
            return CarName.of(device)
        }
        return "Choose your car"
    }

    private func connectionColor() -> Color {
        switch viewModel.connection {
        case .online:
            return Theme.success
        case .unreachable:
            return Theme.error
        case .checking, .unknown:
            return .secondary
        }
    }

    // MARK: - favorites bottom left, recentre bottom right, only without a destination

    private func bottomButtons() -> some View {
        VStack {
            Spacer()
            HStack {
                MapButton(systemName: "heart.fill", label: "Favorites", action: openFavorites)
                Spacer()
                MapButton(systemName: "location.fill", label: "Show my position") {
                    Task {
                        await viewModel.refreshMyLocation(recenter: true)
                    }
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, 12)
            .padding(.bottom, 16)
        }
    }

    // MARK: - destination panel

    @ViewBuilder
    private func panel(wide: Bool, panelWidth: CGFloat, leadingSafeArea: CGFloat) -> some View {
        if wide {
            HStack(spacing: 0) {
                ScrollView {
                    DestinationPanel(viewModel: viewModel, openSettings: openSettings)
                        .padding(16)
                        // the card goes to the screen edge, its content stays clear of the Dynamic Island
                        .padding(.leading, leadingSafeArea)
                }
                .frame(width: leadingSafeArea + panelWidth)
                .background(Theme.card)
                .clipShape(UnevenRoundedRectangle(bottomTrailingRadius: 24, topTrailingRadius: 24, style: .continuous))
                .shadow(color: .black.opacity(0.2), radius: 10)
                .ignoresSafeArea(edges: [.top, .bottom, .leading])
                Spacer(minLength: 0)
            }
        } else {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                ScrollView {
                    DestinationPanel(viewModel: viewModel, openSettings: openSettings)
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 8)
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: 440)
                .fixedSize(horizontal: false, vertical: true)
                .background(
                    UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24, style: .continuous)
                        .fill(Theme.card)
                        .shadow(color: .black.opacity(0.2), radius: 10)
                        .ignoresSafeArea(edges: .bottom)
                )
                .onGeometryChange(for: CGSize.self) { proxy in
                    proxy.size
                } action: { size in
                    panelSize = size
                }
            }
        }
    }
}

/// Destination, routes, stops and the send button.
private struct DestinationPanel: View {
    let viewModel: MainViewModel
    let openSettings: () -> Void
    @State private var detailsVisible = false

    var body: some View {
        if let destination = viewModel.destination {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 4) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(destination.displayName())
                            .font(.title2.weight(.semibold))
                            .lineLimit(2)
                        if !destination.details.isEmpty {
                            Text(destination.details)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        kindAndStatus(destination)
                    }
                    Spacer(minLength: 8)
                    Button {
                        viewModel.toggleFavorite()
                    } label: {
                        Image(systemName: viewModel.isFavorite(destination) ? "heart.fill" : "heart")
                            .font(.title3)
                            .foregroundStyle(viewModel.isFavorite(destination) ? Theme.brand : Color.secondary)
                            .frame(width: 44, height: 44)
                            .accessibilityLabel(viewModel.isFavorite(destination) ? "Remove from favorites" : "Add to favorites")
                    }
                    .buttonStyle(.borderless)
                    Button {
                        viewModel.clearSelection()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .frame(width: 44, height: 44)
                            .accessibilityLabel("Clear destination")
                    }
                    .buttonStyle(.borderless)
                }

                // needed to decide whether to send it, so never folded away
                if destination.approximate {
                    Label("Approximate: the link only had the map centre. Check the pin on the map.", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(Theme.warning)
                }

                routes()

                if !viewModel.stops.isEmpty {
                    stops()
                }

                if needsMapbox() {
                    mapboxNotice()
                }

                sendButton()

                if let feedback = viewModel.feedback {
                    FeedbackRow(feedback: feedback)
                }

                HStack {
                    if let url = MapLinks.appleMaps(destination) {
                        Link("Open in Maps", destination: url)
                    }
                    Spacer()
                    Button {
                        detailsVisible.toggle()
                    } label: {
                        Label(detailsVisible ? "Hide details" : "Details", systemImage: detailsVisible ? "chevron.up" : "chevron.down")
                            .labelStyle(.titleAndIcon)
                    }
                }
                .font(.subheadline.weight(.medium))

                if detailsVisible {
                    let info = viewModel.info(for: destination)
                    if !info.isEmpty() {
                        PlaceInfoBlock(info: info)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(destination.coordinatesText())
                            .font(.callout.monospaced())
                        if !viewModel.destinationSource.isEmpty {
                            Text("From: " + viewModel.destinationSource)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text("Long-press the map to add a stop. The car follows the route you pick.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    /// "Furniture store · Open · Closes 20:00" under the address; a tap shows the week, the phone and the website.
    @ViewBuilder
    private func kindAndStatus(_ destination: Destination) -> some View {
        let info = viewModel.info(for: destination)
        let label = viewModel.kindLabel(for: destination)
        if !label.isEmpty || OpeningHours.parse(info.openingHours) != nil {
            let line = KindAndStatusLine(label: label, openingHours: info.openingHours)
                .font(.subheadline)
                .lineLimit(2)
                .padding(.top, 2)
            if info.isEmpty() {
                line
            } else {
                Button {
                    detailsVisible.toggle()
                } label: {
                    line
                }
                .buttonStyle(.plain)
                .accessibilityHint(detailsVisible ? "Hides the details" : "Shows the details")
            }
        }
    }

    /// Without comma prime the car only gets a route through the user's Mapbox token.
    private func needsMapbox() -> Bool {
        guard let device = viewModel.selectedDevice() else {
            return false
        }
        return device.needsMapboxForRoutes() && !viewModel.hasMapboxToken
    }

    @ViewBuilder
    private func routes() -> some View {
        if viewModel.routesLoading {
            HStack(spacing: 12) {
                ProgressView()
                Text("Computing routes…")
                    .foregroundStyle(.secondary)
            }
        } else if !viewModel.routesMessage.isEmpty {
            Label(viewModel.routesMessage, systemImage: "exclamationmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(Theme.error)
        } else if !viewModel.routes.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(0..<viewModel.routes.count, id: \.self) { index in
                        routeChip(index)
                    }
                }
            }
        }
    }

    private func routeChip(_ index: Int) -> some View {
        let route = viewModel.routes[index]
        let selected = index == viewModel.selectedRouteIndex
        var label = RouteFormatting.duration(route.durationSeconds) + " · " + RouteFormatting.distance(route.distanceMeters)
        if index == 0 {
            label = "Fastest · " + label
        }
        return Button {
            viewModel.selectRoute(index)
        } label: {
            Text(label)
                .font(.subheadline.weight(selected ? .semibold : .regular))
                .foregroundStyle(selected ? Theme.brand : Color.primary)
                .padding(.horizontal, 14)
                .frame(minHeight: 40)
                .background(selected ? Theme.brandSoft : Theme.mutedFill, in: Capsule())
                .overlay(Capsule().strokeBorder(selected ? Theme.brand : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func stops() -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(0..<viewModel.stops.count, id: \.self) { index in
                    Button {
                        Task {
                            await viewModel.removeStop(at: index)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "\(index + 1).circle.fill")
                                .foregroundStyle(.white, .orange)
                            Text("Stop \(index + 1)")
                            Image(systemName: "xmark")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 36)
                        .background(Theme.mutedFill, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove stop \(index + 1)")
                }
            }
        }
    }

    private func mapboxNotice() -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text("No comma prime and no Mapbox token: your car will stay on \"Waiting for route\". A free Mapbox account fixes it.")
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .font(.subheadline)
            Button("Set up Mapbox") {
                viewModel.showMapboxSheet()
            }
            .font(.subheadline.weight(.semibold))
            .padding(.leading, 28)
        }
        .foregroundStyle(Theme.warning)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// The big button; without a car it leads to the settings instead.
    @ViewBuilder
    private func sendButton() -> some View {
        if let device = viewModel.selectedDevice(), viewModel.hasToken {
            Button {
                Task {
                    await viewModel.sendDestination()
                }
            } label: {
                HStack(spacing: 12) {
                    if viewModel.sending {
                        ProgressView()
                            .tint(Theme.onAccent)
                    } else {
                        Image(systemName: "paperplane.fill")
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Send to " + CarName.of(device))
                            .fontWeight(.semibold)
                            .lineLimit(1)
                        if needsMapbox() {
                            Text("destination only, no route")
                                .font(.caption)
                        }
                    }
                }
                .foregroundStyle(Theme.onAccent)
                .frame(maxWidth: .infinity, minHeight: 40)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 16))
            .controlSize(.large)
            .disabled(viewModel.sending)
        } else {
            Button(action: openSettings) {
                Text(viewModel.hasToken ? "Choose your car" : "Connect your comma account")
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.onAccent)
                    .frame(maxWidth: .infinity, minHeight: 40)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 16))
            .controlSize(.large)
        }
    }
}

/// Points of interest: the categories in a menu; the one picked is looked up in the part of the map in view.
private struct PlacesButton: View {
    let viewModel: MainViewModel
    let area: () -> MapArea?

    var body: some View {
        let shown = viewModel.placesCategory != nil
        Menu {
            Section("From OpenStreetMap, in the part of the map you see. Tap a place on the map to go there.") {
                ForEach(PlaceCategory.allCases) { category in
                    Button {
                        Task {
                            await viewModel.showPlaces(category, in: area())
                        }
                    } label: {
                        if category == viewModel.placesCategory {
                            Label(category.label, systemImage: "checkmark")
                        } else {
                            Label(category.label, systemImage: category.symbolName)
                        }
                    }
                }
            }
            Section {
                Button {
                    viewModel.hidePlaces()
                } label: {
                    Label("Hide places", systemImage: "xmark")
                }
                .disabled(!shown)
            }
        } label: {
            ZStack {
                if viewModel.placesLoading {
                    ProgressView()
                        .tint(shown ? Theme.onAccent : Theme.brand)
                } else {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.title3)
                        .foregroundStyle(shown ? Theme.onAccent : Theme.brand)
                }
            }
            .frame(width: 52, height: 52)
            .background(shown ? Theme.brand : Theme.card, in: Circle())
            .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
        }
        .menuOrder(.fixed)
        .accessibilityLabel("Points of interest")
    }
}

/// The part of the map in view, kept by reference: the map reports it after every move without redrawing the screen.
final class MapAreaBox {
    var value: MapArea?
}

/// Round floating button on the map, at least 52 points for use in the car.
private struct MapButton: View {
    let systemName: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.title3)
                .foregroundStyle(Theme.brand)
                .frame(width: 52, height: 52)
                .background(Theme.card, in: Circle())
                .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - Kind and opening hours

/// The symbol of a place's kind: the places menu's own, a shop, a town, an address, or a plain pin.
private struct KindIcon: View {
    let kind: String

    var body: some View {
        Image(systemName: KindIcon.symbolName(kind))
            .font(.title3)
            .foregroundStyle(Theme.brand)
            .frame(width: 28)
    }

    private static func symbolName(_ kind: String) -> String {
        if let category = PlaceKinds.category(kind) {
            return category.symbolName
        }
        if PlaceKinds.isShop(kind) {
            return "bag.fill"
        }
        if PlaceKinds.isArea(kind) {
            return "mappin.and.ellipse"
        }
        if PlaceKinds.isAddress(kind) {
            return "house.fill"
        }
        return "mappin.circle.fill"
    }
}

/// "Furniture store · Open · Closes 20:00": `label` first when there is one, the open or closed in its colour, again
/// at each new minute. Hours the app cannot read give no status: they show as written in the details.
private struct KindAndStatusLine: View {
    let label: String
    let openingHours: String

    var body: some View {
        TimelineView(.everyMinute) { context in
            KindAndStatusLine.text(label, OpeningHours.parse(openingHours), context.date)
        }
    }

    private static func text(_ label: String, _ hours: OpeningHours?, _ now: Date) -> Text {
        var line = Text(label).foregroundStyle(Color.secondary)
        guard let status = hours?.statusText(at: now) else {
            return line
        }
        if !label.isEmpty {
            line = joined(line, Text(" · ").foregroundStyle(Color.secondary))
        }
        let headline = Text(status.headline)
            .foregroundStyle(toneColor(status.tone))
            .fontWeight(.medium)
        line = joined(line, headline)
        if !status.rest.isEmpty {
            line = joined(line, Text(" · " + status.rest).foregroundStyle(Color.secondary))
        }
        return line
    }

    /// One text after the other on the same line, each in its own colour.
    private static func joined(_ first: Text, _ second: Text) -> Text {
        return Text("\(first)\(second)")
    }

    private static func toneColor(_ tone: OpeningHours.StatusText.Tone) -> Color {
        switch tone {
        case .open:
            return Theme.success
        case .soon:
            return Theme.warning
        case .closed:
            return Theme.error
        }
    }
}

/// The opening hours of the week (today in bold), the phone and the website, each when there is one.
private struct PlaceInfoBlock: View {
    let info: PlaceInfo
    // the day names in a column, as wide as the longest at the user's text size
    @ScaledMetric(relativeTo: .callout) private var dayColumnWidth: CGFloat = 104

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !info.openingHours.isEmpty {
                Text("Opening hours")
                    .font(.subheadline.weight(.semibold))
                if let hours = OpeningHours.parse(info.openingHours) {
                    TimelineView(.everyMinute) { context in
                        week(hours, today: PlaceInfoBlock.dayIndex(context.date))
                    }
                } else {
                    // more than the app reads (months, holidays by date): as mapped
                    Text(info.openingHours)
                        .font(.callout)
                }
            }
            let phoneLink = PlaceInfo.phoneLink(info.phone)
            if !phoneLink.isEmpty, let url = URL(string: phoneLink) {
                Link(destination: url) {
                    Label(info.phone, systemImage: "phone.fill")
                }
                .font(.callout)
                .accessibilityLabel("Call " + info.phone)
            }
            if !info.website.isEmpty, let url = URL(string: info.website) {
                Link(destination: url) {
                    Label(PlaceInfo.shortWebAddress(info.website), systemImage: "globe")
                        .lineLimit(1)
                }
                .font(.callout)
                .accessibilityLabel("Website " + PlaceInfo.shortWebAddress(info.website))
            }
        }
    }

    private func week(_ hours: OpeningHours, today: Int) -> some View {
        let rows = hours.weekRows()
        return VStack(alignment: .leading, spacing: 2) {
            ForEach(0..<rows.count, id: \.self) { index in
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(rows[index].day)
                        .frame(width: dayColumnWidth, alignment: .leading)
                    Text(rows[index].hours)
                }
                .font(.callout.weight(index == today ? .semibold : .regular))
            }
        }
    }

    /// 0 for Monday to 6 for Sunday, as the rows of `weekRows`.
    private static func dayIndex(_ date: Date) -> Int {
        let weekday = Calendar.current.component(.weekday, from: date)
        // the calendar counts from Sunday, 1
        return (weekday + 5) % 7
    }
}
