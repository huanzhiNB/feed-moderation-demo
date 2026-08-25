import Foundation

/// Envelope shape used by every endpoint except `/game/feed`, which returns a bare array.
struct APIEnvelope<T: Decodable>: Decodable {
    let code: Int
    let message: String
    let data: T?
}

enum APIError: Error, Equatable {
    case invalidResponse
    case httpError(statusCode: Int)
    case apiError(code: Int, message: String)
}

final class APIClient {
    private static let defaultBaseURL: URL = {
        guard let url = URL(string: "http://127.0.0.1:8787") else {
            preconditionFailure("Invalid mock server base URL")
        }
        return url
    }()

    private let baseURL: URL
    private let urlSession: URLDataLoading
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(baseURL: URL = APIClient.defaultBaseURL, urlSession: URLDataLoading = URLSession.shared) {
        self.baseURL = baseURL
        self.urlSession = urlSession
    }

    // MARK: Feed — bare array, no envelope

    func fetchFeed(limit: Int, refresh: Int) async throws -> [FeedItem] {
        let url = try makeURL(
            path: "game/feed",
            queryItems: [
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "refresh", value: String(refresh)),
            ]
        )
        let data = try await getData(from: url)
        return try decoder.decode([FeedItem].self, from: data)
    }

    // MARK: Creator profile

    func fetchUserProfile(userID: String) async throws -> UserProfile {
        let url = try makeURL(
            path: "api/user/info/v1/userProfile",
            queryItems: [URLQueryItem(name: "user_id", value: userID)]
        )
        let data = try await getData(from: url)
        return try decodeEnvelope(UserProfile.self, from: data)
    }

    // MARK: Creator's games — wrapped, paged

    func fetchUserGames(userID: String, page: Int, size: Int) async throws -> UserGamesPage {
        let url = try makeURL(
            path: "api/game/list/v1/userGames",
            queryItems: [
                URLQueryItem(name: "user_id", value: userID),
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "size", value: String(size)),
            ]
        )
        let data = try await getData(from: url)
        return try decodeEnvelope(UserGamesPage.self, from: data)
    }

    // MARK: Moderation

    func blockUser(userID: String) async throws {
        let url = try makeURL(path: "api/user/block/v1/blockUser", queryItems: [])
        let data = try await postData(to: url, body: BlockUserRequest(userID: userID))
        try validateStatus(data)
    }

    func reportContent(gameID: String, reason: String) async throws {
        let url = try makeURL(path: "api/report/content/v1/reportContent", queryItems: [])
        let data = try await postData(to: url, body: ReportContentRequest(gameID: gameID, reason: reason))
        try validateStatus(data)
    }

    // MARK: URL construction

    private func makeURL(path: String, queryItems: [URLQueryItem]) throws -> URL {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components?.url else {
            throw APIError.invalidResponse
        }
        return url
    }

    // MARK: Transport

    private func getData(from url: URL) async throws -> Data {
        let (data, response) = try await urlSession.data(from: url)
        try validate(response)
        return data
    }

    private func postData(to url: URL, body: some Encodable) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        let (data, response) = try await urlSession.data(for: request)
        try validate(response)
        return data
    }

    private func validate(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.httpError(statusCode: httpResponse.statusCode)
        }
    }

    // MARK: Envelope decoding

    private func decodeEnvelope<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let envelope = try decoder.decode(APIEnvelope<T>.self, from: data)
        guard envelope.code == 0 else {
            throw APIError.apiError(code: envelope.code, message: envelope.message)
        }
        guard let value = envelope.data else {
            throw APIError.invalidResponse
        }
        return value
    }

    /// For endpoints where only `code`/`message` matter — blockUser/reportContent's `data`
    /// payload is not something callers need.
    private func validateStatus(_ data: Data) throws {
        struct StatusEnvelope: Decodable {
            let code: Int
            let message: String
        }
        let envelope = try decoder.decode(StatusEnvelope.self, from: data)
        guard envelope.code == 0 else {
            throw APIError.apiError(code: envelope.code, message: envelope.message)
        }
    }
}
