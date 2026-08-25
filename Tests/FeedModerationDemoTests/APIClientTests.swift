import XCTest
@testable import FeedModerationDemo

final class APIClientTests: XCTestCase {
    private let baseURL = URL(string: "http://127.0.0.1:8787")!

    func testFetchFeedDecodesBareArrayAndSendsExpectedQuery() async throws {
        let json = """
        [{"game_id": "game_0000", "title": "A", "game_url": "http://127.0.0.1:8787/content/game_0000",
          "cover_url": "http://127.0.0.1:8787/avatar/creator_1", "creator_id": "creator_1",
          "creator_name": "mejikoOV_80", "like_count": 7}]
        """
        let loader = StubDataLoader(data: Data(json.utf8), statusCode: 200)
        let client = APIClient(baseURL: baseURL, urlSession: loader)

        let items = try await client.fetchFeed(limit: 6, refresh: 1)

        XCTAssertEqual(items.map(\.gameID), ["game_0000"])
        let query = loader.lastRequest?.url.flatMap {
            URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems
        }
        XCTAssertEqual(query?.first(where: { $0.name == "limit" })?.value, "6")
        XCTAssertEqual(query?.first(where: { $0.name == "refresh" })?.value, "1")
    }

    func testFetchUserProfileThrowsAPIErrorOnNonZeroCode() async throws {
        let json = #"{"code": 50000, "message": "service unavailable", "data": null}"#
        let loader = StubDataLoader(data: Data(json.utf8), statusCode: 200)
        let client = APIClient(baseURL: baseURL, urlSession: loader)

        do {
            _ = try await client.fetchUserProfile(userID: "creator_1")
            XCTFail("Expected apiError to be thrown")
        } catch let error as APIError {
            XCTAssertEqual(error, .apiError(code: 50000, message: "service unavailable"))
        }
    }

    func testHTTPErrorStatusThrowsHTTPErrorRegardlessOfBody() async throws {
        let loader = StubDataLoader(data: Data(#"{"code": 0, "message": "ok", "data": null}"#.utf8), statusCode: 500)
        let client = APIClient(baseURL: baseURL, urlSession: loader)

        do {
            _ = try await client.fetchUserProfile(userID: "creator_1")
            XCTFail("Expected httpError to be thrown")
        } catch let error as APIError {
            XCTAssertEqual(error, .httpError(statusCode: 500))
        }
    }

    func testBlockUserSendsExpectedBodyAndSucceedsOnZeroCode() async throws {
        let loader = StubDataLoader(data: Data(#"{"code": 0, "message": "ok", "data": {"echo": {}}}"#.utf8))
        let client = APIClient(baseURL: baseURL, urlSession: loader)

        try await client.blockUser(userID: "creator_1")

        let sentBody = try XCTUnwrap(loader.lastRequest?.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: sentBody) as? [String: String])
        XCTAssertEqual(json["user_id"], "creator_1")
        XCTAssertEqual(loader.lastRequest?.httpMethod, "POST")
    }

    func testBlockUserThrowsOnNonZeroCode() async throws {
        let loader = StubDataLoader(data: Data(#"{"code": 50000, "message": "service unavailable", "data": null}"#.utf8))
        let client = APIClient(baseURL: baseURL, urlSession: loader)

        do {
            try await client.blockUser(userID: "creator_1")
            XCTFail("Expected apiError to be thrown")
        } catch let error as APIError {
            XCTAssertEqual(error, .apiError(code: 50000, message: "service unavailable"))
        }
    }

    func testReportContentSendsExpectedBody() async throws {
        let loader = StubDataLoader(data: Data(#"{"code": 0, "message": "ok", "data": {"echo": {}}}"#.utf8))
        let client = APIClient(baseURL: baseURL, urlSession: loader)

        try await client.reportContent(gameID: "game_0042", reason: "spam")

        let sentBody = try XCTUnwrap(loader.lastRequest?.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: sentBody) as? [String: String])
        XCTAssertEqual(json["game_id"], "game_0042")
        XCTAssertEqual(json["reason"], "spam")
    }

    func testFetchUserGamesUsesServerProvidedHasMore() async throws {
        let json = #"{"code": 0, "message": "ok", "data": {"list": [], "page": 2, "size": 2, "has_more": false}}"#
        let loader = StubDataLoader(data: Data(json.utf8))
        let client = APIClient(baseURL: baseURL, urlSession: loader)

        let page = try await client.fetchUserGames(userID: "creator_1", page: 2, size: 2)

        XCTAssertEqual(page.hasMore, false)
        XCTAssertEqual(page.page, 2)
    }
}
