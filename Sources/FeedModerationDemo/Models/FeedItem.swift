import Foundation

/// One sekai, as served by both `GET /game/feed` (bare array) and `GET .../userGames`
/// (wrapped, paged) — the same `game_id`s appear in both places.
struct FeedItem: Decodable, Hashable {
    let gameID: String
    let title: String
    let gameURL: URL
    let coverURL: URL
    let creatorID: String
    let creatorName: String
    let likeCount: Int

    private enum CodingKeys: String, CodingKey {
        case gameID = "game_id"
        case title
        case gameURL = "game_url"
        case coverURL = "cover_url"
        case creatorID = "creator_id"
        case creatorName = "creator_name"
        case likeCount = "like_count"
    }
}
