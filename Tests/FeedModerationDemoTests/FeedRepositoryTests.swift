import XCTest
@testable import FeedModerationDemo

final class FeedRepositoryTests: XCTestCase {
    private let baseURL = URL(string: "http://127.0.0.1:8787")!

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

    private func makeRepository(loader: StubDataLoader) -> FeedRepository {
        FeedRepository(apiClient: APIClient(baseURL: baseURL, urlSession: loader))
    }

    func test_loadNextPage_appendsFetchedItems_andIncrementsCursor() async throws {
        let loader = StubDataLoader(responses: [
            (feedJSON([("game_0000", "creator_1")]), 200),
            (feedJSON([("game_0001", "creator_1")]), 200),
        ])
        let repository = makeRepository(loader: loader)

        try await repository.loadNextPage()
        try await repository.loadNextPage()

        XCTAssertEqual(repository.pages.map(\.gameID), ["game_0000", "game_0001"])
        let refreshValues = loader.requests.compactMap { request in
            request.url
                .flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems }?
                .first(where: { $0.name == "refresh" })?.value
        }
        XCTAssertEqual(refreshValues, ["0", "1"])
    }

    func test_loadNextPage_dedupesByGameID() async throws {
        let loader = StubDataLoader(responses: [
            (feedJSON([("game_0000", "creator_1")]), 200),
            (feedJSON([("game_0000", "creator_1"), ("game_0001", "creator_1")]), 200),
        ])
        let repository = makeRepository(loader: loader)

        try await repository.loadNextPage()
        try await repository.loadNextPage()

        XCTAssertEqual(repository.pages.map(\.gameID), ["game_0000", "game_0001"])
    }

    func test_loadNextPage_emptyResponse_marksExhausted_andStopsFurtherFetches() async throws {
        let loader = StubDataLoader(data: feedJSON([]))
        let repository = makeRepository(loader: loader)

        try await repository.loadNextPage()
        XCTAssertTrue(repository.isExhausted)

        try await repository.loadNextPage()
        XCTAssertEqual(loader.requests.count, 1)
    }

    func test_loadNextPage_resetsIsLoading_afterCompletion() async throws {
        let loader = StubDataLoader(data: feedJSON([("game_0000", "creator_1")]))
        let repository = makeRepository(loader: loader)

        try await repository.loadNextPage()

        XCTAssertFalse(repository.isLoading)
    }

    /// Regression guard for the `willDisplay`-triggered pagination race: overlapping calls to
    /// `loadNextPage()` (as would come from separate `Task`s spawned per cell during a fast
    /// flick) must not both pass the `isLoading` guard. `FeedRepository` is `@MainActor`
    /// so this is deterministic — the artificial delay just makes the overlap unmissable.
    func test_loadNextPage_calledConcurrently_onlyFetchesOnce() async throws {
        let loader = StubDataLoader(
            data: feedJSON([("game_0000", "creator_1")]),
            delayNanoseconds: 20_000_000
        )
        let repository = makeRepository(loader: loader)

        async let first: () = repository.loadNextPage()
        async let second: () = repository.loadNextPage()
        _ = try await (first, second)

        XCTAssertEqual(loader.requests.count, 1)
        XCTAssertEqual(repository.pages.map(\.gameID), ["game_0000"])
        XCTAssertFalse(repository.isLoading)
    }
}
