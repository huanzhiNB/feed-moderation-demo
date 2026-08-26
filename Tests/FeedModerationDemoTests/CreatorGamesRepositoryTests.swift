import XCTest
@testable import FeedModerationDemo

final class CreatorGamesRepositoryTests: XCTestCase {
    private let baseURL = URL(string: "http://127.0.0.1:8787")!
    private let userID = "creator_1"

    private func userGamesJSON(
        _ items: [(gameID: String, creatorID: String)],
        page: Int,
        hasMore: Bool
    ) -> Data {
        let entries = items.map { item in
            """
            {"game_id": "\(item.gameID)", "title": "T", \
            "game_url": "http://127.0.0.1:8787/content/\(item.gameID)", \
            "cover_url": "http://127.0.0.1:8787/avatar/\(item.creatorID)", \
            "creator_id": "\(item.creatorID)", "creator_name": "C", "like_count": 0}
            """
        }.joined(separator: ",")
        let json = """
        {"code": 0, "message": "ok", "data": {"list": [\(entries)], "page": \(page), "size": 10, "has_more": \(hasMore)}}
        """
        return Data(json.utf8)
    }

    private func makeRepository(loader: StubDataLoader) -> CreatorGamesRepository {
        CreatorGamesRepository(apiClient: APIClient(baseURL: baseURL, urlSession: loader), userID: userID)
    }

    func test_loadNextPage_appendsFetchedItems_andIncrementsPage() async throws {
        let loader = StubDataLoader(responses: [
            (userGamesJSON([("game_0000", userID)], page: 0, hasMore: true), 200),
            (userGamesJSON([("game_0007", userID)], page: 1, hasMore: true), 200),
        ])
        let repository = makeRepository(loader: loader)

        try await repository.loadNextPage()
        try await repository.loadNextPage()

        XCTAssertEqual(repository.items.map(\.gameID), ["game_0000", "game_0007"])
        let pageValues = loader.requests.compactMap { request in
            request.url
                .flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems }?
                .first(where: { $0.name == "page" })?.value
        }
        XCTAssertEqual(pageValues, ["0", "1"])
    }

    func test_loadNextPage_dedupesByGameID() async throws {
        let loader = StubDataLoader(responses: [
            (userGamesJSON([("game_0000", userID)], page: 0, hasMore: true), 200),
            (userGamesJSON([("game_0000", userID), ("game_0007", userID)], page: 1, hasMore: false), 200),
        ])
        let repository = makeRepository(loader: loader)

        try await repository.loadNextPage()
        try await repository.loadNextPage()

        XCTAssertEqual(repository.items.map(\.gameID), ["game_0000", "game_0007"])
    }

    /// `userGames` gives an authoritative `has_more` — exhaustion must come from that field,
    /// not from inferring it off an empty page like the feed has to (`docs/architecture-plan.md` §7).
    func test_loadNextPage_hasMoreFalse_stopsFurtherFetches() async throws {
        let loader = StubDataLoader(responses: [
            (userGamesJSON([("game_0000", userID)], page: 0, hasMore: false), 200),
        ])
        let repository = makeRepository(loader: loader)

        try await repository.loadNextPage()
        XCTAssertFalse(repository.hasMore)
        XCTAssertEqual(repository.items.map(\.gameID), ["game_0000"])

        try await repository.loadNextPage()
        XCTAssertEqual(loader.requests.count, 1)
    }

    /// Same `willDisplay`-triggered pagination race as `FeedRepository` — see
    /// `FeedRepositoryTests.test_loadNextPage_calledConcurrently_onlyFetchesOnce`.
    func test_loadNextPage_calledConcurrently_onlyFetchesOnce() async throws {
        let loader = StubDataLoader(
            data: userGamesJSON([("game_0000", userID)], page: 0, hasMore: true),
            delayNanoseconds: 20_000_000
        )
        let repository = makeRepository(loader: loader)

        async let first: () = repository.loadNextPage()
        async let second: () = repository.loadNextPage()
        _ = try await (first, second)

        XCTAssertEqual(loader.requests.count, 1)
        XCTAssertEqual(repository.items.map(\.gameID), ["game_0000"])
        XCTAssertFalse(repository.isLoading)
    }
}
