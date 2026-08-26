import Combine
import Foundation

/// Drives the SwiftUI creator page. No UIKit/SwiftUI import — testable the same way
/// `FeedViewModel` is (README: "Combine is the workhorse (`@Published` + `ObservableObject`
/// for the SwiftUI binding)").
///
/// `visibleGames` reuses the exact same `visibleItems(pages:blocked:reported:)` free function
/// the feed uses, passing this repository's `items` instead of the feed's pages — so blocking
/// this creator from their own `⋯` panel empties this list through the identical derivation,
/// and a game reported (not blocked) elsewhere stays hidden here too
/// (`docs/architecture-plan.md` §7).
final class CreatorProfileViewModel: ObservableObject {
    let creatorID: String
    let creatorName: String

    @Published private(set) var profile: UserProfile?
    @Published private(set) var visibleGames: [FeedItem] = []

    let toastEvents = PassthroughSubject<ToastMessage, Never>()
    let didBlockCreator = PassthroughSubject<Void, Never>()

    private let gamesRepository: CreatorGamesRepository
    private let moderationStore: ModerationStore
    private let apiClient: APIClient

    private static let paginationThreshold = 2

    init(
        creatorID: String,
        creatorName: String,
        gamesRepository: CreatorGamesRepository,
        moderationStore: ModerationStore,
        apiClient: APIClient
    ) {
        self.creatorID = creatorID
        self.creatorName = creatorName
        self.gamesRepository = gamesRepository
        self.moderationStore = moderationStore
        self.apiClient = apiClient

        Publishers.CombineLatest3(
            gamesRepository.$items,
            moderationStore.$blockedCreatorIDs,
            moderationStore.$reportedGameIDs
        )
        .map { items, blocked, reported in
            FeedModerationDemo.visibleItems(pages: items, blocked: blocked, reported: reported)
        }
        .removeDuplicates()
        .receive(on: DispatchQueue.main)
        .assign(to: &$visibleGames)
    }

    func loadInitialContentIfNeeded() {
        guard profile == nil else { return }
        Task { [weak self, apiClient, creatorID] in
            let fetchedProfile = try? await apiClient.fetchUserProfile(userID: creatorID)
            await MainActor.run {
                self?.profile = fetchedProfile
            }
        }
        requestNextPage()
    }

    /// `displayingIndex` must index into `visibleGames`, not the raw fetched `items` — same
    /// starvation caveat as the feed (`docs/architecture-plan.md` §7).
    func loadNextPageIfNeeded(displayingIndex: Int) {
        guard displayingIndex >= visibleGames.count - Self.paginationThreshold else { return }
        requestNextPage()
    }

    func block() {
        guard !moderationStore.blockedCreatorIDs.contains(creatorID) else { return }
        moderationStore.block(creatorID: creatorID)
        toastEvents.send(ToastMessage(text: "Blocked \(creatorName)"))
        didBlockCreator.send(())
        Task { [apiClient, creatorID] in
            try? await apiClient.blockUser(userID: creatorID)
        }
    }

    private func requestNextPage() {
        Task { [gamesRepository] in
            try? await gamesRepository.loadNextPage()
        }
    }
}
