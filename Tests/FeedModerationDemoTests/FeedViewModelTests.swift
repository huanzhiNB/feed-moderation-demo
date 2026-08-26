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

    /// Waits for `visibleItems` to match `gameIDs` through the real published pipeline, rather
    /// than reading it synchronously — delivery hops through `.receive(on: .main)`, so a bare
    /// assertion right after an `await` can race and read a stale value (`docs/architecture-plan.md` §10).
    private func expectVisibleItems(_ viewModel: FeedViewModel, toEqual gameIDs: [String]) async {
        if viewModel.visibleItems.map(\.gameID) == gameIDs { return }
        let expectation = XCTestExpectation(description: "visibleItems == \(gameIDs)")
        let cancellable = viewModel.$visibleItems.sink { items in
            if items.map(\.gameID) == gameIDs {
                expectation.fulfill()
            }
        }
        await fulfillment(of: [expectation], timeout: 1)
        cancellable.cancel()
    }

    /// Exercises the real `CombineLatest3` pipeline, not just the pure `visibleItems` function:
    /// page 1 has creators A and B; blocking A leaves only B visible; a later page delivering
    /// another A game must not reappear, with no special-casing at fetch time.
    func test_visibleItems_excludesBlockedCreator_andStaysExcludedAcrossLaterPage() async throws {
        let loader = StubDataLoader(responses: [
            (feedJSON([("game_0000", "creator_a"), ("game_0001", "creator_b")]), 200),
            (feedJSON([("game_0007", "creator_a")]), 200),
        ])
        let apiClient = APIClient(baseURL: baseURL, urlSession: loader)
        let repository = FeedRepository(apiClient: apiClient)
        let moderationStore = ModerationStore(userDefaults: userDefaults)
        let viewModel = FeedViewModel(feedRepository: repository, moderationStore: moderationStore, apiClient: apiClient)

        try await repository.loadNextPage()
        await expectVisibleItems(viewModel, toEqual: ["game_0000", "game_0001"])

        moderationStore.block(creatorID: "creator_a")
        await expectVisibleItems(viewModel, toEqual: ["game_0001"])

        try await repository.loadNextPage()
        await expectVisibleItems(viewModel, toEqual: ["game_0001"])
    }

    /// Block writes into `ModerationStore` and fires the toast synchronously, and is
    /// idempotent under a rapid double-tap — no duplicate toast or store write.
    func test_block_writesToModerationStore_andEmitsToastOnce() {
        let loader = StubDataLoader(data: Data(#"{"code": 0, "message": "ok", "data": {"echo": {}}}"#.utf8))
        let apiClient = APIClient(baseURL: baseURL, urlSession: loader)
        let moderationStore = ModerationStore(userDefaults: userDefaults)
        let viewModel = FeedViewModel(
            feedRepository: FeedRepository(apiClient: apiClient),
            moderationStore: moderationStore,
            apiClient: apiClient
        )

        var toastMessages: [ToastMessage] = []
        let cancellable = viewModel.toastEvents.sink { toastMessages.append($0) }

        viewModel.block(creatorID: "creator_1", creatorName: "Creator One")
        viewModel.block(creatorID: "creator_1", creatorName: "Creator One")

        XCTAssertEqual(moderationStore.blockedCreatorIDs, ["creator_1"])
        XCTAssertEqual(toastMessages, [ToastMessage(text: "Blocked Creator One")])
        cancellable.cancel()
    }

    /// Report writes into `ModerationStore` and fires the toast synchronously, and is
    /// idempotent under a rapid double-tap.
    func test_report_writesToModerationStore_andEmitsToastOnce() {
        let loader = StubDataLoader(data: Data(#"{"code": 0, "message": "ok", "data": {"echo": {}}}"#.utf8))
        let apiClient = APIClient(baseURL: baseURL, urlSession: loader)
        let moderationStore = ModerationStore(userDefaults: userDefaults)
        let viewModel = FeedViewModel(
            feedRepository: FeedRepository(apiClient: apiClient),
            moderationStore: moderationStore,
            apiClient: apiClient
        )

        var toastMessages: [ToastMessage] = []
        let cancellable = viewModel.toastEvents.sink { toastMessages.append($0) }

        viewModel.report(gameID: "game_0042")
        viewModel.report(gameID: "game_0042")

        XCTAssertEqual(moderationStore.reportedGameIDs, ["game_0042"])
        XCTAssertEqual(toastMessages, [ToastMessage(text: "Reported")])
        cancellable.cancel()
    }
}
