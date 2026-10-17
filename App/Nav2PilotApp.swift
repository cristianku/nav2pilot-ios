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

enum Tab: Hashable {
    case send
    case favorites
    case devices
}

struct RootView: View {
    @Bindable var viewModel: MainViewModel
    @State private var tab = Tab.send

    var body: some View {
        TabView(selection: $tab) {
            SendView(viewModel: viewModel, openDevices: {
                tab = .devices
            })
            .tabItem {
                Label("Send", systemImage: "paperplane")
            }
            .tag(Tab.send)

            FavoritesView(viewModel: viewModel)
                .tabItem {
                    Label("Favorites", systemImage: "heart")
                }
                .tag(Tab.favorites)

            DevicesView(viewModel: viewModel)
                .tabItem {
                    Label("Devices", systemImage: "car")
                }
                .tag(Tab.devices)
        }
        .onChange(of: viewModel.showSendTabRequest) {
            tab = .send
        }
        // one sheet for both tabs that offer the Mapbox setup
        .sheet(isPresented: $viewModel.mapboxSheetVisible) {
            MapboxTokenSheet(viewModel: viewModel)
        }
    }
}
