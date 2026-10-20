import Nav2PilotKit
import SwiftUI

struct FavoritesView: View {
    let viewModel: MainViewModel
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            content()
                .background(Theme.background)
                .navigationTitle("Favorites")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", action: onClose)
                    }
                }
        }
    }

    @ViewBuilder
    private func content() -> some View {
        if viewModel.favorites.isEmpty {
            ContentUnavailableView(
                "Your places, one tap away",
                systemImage: "heart",
                description: Text("Tap the heart on a destination to keep it here.")
            )
        } else {
            List {
                ForEach(viewModel.favorites) { favorite in
                    HStack(spacing: 12) {
                        Button {
                            viewModel.selectFavorite(favorite)
                        } label: {
                            FavoriteRow(destination: favorite.destination)
                        }
                        .buttonStyle(.plain)
                        Spacer(minLength: 0)
                        sendButton(favorite)
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(Theme.card)
                    .swipeActions {
                        Button(role: .destructive) {
                            viewModel.removeFavorite(favorite.id)
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                    // the same removal without the swipe gesture
                    .contextMenu {
                        Button(role: .destructive) {
                            viewModel.removeFavorite(favorite.id)
                        } label: {
                            Label("Remove from favorites", systemImage: "trash")
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
    }

    private func sendButton(_ favorite: Favorite) -> some View {
        let disabled = viewModel.selectedDevice() == nil || viewModel.sending
        return Button {
            Task {
                await viewModel.sendFavorite(favorite)
            }
        } label: {
            Image(systemName: "paperplane.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.onAccent)
                .frame(width: 44, height: 44)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .opacity(disabled ? 0.4 : 1)
        }
        .buttonStyle(.borderless)
        .disabled(disabled)
        .accessibilityLabel(sendLabel(favorite))
    }

    private func sendLabel(_ favorite: Favorite) -> String {
        return "Send " + favorite.destination.displayName() + " to comma"
    }
}

private struct FavoriteRow: View {
    let destination: Destination

    var body: some View {
        HStack(spacing: 14) {
            IconBadge(systemName: "mappin", tint: Theme.brand, background: Theme.brandSoft)
            // without a name the title is the coordinates, otherwise they stay in the Send details
            VStack(alignment: .leading, spacing: 2) {
                Text(destination.displayName())
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                if !destination.details.isEmpty {
                    Text(destination.details)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .multilineTextAlignment(.leading)
        }
        .contentShape(Rectangle())
    }
}
