import Nav2PilotKit
import SwiftUI

@main
struct Nav2PilotApp: App {
    @State private var viewModel = AppContainer.makeViewModel(withRoutePlanning: true)
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

    var body: some View {
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
