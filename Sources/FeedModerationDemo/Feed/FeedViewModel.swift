import Combine
import Foundation

/// Derives the visible feed reactively from `FeedRepository` and `ModerationStore` — no UIKit,
/// no direct list mutation. `visibleItems = fetchedPages - blockedCreators - reportedSekais`.
/// Block/report write into `ModerationStore` synchronously (the item disappears the same
/// frame) and fire the network call optimistically — a failure never reverts the local hide
/// (see `ARCHITECTURE.md` §4/§9).
final class FeedViewModel {
    @Published private(set) var visibleItems: [FeedItem] = []
    let toastEvents = PassthroughSubject<ToastMessage, Never>()

    private let feedRepository: FeedRepository
    private let moderationStore: ModerationStore
    private let apiClient: APIClient

    private static let paginationThreshold = 2
    private static let reportReason = "inappropriate"

    init(feedRepository: FeedRepository, moderationStore: ModerationStore, apiClient: APIClient) {
        self.feedRepository = feedRepository
        self.moderationStore = moderationStore
        self.apiClient = apiClient

        Publishers.CombineLatest3(
            feedRepository.$pages,
            moderationStore.$blockedCreatorIDs,
            moderationStore.$reportedGameIDs
        )
        .map { pages, blocked, reported in
            FeedModerationDemo.visibleItems(pages: pages, blocked: blocked, reported: reported)
        }
        .removeDuplicates()
        .receive(on: DispatchQueue.main)
        .assign(to: &$visibleItems)
    }

    func loadInitialPageIfNeeded() {
        guard visibleItems.isEmpty else { return }
        requestNextPage()
    }

    /// `displayingIndex` must be an index into `visibleItems` (the filtered list), not the raw
    /// fetched pages — otherwise a page mostly consumed by a blocked creator can look "full"
    /// while the visible tail is nearly exhausted (`ARCHITECTURE.md` §7).
    func loadNextPageIfNeeded(displayingIndex: Int) {
        guard displayingIndex >= visibleItems.count - Self.paginationThreshold else { return }
        requestNextPage()
    }

    func block(creatorID: String, creatorName: String) {
        guard !moderationStore.blockedCreatorIDs.contains(creatorID) else { return }
        moderationStore.block(creatorID: creatorID)
        toastEvents.send(ToastMessage(text: "Blocked \(creatorName)"))
        Task { [apiClient] in
            try? await apiClient.blockUser(userID: creatorID)
        }
    }

    func report(gameID: String) {
        guard !moderationStore.reportedGameIDs.contains(gameID) else { return }
        moderationStore.report(gameID: gameID)
        toastEvents.send(ToastMessage(text: "Reported"))
        Task { [apiClient] in
            try? await apiClient.reportContent(gameID: gameID, reason: Self.reportReason)
        }
    }

    private func requestNextPage() {
        Task { [feedRepository] in
            try? await feedRepository.loadNextPage()
        }
    }
}
