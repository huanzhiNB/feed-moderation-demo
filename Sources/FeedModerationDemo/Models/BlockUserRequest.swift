/// `POST /api/user/block/v1/blockUser` request body.
struct BlockUserRequest: Encodable {
    let userID: String

    private enum CodingKeys: String, CodingKey {
        case userID = "user_id"
    }
}
