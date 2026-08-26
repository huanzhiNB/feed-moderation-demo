import XCTest
@testable import FeedModerationDemo

final class FeedViewModelTests: XCTestCase {
    private let baseURL = URL(string: "http://127.0.0.1:8787")!
    private let suiteName = "FeedViewModelTests"
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

    private func feedJSON(_ items: [(gameID: String, creatorID: String)]) -> Data {
        let entries = items.map { item in
            """
            {"game_id": "\(item.gameID)", "title": "T", \
            "game_url": "http://127.0.0.1:8787/content/\(item.gameID)", \
            "cover_url": "http://127.0.0.1:8787/avatar/\(item.creatorID)", \
            "creator_id": "\(item.creatorID)", "creator_name": "C", "like_count": 0}
            """
        }.joined(separator: ",")
        return Data("[\(entries)]".utf8)
    }

    /// Exercises the real `CombineLatest3` pipeline, not just the pure `visibleItems` function:
    /// page 1 has creators A and B; blocking A leaves only B visible; a later page delivering
    /// another A game must not reappear, with no special-casing at fetch time.
    func test_visibleItems_excludesBlockedCreator_andStaysExcludedAcrossLaterPage() async throws {
        let loader = StubDataLoader(responses: [
            (feedJSON([("game_0000", "creator_a"), ("game_0001", "creator_b")]), 200),
            (feedJSON([("game_0007", "creator_a")]), 200),
        ])
        let repository = FeedRepository(apiClient: APIClient(baseURL: baseURL, urlSession: loader))
        let moderationStore = ModerationStore(userDefaults: userDefaults)
        let viewModel = FeedViewModel(feedRepository: repository, moderationStore: moderationStore)

        try await repository.loadNextPage()
        XCTAssertEqual(viewModel.visibleItems.map(\.gameID), ["game_0000", "game_0001"])

        let onlyCreatorBVisible = XCTestExpectation(description: "visibleItems excludes blocked creator A")
        let cancellable = viewModel.$visibleItems.sink { items in
            if items.map(\.gameID) == ["game_0001"] {
                onlyCreatorBVisible.fulfill()
            }
        }
        moderationStore.block(creatorID: "creator_a")
        await fulfillment(of: [onlyCreatorBVisible], timeout: 1)
        cancellable.cancel()

        try await repository.loadNextPage()

        XCTAssertEqual(viewModel.visibleItems.map(\.gameID), ["game_0001"])
    }
}
