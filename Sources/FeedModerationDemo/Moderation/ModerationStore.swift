import Combine
import Foundation

/// Owns the two moderation sets and nothing else — no UIKit, no feed/network knowledge. The
/// feed and creator page must share one injected instance so a block/report is visible
/// everywhere (see `ARCHITECTURE.md`).
final class ModerationStore {
    @Published private(set) var blockedCreatorIDs: Set<String>
    @Published private(set) var reportedGameIDs: Set<String>

    private let userDefaults: UserDefaults

    private static let blockedCreatorIDsKey = "moderation.blockedCreatorIDs"
    private static let reportedGameIDsKey = "moderation.reportedGameIDs"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.blockedCreatorIDs = Set(userDefaults.stringArray(forKey: Self.blockedCreatorIDsKey) ?? [])
        self.reportedGameIDs = Set(userDefaults.stringArray(forKey: Self.reportedGameIDsKey) ?? [])
    }

    func block(creatorID: String) {
        guard blockedCreatorIDs.insert(creatorID).inserted else { return }
        userDefaults.set(Array(blockedCreatorIDs), forKey: Self.blockedCreatorIDsKey)
    }

    func report(gameID: String) {
        guard reportedGameIDs.insert(gameID).inserted else { return }
        userDefaults.set(Array(reportedGameIDs), forKey: Self.reportedGameIDsKey)
    }
}
