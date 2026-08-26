import UIKit

/// Feed-domain navigation (`ARCHITECTURE.md`: Router, not Coordinator — this owns no
/// `UINavigationController` lifecycle and exposes no `start()`, it only pushes onto one it's
/// given).
final class FeedRouter {
    private weak var navigationController: UINavigationController?

    init(navigationController: UINavigationController) {
        self.navigationController = navigationController
    }

    func showCreatorProfile(creatorID: String, creatorName: String) {
        let placeholder = CreatorProfilePlaceholderViewController(creatorID: creatorID, creatorName: creatorName)
        navigationController?.pushViewController(placeholder, animated: true)
    }
}
