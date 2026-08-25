import XCTest
@testable import FeedModerationDemo

private struct StubDataLoader: URLDataLoading {
    let data: Data
    let response: URLResponse

    func data(from url: URL) async throws -> (Data, URLResponse) {
        (data, response)
    }
}

final class HealthCheckClientTests: XCTestCase {
    func testCheckHealthReturnsTrueForOkResponse() async {
        let url = URL(string: "http://127.0.0.1:8787/health")!
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        let loader = StubDataLoader(data: Data(#"{"ok": true}"#.utf8), response: response)
        let client = HealthCheckClient(urlSession: loader)

        let isReachable = await client.checkHealth()

        XCTAssertTrue(isReachable)
    }

    func testCheckHealthReturnsFalseForOkFieldFalse() async {
        let url = URL(string: "http://127.0.0.1:8787/health")!
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        let loader = StubDataLoader(data: Data(#"{"ok": false}"#.utf8), response: response)
        let client = HealthCheckClient(urlSession: loader)

        let isReachable = await client.checkHealth()

        XCTAssertFalse(isReachable)
    }

    func testCheckHealthReturnsFalseForServerErrorStatus() async {
        let url = URL(string: "http://127.0.0.1:8787/health")!
        let response = HTTPURLResponse(url: url, statusCode: 500, httpVersion: nil, headerFields: nil)!
        let loader = StubDataLoader(data: Data(#"{"ok": true}"#.utf8), response: response)
        let client = HealthCheckClient(urlSession: loader)

        let isReachable = await client.checkHealth()

        XCTAssertFalse(isReachable)
    }
}
