import Combine
import Foundation

/// Derives the visible feed reactively from `FeedRepository` and `ModerationStore` — no UIKit,
/// no direct list mutation. `visibleItems = fetchedPages - blockedCreators - reportedSekais`.
final class FeedViewModel {
    @Published private(set) var visibleItems: [FeedItem] = []

    init(feedRepository: FeedRepository, moderationStore: ModerationStore) {
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
}
