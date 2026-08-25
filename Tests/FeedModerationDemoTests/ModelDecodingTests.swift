import XCTest
@testable import FeedModerationDemo

final class ModelDecodingTests: XCTestCase {
    func testFeedItemDecodesFromBareSnakeCaseJSON() throws {
        let json = """
        {
          "game_id": "game_0000",
          "title": "Lo-Fi Vibe Mixer",
          "game_url": "http://127.0.0.1:8787/content/game_0000",
          "cover_url": "http://127.0.0.1:8787/avatar/creator_1",
          "creator_id": "creator_1",
          "creator_name": "mejikoOV_80",
          "like_count": 7
        }
        """
        let item = try JSONDecoder().decode(FeedItem.self, from: Data(json.utf8))

        XCTAssertEqual(item.gameID, "game_0000")
        XCTAssertEqual(item.title, "Lo-Fi Vibe Mixer")
        XCTAssertEqual(item.gameURL, URL(string: "http://127.0.0.1:8787/content/game_0000"))
        XCTAssertEqual(item.creatorID, "creator_1")
        XCTAssertEqual(item.creatorName, "mejikoOV_80")
        XCTAssertEqual(item.likeCount, 7)
    }

    func testFeedFetchDecodesBareArray() throws {
        let json = """
        [
          {
            "game_id": "game_0000", "title": "A", "game_url": "http://127.0.0.1:8787/content/game_0000",
            "cover_url": "http://127.0.0.1:8787/avatar/creator_1", "creator_id": "creator_1",
            "creator_name": "mejikoOV_80", "like_count": 7
          },
          {
            "game_id": "game_0001", "title": "B", "game_url": "http://127.0.0.1:8787/content/game_0001",
            "cover_url": "http://127.0.0.1:8787/avatar/creator_2", "creator_id": "creator_2",
            "creator_name": "Dark Prince", "like_count": 20
          }
        ]
        """
        let items = try JSONDecoder().decode([FeedItem].self, from: Data(json.utf8))

        XCTAssertEqual(items.map(\.gameID), ["game_0000", "game_0001"])
    }

    func testUserProfileDecodesFromWrappedEnvelope() throws {
        let json = """
        {
          "code": 0,
          "message": "ok",
          "data": {
            "user_id": "creator_1",
            "nick_name": "mejikoOV_80",
            "avatar": "http://127.0.0.1:8787/avatar/creator_1",
            "bio": "lo-fi loops and small machines",
            "following_count": 10,
            "follower_count": 60,
            "like_count": 440
          }
        }
        """
        let envelope = try JSONDecoder().decode(APIEnvelope<UserProfile>.self, from: Data(json.utf8))

        XCTAssertEqual(envelope.code, 0)
        XCTAssertEqual(envelope.data?.userID, "creator_1")
        XCTAssertEqual(envelope.data?.nickName, "mejikoOV_80")
        XCTAssertEqual(envelope.data?.followingCount, 10)
    }

    func testUserGamesPageDecodesHasMoreTrue() throws {
        let json = """
        {
          "code": 0,
          "message": "ok",
          "data": {
            "list": [
              {
                "game_id": "game_0000", "title": "A", "game_url": "http://127.0.0.1:8787/content/game_0000",
                "cover_url": "http://127.0.0.1:8787/avatar/creator_1", "creator_id": "creator_1",
                "creator_name": "mejikoOV_80", "like_count": 7
              }
            ],
            "page": 0,
            "size": 2,
            "has_more": true
          }
        }
        """
        let envelope = try JSONDecoder().decode(APIEnvelope<UserGamesPage>.self, from: Data(json.utf8))

        XCTAssertEqual(envelope.data?.hasMore, true)
        XCTAssertEqual(envelope.data?.page, 0)
        XCTAssertEqual(envelope.data?.list.count, 1)
    }

    func testUserGamesPageDecodesHasMoreFalse() throws {
        let json = """
        {"code": 0, "message": "ok", "data": {"list": [], "page": 3, "size": 2, "has_more": false}}
        """
        let envelope = try JSONDecoder().decode(APIEnvelope<UserGamesPage>.self, from: Data(json.utf8))

        XCTAssertEqual(envelope.data?.hasMore, false)
    }

    func testEnvelopeDecodesNonZeroFailureCode() throws {
        let json = #"{"code": 50000, "message": "service unavailable", "data": null}"#
        let envelope = try JSONDecoder().decode(APIEnvelope<UserProfile>.self, from: Data(json.utf8))

        XCTAssertEqual(envelope.code, 50000)
        XCTAssertEqual(envelope.message, "service unavailable")
        XCTAssertNil(envelope.data)
    }
}
