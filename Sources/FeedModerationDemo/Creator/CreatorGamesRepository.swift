import Combine
import Foundation

/// Mirrors `FeedRepository`'s shape for one creator's own paged sekai list. Unlike the feed,
/// `userGames` returns `has_more` directly — no empty-page inference needed
/// (`docs/architecture-plan.md` §7). No moderation filtering here either — same derive,
/// don't-mutate rule as the feed.
final class CreatorGamesRepository {
    @Published private(set) var items: [FeedItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var hasMore = true

    private let apiClient: APIClient
    private let userID: String
    private let pageSize: Int
    private var nextPage = 0

    init(apiClient: APIClient, userID: String, pageSize: Int = 10) {
        self.apiClient = apiClient
        self.userID = userID
        self.pageSize = pageSize
    }

    /// `@MainActor`-isolated for the same reason as `FeedRepository.loadNextPage()`: makes the
    /// `isLoading` check-then-set below atomic against overlapping `willDisplay`-triggered
    /// `Task`s during a fast flick.
    @MainActor
    func loadNextPage() async throws {
        guard !isLoading, hasMore else { return }
        isLoading = true
        defer { isLoading = false }

        let page = try await apiClient.fetchUserGames(userID: userID, page: nextPage, size: pageSize)
        let existingIDs = Set(items.map(\.gameID))
        items.append(contentsOf: page.list.filter { !existingIDs.contains($0.gameID) })
        hasMore = page.hasMore
        nextPage += 1
    }
}
