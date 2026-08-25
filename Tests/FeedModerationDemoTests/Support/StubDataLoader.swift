import Foundation
@testable import FeedModerationDemo

/// Shared `URLDataLoading` stub for tests — returns fixed data/status for any request and
/// records the last request sent, so POST bodies can be asserted on.
final class StubDataLoader: URLDataLoading {
    private let data: Data
    private let statusCode: Int
    private(set) var lastRequest: URLRequest?

    init(data: Data, statusCode: Int = 200) {
        self.data = data
        self.statusCode = statusCode
    }

    func data(from url: URL) async throws -> (Data, URLResponse) {
        lastRequest = URLRequest(url: url)
        return (data, makeResponse(for: url))
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request
        guard let url = request.url else {
            preconditionFailure("StubDataLoader requires a request with a URL")
        }
        return (data, makeResponse(for: url))
    }

    private func makeResponse(for url: URL) -> URLResponse {
        guard let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil) else {
            preconditionFailure("Failed to construct a stub HTTPURLResponse")
        }
        return response
    }
}
