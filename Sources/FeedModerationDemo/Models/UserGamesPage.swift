import Foundation

/// `GET /api/game/list/v1/userGames` — one page of a creator's sekais.
/// `hasMore` is authoritative from the server; do not re-derive it by inference.
struct UserGamesPage: Decodable {
    let list: [FeedItem]
    let page: Int
    let size: Int
    let hasMore: Bool

    private enum CodingKeys: String, CodingKey {
        case list
        case page
        case size
        case hasMore = "has_more"
    }
}
