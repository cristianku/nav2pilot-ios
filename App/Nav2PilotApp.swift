import Nav2PilotKit
import SwiftUI
import AppIntents

@MainActor private enum PhoneSession {
    static let model = AppContainer.makeViewModel(withRoutePlanning: true)
}

/// Open a search on the phone. The spoken query never sends anything to a device.
struct FindDestinationIntent: AppIntent {
    static var title: LocalizedStringResource = "Find a destination"
    static var openAppWhenRun = true
    @Parameter(title: "Destination", requestValueDialog: "Where would you like to go?")
    var destination: String

    @MainActor func perform() async throws -> some IntentResult {
        await PhoneSession.model.voiceSearch(destination)
        return .result()
    }
}

struct Nav2PilotShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: FindDestinationIntent(), phrases: [
            "Find a destination with \(.applicationName)"
        ], shortTitle: "Find destination", systemImageName: "magnifyingglass")
    }
}

@main
struct Nav2PilotApp: App {
    @State private var viewModel = PhoneSession.model
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView(viewModel: viewModel)
                .onOpenURL { url in
                    // geo: links opened with Nav2Pilot
                    Task {
                        await viewModel.handleLink(url.absoluteString)
                    }
                }
                .onChange(of: scenePhase, initial: true) { _, phase in
                    if phase == .active {
                        // the share extension may have changed devices, favorites or the token
                        viewModel.reloadStoredData()
                        Task {
                            await viewModel.checkConnection()
                        }
                    }
                }
        }
    }
}

/// The map is the app; favorites and settings open as sheets over it.
struct RootView: View {
    @Bindable var viewModel: MainViewModel
    @State private var settingsOpen = false
    @State private var favoritesOpen = false
    @AppStorage("releaseHighlights.seenEdition") private var seenEdition = ""

    var body: some View {
        Group {
            if seenEdition != ReleaseHighlights.edition && viewModel.showSendTabRequest == 0 {
                ReleaseHighlights { seenEdition = ReleaseHighlights.edition }
            } else {
                map
            }
        }
    }

    private var map: some View {
        MapScreenView(
            viewModel: viewModel,
            openSettings: {
                settingsOpen = true
            },
            openFavorites: {
                favoritesOpen = true
            }
        )
        // a shared place or a picked favorite: back to the map
        .onChange(of: viewModel.showSendTabRequest) {
            settingsOpen = false
            favoritesOpen = false
        }
        .sheet(isPresented: $settingsOpen) {
            DevicesView(viewModel: viewModel, onClose: {
                settingsOpen = false
            })
        }
        .sheet(isPresented: $favoritesOpen) {
            FavoritesView(viewModel: viewModel, onClose: {
                favoritesOpen = false
            })
            .presentationDetents([.medium, .large])
        }
        // from the map panel; with the settings open, the settings present it themselves
        .sheet(isPresented: mapboxSheetOverMap()) {
            MapboxTokenSheet(viewModel: viewModel)
        }
        .sheet(isPresented: Binding(get: { viewModel.tokenSheetVisible && !settingsOpen },
                                   set: { if !$0 { viewModel.hideTokenSheet() } })) {
            TokenSheet(viewModel: viewModel)
        }
    }

    private func mapboxSheetOverMap() -> Binding<Bool> {
        return Binding(
            get: {
                return viewModel.mapboxSheetVisible && !settingsOpen
            },
            set: { visible in
                if !visible {
                    viewModel.hideMapboxSheet()
                }
            }
        )
    }
}
