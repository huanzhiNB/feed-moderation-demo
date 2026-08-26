import XCTest
@testable import FeedModerationDemo

final class ModerationStoreTests: XCTestCase {
    private let suiteName = "ModerationStoreTests"
    private var userDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        userDefaults = UserDefaults(suiteName: suiteName)
        userDefaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        userDefaults.removePersistentDomain(forName: suiteName)
        userDefaults = nil
        super.tearDown()
    }

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

    func test_gameFromBlockedCreator_remainsHidden_whenDeliveredInLaterPage() {
        let store = ModerationStore(userDefaults: userDefaults)
        store.block(creatorID: "creator_1")

        let firstPage = [makeItem(gameID: "game_0001", creatorID: "creator_2")]
        let visibleFirstPage = visibleItems(pages: firstPage, blocked: store.blockedCreatorIDs, reported: store.reportedGameIDs)
        XCTAssertEqual(visibleFirstPage.map(\.gameID), ["game_0001"])

        let laterPage = firstPage + [makeItem(gameID: "game_0007", creatorID: "creator_1")]
        let visibleLaterPage = visibleItems(pages: laterPage, blocked: store.blockedCreatorIDs, reported: store.reportedGameIDs)
        XCTAssertEqual(visibleLaterPage.map(\.gameID), ["game_0001"])
    }

    func test_reportedGameIDs_persistAcrossStoreRecreation() {
        let originalStore = ModerationStore(userDefaults: userDefaults)
        originalStore.report(gameID: "game_0042")

        let recreatedStore = ModerationStore(userDefaults: userDefaults)

        XCTAssertEqual(recreatedStore.reportedGameIDs, ["game_0042"])
    }

    func test_blockedCreatorIDs_persistAcrossStoreRecreation() {
        let originalStore = ModerationStore(userDefaults: userDefaults)
        originalStore.block(creatorID: "creator_1")

        let recreatedStore = ModerationStore(userDefaults: userDefaults)

        XCTAssertEqual(recreatedStore.blockedCreatorIDs, ["creator_1"])
    }

    func test_block_and_report_areIdempotent() {
        let store = ModerationStore(userDefaults: userDefaults)

        store.block(creatorID: "creator_1")
        store.block(creatorID: "creator_1")
        store.report(gameID: "game_0042")
        store.report(gameID: "game_0042")

        XCTAssertEqual(store.blockedCreatorIDs, ["creator_1"])
        XCTAssertEqual(store.reportedGameIDs, ["game_0042"])
    }
}
