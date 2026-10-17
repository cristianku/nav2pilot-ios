import Nav2PilotKit
import SwiftUI

struct FavoritesView: View {
    let viewModel: MainViewModel

    var body: some View {
        NavigationStack {
            content()
                .navigationTitle("Favorites")
        }
    }

    @ViewBuilder
    private func content() -> some View {
        if viewModel.favorites.isEmpty {
            ContentUnavailableView(
                "No favorites yet",
                systemImage: "heart",
                description: Text("Tap the heart on a destination to keep it here.")
            )
        } else {
            List {
                ForEach(viewModel.favorites) { favorite in
                    HStack {
                        Button {
                            viewModel.selectFavorite(favorite)
                        } label: {
                            FavoriteRow(destination: favorite.destination)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        Button {
                            Task {
                                await viewModel.sendFavorite(favorite)
                            }
                        } label: {
                            Image(systemName: "paperplane.fill")
                                .font(.title3)
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(Color.blue, in: RoundedRectangle(cornerRadius: 10))
                                .opacity(viewModel.selectedDevice() == nil || viewModel.sending ? 0.4 : 1)
                        }
                        .buttonStyle(.borderless)
                        .disabled(viewModel.selectedDevice() == nil || viewModel.sending)
                        .accessibilityLabel("Send to comma")
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            viewModel.removeFavorite(favorite.id)
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }
}

private struct FavoriteRow: View {
    let destination: Destination

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "mappin.circle.fill")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(destination.displayName())
                    .foregroundStyle(.primary)
                if !destination.details.isEmpty {
                    Text(destination.details)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if destination.displayName() != destination.coordinatesText() {
                    Text(destination.coordinatesText())
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
