import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)

        let apiClient = APIClient()
        let moderationStore = ModerationStore()
        let feedRepository = FeedRepository(apiClient: apiClient)
        let feedViewModel = FeedViewModel(
            feedRepository: feedRepository,
            moderationStore: moderationStore,
            apiClient: apiClient
        )

        let navigationController = UINavigationController()
        let feedRouter = FeedRouter(
            navigationController: navigationController,
            apiClient: apiClient,
            moderationStore: moderationStore
        )
        // Swap this for the prefetch-window latency experiment
        // (docs/prefetch-window-latency-results.md) — leave at `.default` otherwise.
        let feedViewController = FeedViewController(
            viewModel: feedViewModel,
            router: feedRouter,
            prefetchWindow: .default
        )
        navigationController.viewControllers = [feedViewController]

        window.rootViewController = navigationController
        window.makeKeyAndVisible()
        self.window = window
    }
}
