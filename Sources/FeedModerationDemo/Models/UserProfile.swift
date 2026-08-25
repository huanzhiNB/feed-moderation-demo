import Foundation

/// `GET /api/user/info/v1/userProfile` — the creator page's profile section.
struct UserProfile: Decodable {
    let userID: String
    let nickName: String
    let avatar: URL
    let bio: String
    let followingCount: Int
    let followerCount: Int
    let likeCount: Int

    private enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case nickName = "nick_name"
        case avatar
        case bio
        case followingCount = "following_count"
        case followerCount = "follower_count"
        case likeCount = "like_count"
    }
}
