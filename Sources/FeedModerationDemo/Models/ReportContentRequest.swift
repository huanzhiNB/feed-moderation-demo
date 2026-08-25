/// `POST /api/report/content/v1/reportContent` request body.
struct ReportContentRequest: Encodable {
    let gameID: String
    let reason: String

    private enum CodingKeys: String, CodingKey {
        case gameID = "game_id"
        case reason
    }
}
