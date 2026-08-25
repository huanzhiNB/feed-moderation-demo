import Foundation

struct HealthResponse: Decodable {
    let ok: Bool
}

final class HealthCheckClient {
    private static let defaultBaseURL: URL = {
        guard let url = URL(string: "http://127.0.0.1:8787") else {
            preconditionFailure("Invalid mock server base URL")
        }
        return url
    }()

    private let baseURL: URL
    private let urlSession: URLDataLoading

    init(baseURL: URL = HealthCheckClient.defaultBaseURL, urlSession: URLDataLoading = URLSession.shared) {
        self.baseURL = baseURL
        self.urlSession = urlSession
    }

    func checkHealth() async -> Bool {
        let url = baseURL.appendingPathComponent("health")
        do {
            let (data, response) = try await urlSession.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return false
            }
            let decoded = try JSONDecoder().decode(HealthResponse.self, from: data)
            return decoded.ok
        } catch {
            return false
        }
    }
}
