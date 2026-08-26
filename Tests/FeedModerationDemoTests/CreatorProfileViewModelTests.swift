import XCTest
@testable import FeedModerationDemo

final class CreatorProfileViewModelTests: XCTestCase {
    private let baseURL = URL(string: "http://127.0.0.1:8787")!
    private let suiteName = "CreatorProfileViewModelTests"
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

    private func userGamesJSON(_ items: [(gameID: String, creatorID: String)]) -> Data {
        let entries = items.map { item in
            """
            {"game_id": "\(item.gameID)", "title": "T", \
            "game_url": "http://127.0.0.1:8787/content/\(item.gameID)", \
            "cover_url": "http://127.0.0.1:8787/avatar/\(item.creatorID)", \
            "creator_id": "\(item.creatorID)", "creator_name": "C", "like_count": 0}
            """
        }.joined(separator: ",")
        let json = """
        {"code": 0, "message": "ok", "data": {"list": [\(entries)], "page": 0, "size": 10, "has_more": false}}
        """
        return Data(json.utf8)
    }

    private func makeViewModel(
        creatorID: String,
        items: [(gameID: String, creatorID: String)],
        moderationStore: ModerationStore
    ) -> (CreatorProfileViewModel, CreatorGamesRepository) {
        let loader = StubDataLoader(data: userGamesJSON(items))
        let apiClient = APIClient(baseURL: baseURL, urlSession: loader)
        let repository = CreatorGamesRepository(apiClient: apiClient, userID: creatorID)
        let viewModel = CreatorProfileViewModel(
            creatorID: creatorID,
            creatorName: "Creator Name",
            gamesRepository: repository,
            moderationStore: moderationStore,
            apiClient: apiClient
        )
        return (viewModel, repository)
    }

    /// Waits for `visibleGames` to match `gameIDs` through the real published pipeline — a bare
    /// assertion right after an `await` can race `.receive(on: .main)` (`docs/architecture-plan.md` §10).
    private func expectVisibleGames(_ viewModel: CreatorProfileViewModel, toEqual gameIDs: [String]) async {
        if viewModel.visibleGames.map(\.gameID) == gameIDs { return }
        let expectation = XCTestExpectation(description: "visibleGames == \(gameIDs)")
        let cancellable = viewModel.$visibleGames.sink { games in
            if games.map(\.gameID) == gameIDs {
                expectation.fulfill()
            }
        }
        await fulfillment(of: [expectation], timeout: 1)
        cancellable.cancel()
    }

    /// A game reported (not blocked) elsewhere must stay hidden on the creator's own page too —
    /// a filter that only checked `blockedCreatorIDs` would miss this (`docs/architecture-plan.md` §7).
    func test_visibleGames_excludesReportedGame_keepsOthersVisible() async throws {
        let moderationStore = ModerationStore(userDefaults: userDefaults)
        let (viewModel, repository) = makeViewModel(
            creatorID: "creator_1",
            items: [("game_0000", "creator_1"), ("game_0007", "creator_1")],
            moderationStore: moderationStore
        )

        try await repository.loadNextPage()
        await expectVisibleGames(viewModel, toEqual: ["game_0000", "game_0007"])

        moderationStore.report(gameID: "game_0000")
        await expectVisibleGames(viewModel, toEqual: ["game_0007"])
    }

    /// Passing `blockedCreatorIDs` through is free and correct even though the feed normally
    /// can't navigate to an already-blocked creator's page.
    func test_visibleGames_excludesAllGames_whenCreatorIsBlocked() async throws {
        let moderationStore = ModerationStore(userDefaults: userDefaults)
        let (viewModel, repository) = makeViewModel(
            creatorID: "creator_1",
            items: [("game_0000", "creator_1"), ("game_0007", "creator_1")],
            moderationStore: moderationStore
        )

        try await repository.loadNextPage()
        await expectVisibleGames(viewModel, toEqual: ["game_0000", "game_0007"])

        moderationStore.block(creatorID: "creator_1")
        await expectVisibleGames(viewModel, toEqual: [])
    }

    /// Block writes into `ModerationStore`, fires the toast and the pop-back-to-feed event, and
    /// is idempotent under a rapid double-tap.
    func test_block_writesToModerationStore_firesToastAndDidBlockEventOnce() {
        let moderationStore = ModerationStore(userDefaults: userDefaults)
        let (viewModel, _) = makeViewModel(
            creatorID: "creator_1",
            items: [],
            moderationStore: moderationStore
        )

        var toastMessages: [ToastMessage] = []
        var didBlockCount = 0
        let toastCancellable = viewModel.toastEvents.sink { toastMessages.append($0) }
        let didBlockCancellable = viewModel.didBlockCreator.sink { didBlockCount += 1 }

        viewModel.block()
        viewModel.block()

        XCTAssertEqual(moderationStore.blockedCreatorIDs, ["creator_1"])
        XCTAssertEqual(toastMessages, [ToastMessage(text: "Blocked Creator Name")])
        XCTAssertEqual(didBlockCount, 1)
        toastCancellable.cancel()
        didBlockCancellable.cancel()
    }
}
