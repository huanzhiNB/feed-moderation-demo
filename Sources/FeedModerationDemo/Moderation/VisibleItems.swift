import Foundation

/// `visibleFeed = fetchedPages - blockedCreators - reportedSekais`, as a pure function so it's
/// testable without Combine/UIKit and reusable by both the feed and the creator page.
func visibleItems(pages: [FeedItem], blocked: Set<String>, reported: Set<String>) -> [FeedItem] {
    pages.filter { !blocked.contains($0.creatorID) && !reported.contains($0.gameID) }
}
