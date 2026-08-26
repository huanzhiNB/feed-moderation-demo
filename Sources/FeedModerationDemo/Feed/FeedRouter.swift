import UIKit

/// Feed-domain navigation (`docs/rules/ARCHITECTURE.md`: Router, not Coordinator — this owns no
/// `UINavigationController` lifecycle and exposes no `start()`, it only pushes onto one it's
/// given).
final class FeedRouter {
    private weak var navigationController: UINavigationController?
    private let apiClient: APIClient
    private let moderationStore: ModerationStore

    init(navigationController: UINavigationController, apiClient: APIClient, moderationStore: ModerationStore) {
        self.navigationController = navigationController
        self.apiClient = apiClient
        self.moderationStore = moderationStore
    }

    func showCreatorProfile(creatorID: String, creatorName: String) {
        let gamesRepository = CreatorGamesRepository(apiClient: apiClient, userID: creatorID)
        let viewModel = CreatorProfileViewModel(
            creatorID: creatorID,
            creatorName: creatorName,
            gamesRepository: gamesRepository,
            moderationStore: moderationStore,
            apiClient: apiClient
        )
        let viewController = CreatorProfileViewController(viewModel: viewModel)
        navigationController?.pushViewController(viewController, animated: true)
    }
}
