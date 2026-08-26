import SwiftUI

/// Avatar, name, bio, and the creator's paged (visible) sekais, with a `⋯` menu offering
/// Block. Purely declarative content — navigation, toast, and pop-after-block are handled by
/// the hosting `CreatorProfileViewController`, kept UIKit-native like the rest of the app.
struct CreatorProfileView: View {
    @ObservedObject var viewModel: CreatorProfileViewModel

    var body: some View {
        List {
            Section {
                HStack(spacing: 16) {
                    AsyncImage(url: viewModel.profile?.avatar) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Color.secondary.opacity(0.2)
                    }
                    .frame(width: 64, height: 64)
                    .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.profile?.nickName ?? viewModel.creatorName)
                            .font(.headline)
                        if let bio = viewModel.profile?.bio {
                            Text(bio)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.vertical, 8)
            }

            Section {
                ForEach(Array(viewModel.visibleGames.enumerated()), id: \.element.gameID) { index, game in
                    Text(game.title)
                        .onAppear {
                            viewModel.loadNextPageIfNeeded(displayingIndex: index)
                        }
                }
            }
        }
        .navigationTitle(viewModel.creatorName)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button("Block", role: .destructive) {
                        viewModel.block()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .accessibilityLabel("More")
                }
            }
        }
        .onAppear {
            viewModel.loadInitialContentIfNeeded()
        }
    }
}
