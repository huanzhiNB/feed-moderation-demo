import Foundation
@testable import FeedModerationDemo

/// Shared `URLDataLoading` stub for tests — returns fixed data/status for any request and
/// records every request sent, so POST bodies and per-page query params can be asserted on.
/// Given multiple `responses`, each successive call returns the next one (clamped to the
/// last once exhausted) — needed to simulate a sequence of paginated fetches.
final class StubDataLoader: URLDataLoading {
    private let responses: [(data: Data, statusCode: Int)]
    private(set) var requests: [URLRequest] = []
    private var callCount = 0

    var lastRequest: URLRequest? { requests.last }

    init(data: Data, statusCode: Int = 200) {
        self.responses = [(data, statusCode)]
    }

    init(responses: [(data: Data, statusCode: Int)]) {
        self.responses = responses
    }

    func data(from url: URL) async throws -> (Data, URLResponse) {
        respond(to: URLRequest(url: url), url: url)
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        guard let url = request.url else {
            preconditionFailure("StubDataLoader requires a request with a URL")
        }
        return respond(to: request, url: url)
    }

    private func respond(to request: URLRequest, url: URL) -> (Data, URLResponse) {
        requests.append(request)
        let (data, statusCode) = responses[min(callCount, responses.count - 1)]
        callCount += 1
        return (data, makeResponse(for: url, statusCode: statusCode))
    }

    private func makeResponse(for url: URL, statusCode: Int) -> URLResponse {
        guard let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil) else {
            preconditionFailure("Failed to construct a stub HTTPURLResponse")
        }
        return response
    }
}
