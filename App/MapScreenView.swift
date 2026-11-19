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
    @State private var previewHeight: CGFloat = 0
    @FocusState private var searchFocused: Bool
    // the part of the map in view, where the places are looked for; a box, so a map move does not redraw the screen
    @State private var mapArea = MapAreaBox()
    @State private var searchAreaOffered = false
    // a place tapped while there is already a destination: a stop, or the destination instead
    @State private var tappedPlace: Place?
    @State private var shortcutHint = ""
    @State private var seenVoice = 0
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
            places: viewModel.places,
            preview: tappedPlace
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
                        if tappedPlace == nil { longPressed(latitude: latitude, longitude: longitude) }
                    },
                    onSelectRoute: { index in
                        if tappedPlace == nil { viewModel.selectRoute(index) } else { tappedPlace = nil }
                    },
                    onTapPlace: { index in
                        placeTapped(index)
                    },
                    onAreaChange: { area in
                        mapArea.value = area
                        if let old = viewModel.placesArea {
                            let height = old.north - old.south, width = old.east - old.west
                            searchAreaOffered = abs(area.center().latitude - old.center().latitude) > height / 4 ||
                                abs(area.center().longitude - old.center().longitude) > width / 4 ||
                                area.north - area.south > height * 1.5 || area.east - area.west > width * 1.5
                        }
                    }
                )
                .ignoresSafeArea()

                if viewModel.destination != nil && tappedPlace == nil {
                    panel(wide: wide, panelWidth: panelWidth, leadingSafeArea: geometry.safeAreaInsets.leading)
                }

                topControls(wide: wide, panelWidth: panelWidth)

                // with a destination the panel has all it needs: no buttons on the map to distract
                if viewModel.destination == nil && tappedPlace == nil && !searchEditing {
                    bottomButtons()
                }

                if !placesNote.isEmpty {
                    placesNoteView()
                }
                if let place = tappedPlace {
                    let same = viewModel.destination?.sameLocationAs(place.toDestination()) == true
                    PlacePreviewCard(place: place, parking: viewModel.parking,
                                     canGo: !same, canAdd: !same && viewModel.destination != nil && viewModel.stops.count < MainViewModel.maxStops,
                                     dismiss: { tappedPlace = nil },
                                     go: { tappedPlace = nil; viewModel.choosePlace(place) },
                                     add: {
                                         tappedPlace = nil
                                         Task { await viewModel.addStop(latitude: place.latitude, longitude: place.longitude) }
                                     })
                        .id("\(place.latitude),\(place.longitude),\(place.name)")
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { previewHeight = $0 }
                        .frame(maxWidth: wide ? panelWidth : 520, maxHeight: geometry.size.height * 0.65, alignment: .bottom)
                        .padding(8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: wide ? .bottomLeading : .bottom)
                }
            }
        }
        .onChange(of: viewModel.placesCategory) { tappedPlace = nil; searchAreaOffered = false }
        .onChange(of: viewModel.showSendTabRequest) { tappedPlace = nil }
        .onChange(of: viewModel.voiceRequest, initial: true) {
            guard viewModel.voiceRequest != seenVoice else { return }
            seenVoice = viewModel.voiceRequest
            tappedPlace = nil
            query = viewModel.voiceQuery
            searchEditing = true
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
        if tappedPlace != nil && !wide {
            insets.bottom = safeArea.bottom + previewHeight + 16
        } else if viewModel.destination != nil {
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
        return !searchEditing && viewModel.placesAvailable
    }

    private func mapboxToken() -> String? {
        if !viewModel.hasMapboxToken {
            return nil
        }
        return viewModel.mapboxAccessToken()
    }

    private func mapTapped() {
        if tappedPlace != nil {
            tappedPlace = nil
        } else if searchEditing {
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

    /// Inspection is local UI state: even a first pin cannot change an itinerary.
    private func placeTapped(_ index: Int) {
        guard viewModel.places.indices.contains(index) else { return }
        stopEditing()
        tappedPlace = viewModel.places[index]
    }

    /// The address, then the kind of place when the name does not say it already and whether it is open now:
    /// "Fast food · Open · Closes 23:00".
    fileprivate static func placeDescription(_ place: Place, includeHours: Bool) -> String {
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
        if includeHours, let info = place.info, let hours = OpeningHours.parse(info.openingHours) {
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
                    } else if viewModel.selectedDevice() != nil {
                        carButton()
                    } else {
                        Color.clear.frame(height: 1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // while typing the search gets the whole row, as in Google Maps
                if !searchEditing {
                    MapButton(systemName: "gearshape.fill", label: "Settings", action: openSettings)
                }
            }
            if secondRowVisible() {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(PlaceCategory.allCases) { category in
                            let active = viewModel.placesCategory == category
                            Button {
                                tappedPlace = nil
                                if active { viewModel.hidePlaces() }
                                else { Task { await viewModel.showPlaces(category, in: mapArea.value) } }
                            } label: {
                                Label(category.label, systemImage: category.symbolName)
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 12).frame(minHeight: 42)
                                    .foregroundStyle(active ? Theme.onAccent : Theme.brand)
                                    .background(active ? Theme.brand : Theme.card, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(active ? .isSelected : [])
                        }
                    }
                }
                if searchAreaOffered, !viewModel.placesLoading, let category = viewModel.placesCategory {
                    Button("Search this area") {
                        tappedPlace = nil
                        searchAreaOffered = false
                        Task { await viewModel.showPlaces(category, in: mapArea.value) }
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
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
                tappedPlace = nil
                query = ""
                shortcutHint = ""
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
                    HStack {
                        ForEach(["Home", "Work"], id: \.self) { slot in
                            let saved = viewModel.shortcuts.first { $0.id == slot }
                            Button(saved == nil ? "Set \(slot)" : slot) {
                                if let saved { stopEditing(); viewModel.selectFavorite(saved) }
                                else { shortcutHint = "Choose a destination, then open Details → Set as \(slot)." }
                            }
                        }
                    }.padding(.horizontal, 12)
                    if !shortcutHint.isEmpty { Text(shortcutHint).font(.caption).padding(.horizontal, 12) }
                    if !viewModel.recentSent.isEmpty {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(viewModel.recentSent) { entry in
                                    Button(entry.destination.displayName()) { stopEditing(); viewModel.selectFavorite(entry) }
                                }
                                Button("Clear recently sent") { viewModel.clearRecent() }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.frame(maxHeight: 140).padding(.horizontal, 12)
                    }
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
                    Text(choice.displayName() + (choice.locality.isEmpty || choice.locality == choice.name ? "" : " · " + choice.locality))
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
                if let here = viewModel.origin {
                    Text(RouteFormatting.distance(RouteShaping.distanceMeters(here, LatLng(latitude: choice.latitude, longitude: choice.longitude))))
                        .font(.caption.weight(.medium))
                }
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
                carButton()
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
    @State private var justSent = false

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
                    HStack {
                        ForEach(["Home", "Work"], id: \.self) { slot in
                            let assigned = viewModel.shortcuts.first { $0.id == slot }?.destination.sameLocationAs(destination) == true
                            Button(assigned ? "Remove \(slot)" : "Set as \(slot)") {
                                viewModel.setShortcut(slot, to: assigned ? nil : destination)
                            }
                        }
                    }
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
                    if viewModel.feedback?.success == true {
                        justSent = true
                        try? await Task.sleep(for: .seconds(2.5))
                        justSent = false
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    if viewModel.sending {
                        ProgressView()
                            .tint(Theme.onAccent)
                    } else {
                        Image(systemName: justSent ? "checkmark.circle.fill" : "paperplane.fill")
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text((justSent ? "Sent to " : "Send to ") + CarName.of(device))
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
            .tint(justSent ? Theme.success : Theme.brand)
            .sensoryFeedback(.success, trigger: justSent) { _, new in new }
            .disabled(viewModel.sending || justSent)
        } else {
            Button(action: { if viewModel.hasToken { openSettings() } else { viewModel.showTokenSheet() } }) {
                Text(viewModel.hasToken ? "Choose your car" : "Connect your car to send")
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

private struct PlacePreviewCard: View {
    let place: Place
    let parking: BaselParking?
    let canGo: Bool
    let canAdd: Bool
    let dismiss: () -> Void
    let go: () -> Void
    let add: () -> Void
    @State private var garage: BaselParking.Garage?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    let fallback = place.name == place.category.singular && !place.details.isEmpty
                        ? "\(place.name) · \(place.details.prefix { $0 != "," })" : place.name
                    Label(garage?.title ?? fallback, systemImage: place.category.symbolName)
                        .font(.headline)
                    Spacer()
                    Button(action: dismiss) {
                        Image(systemName: "xmark").frame(width: 44, height: 44)
                    }.accessibilityLabel("Close place preview")
                }
                let description = MapScreenView.placeDescription(place, includeHours: garage == nil)
                if let garage, !garage.address.isEmpty && !description.contains(garage.address) { Text(garage.address) }
                if !description.isEmpty { Text(description) }
                if place.details.isEmpty && garage == nil { Text(place.toDestination().coordinatesText()).font(.caption) }
                if !place.parkingNotes.isEmpty { Text(place.parkingNotes) }
                if place.category == .parking {
                    Text(garage?.availability ?? "Availability unknown").bold()
                    if let garage {
                        Text("Parkhäuser Basel-Stadt · \(garage.published.formatted(date: .omitted, time: .shortened))")
                            .font(.caption)
                    }
                }
                HStack {
                    if canGo { Button("Go here", action: go).buttonStyle(.borderedProminent) }
                    if canAdd { Button("Add as stop", action: add).buttonStyle(.bordered) }
                }
            }.padding(14)
        }
        .scrollBounceBehavior(.basedOnSize)
        .fixedSize(horizontal: false, vertical: true)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20))
        .shadow(radius: 6)
        .task {
            guard place.category == .parking else { return }
            while !Task.isCancelled {
                garage = await parking?.lookup(place)
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
            }
        }
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
