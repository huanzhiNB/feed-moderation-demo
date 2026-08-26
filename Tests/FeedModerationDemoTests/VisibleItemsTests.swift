import XCTest
@testable import FeedModerationDemo

final class VisibleItemsTests: XCTestCase {
    private func makeItem(gameID: String, creatorID: String) -> FeedItem {
        FeedItem(
            gameID: gameID,
            title: "Title \(gameID)",
            gameURL: URL(string: "http://127.0.0.1:8787/content/\(gameID)")!,
            coverURL: URL(string: "http://127.0.0.1:8787/avatar/\(creatorID)")!,
            creatorID: creatorID,
            creatorName: "Creator \(creatorID)",
            likeCount: 0
        )
    }

    func test_reportedGame_isHidden() {
        let reportedItem = makeItem(gameID: "game_0000", creatorID: "creator_1")
        let otherItem = makeItem(gameID: "game_0001", creatorID: "creator_2")

        let visible = visibleItems(
            pages: [reportedItem, otherItem],
            blocked: [],
            reported: ["game_0000"]
        )

        XCTAssertEqual(visible.map(\.gameID), ["game_0001"])
    }

    func test_blockedCreator_hidesAllTheirGames() {
        let blockedCreatorItem1 = makeItem(gameID: "game_0000", creatorID: "creator_1")
        let blockedCreatorItem2 = makeItem(gameID: "game_0007", creatorID: "creator_1")
        let otherItem = makeItem(gameID: "game_0001", creatorID: "creator_2")

        let visible = visibleItems(
            pages: [blockedCreatorItem1, blockedCreatorItem2, otherItem],
            blocked: ["creator_1"],
            reported: []
        )

        XCTAssertEqual(visible.map(\.gameID), ["game_0001"])
    }

    func test_otherGamesFromSameCreator_remainVisibleAfterReportingOne() {
        let reportedItem = makeItem(gameID: "game_0000", creatorID: "creator_1")
        let unreportedItem = makeItem(gameID: "game_0007", creatorID: "creator_1")

        let visible = visibleItems(
            pages: [reportedItem, unreportedItem],
            blocked: [],
            reported: ["game_0000"]
        )

        XCTAssertEqual(visible.map(\.gameID), ["game_0007"])
    }
}
