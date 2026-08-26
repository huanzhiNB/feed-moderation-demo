import Combine
import Foundation

/// Owns the raw, unfiltered fetched feed and its pagination state. Moderation filtering is
/// deliberately not applied here — `visibleItems(pages:blocked:reported:)` derives that from
/// `pages` elsewhere, so a page re-delivering an already-blocked/reported item is still stored
/// as-is.
final class FeedRepository {
    @Published private(set) var pages: [FeedItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isExhausted = false

    private let apiClient: APIClient
    private let pageSize: Int
    private var nextCursor = 0

    init(apiClient: APIClient, pageSize: Int = 10) {
        self.apiClient = apiClient
        self.pageSize = pageSize
    }

    func loadNextPage() async throws {
        guard !isLoading, !isExhausted else { return }
        isLoading = true
        defer { isLoading = false }

        let fetched = try await apiClient.fetchFeed(limit: pageSize, refresh: nextCursor)
        guard !fetched.isEmpty else {
            isExhausted = true
            return
        }

        let existingIDs = Set(pages.map(\.gameID))
        pages.append(contentsOf: fetched.filter { !existingIDs.contains($0.gameID) })
        nextCursor += 1
    }
}
