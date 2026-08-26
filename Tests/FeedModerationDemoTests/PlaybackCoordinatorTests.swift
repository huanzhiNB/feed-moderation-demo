import XCTest
@testable import FeedModerationDemo

final class PlaybackCoordinatorTests: XCTestCase {
    func test_settled_fromNilPrevious_playsOnly() {
        let coordinator = PlaybackCoordinator()

        let result = coordinator.settled(on: "game_1")

        XCTAssertEqual(result.toPlay, "game_1")
        XCTAssertNil(result.toPause)
        XCTAssertEqual(coordinator.currentlyPlayingID, "game_1")
    }

    func test_settled_withDifferentID_pausesOldAndPlaysNew() {
        let coordinator = PlaybackCoordinator()
        _ = coordinator.settled(on: "game_1")

        let result = coordinator.settled(on: "game_2")

        XCTAssertEqual(result.toPlay, "game_2")
        XCTAssertEqual(result.toPause, "game_1")
        XCTAssertEqual(coordinator.currentlyPlayingID, "game_2")
    }

    func test_settled_withSameID_isNoOp() {
        let coordinator = PlaybackCoordinator()
        _ = coordinator.settled(on: "game_1")

        let result = coordinator.settled(on: "game_1")

        XCTAssertNil(result.toPlay)
        XCTAssertNil(result.toPause)
        XCTAssertEqual(coordinator.currentlyPlayingID, "game_1")
    }

    func test_settled_toNil_pausesOnlyNothingPlays() {
        let coordinator = PlaybackCoordinator()
        _ = coordinator.settled(on: "game_1")

        let result = coordinator.settled(on: nil)

        XCTAssertNil(result.toPlay)
        XCTAssertEqual(result.toPause, "game_1")
        XCTAssertNil(coordinator.currentlyPlayingID)
    }

    func test_settled_fromNilToNil_isNoOp() {
        let coordinator = PlaybackCoordinator()

        let result = coordinator.settled(on: nil)

        XCTAssertNil(result.toPlay)
        XCTAssertNil(result.toPause)
        XCTAssertNil(coordinator.currentlyPlayingID)
    }

    func test_settled_repeatedNilAfterAlreadyNil_isNoOp() {
        let coordinator = PlaybackCoordinator()
        _ = coordinator.settled(on: "game_1")
        _ = coordinator.settled(on: nil)

        let result = coordinator.settled(on: nil)

        XCTAssertNil(result.toPlay)
        XCTAssertNil(result.toPause)
        XCTAssertNil(coordinator.currentlyPlayingID)
    }

    func test_settled_sequentialDistinctIDs_eachTransitionIsSelfConsistent() {
        let coordinator = PlaybackCoordinator()

        let first = coordinator.settled(on: "game_1")
        XCTAssertEqual(first.toPlay, "game_1")
        XCTAssertNil(first.toPause)

        let second = coordinator.settled(on: "game_2")
        XCTAssertEqual(second.toPlay, "game_2")
        XCTAssertEqual(second.toPause, "game_1")

        let third = coordinator.settled(on: "game_3")
        XCTAssertEqual(third.toPlay, "game_3")
        XCTAssertEqual(third.toPause, "game_2")

        XCTAssertEqual(coordinator.currentlyPlayingID, "game_3")
    }
}
