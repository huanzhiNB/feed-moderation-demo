import XCTest
@testable import FeedModerationDemo

final class HealthCheckClientTests: XCTestCase {
    func testCheckHealthReturnsTrueForOkResponse() async {
        let loader = StubDataLoader(data: Data(#"{"ok": true}"#.utf8), statusCode: 200)
        let client = HealthCheckClient(urlSession: loader)

        let isReachable = await client.checkHealth()

        XCTAssertTrue(isReachable)
    }

    func testCheckHealthReturnsFalseForOkFieldFalse() async {
        let loader = StubDataLoader(data: Data(#"{"ok": false}"#.utf8), statusCode: 200)
        let client = HealthCheckClient(urlSession: loader)

        let isReachable = await client.checkHealth()

        XCTAssertFalse(isReachable)
    }

    func testCheckHealthReturnsFalseForServerErrorStatus() async {
        let loader = StubDataLoader(data: Data(#"{"ok": true}"#.utf8), statusCode: 500)
        let client = HealthCheckClient(urlSession: loader)

        let isReachable = await client.checkHealth()

        XCTAssertFalse(isReachable)
    }
}
