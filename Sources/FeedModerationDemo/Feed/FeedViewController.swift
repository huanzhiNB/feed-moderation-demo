import Combine
import UIKit

/// How many neighbors of the settled item stay resident in the `WebViewPool`. Default is
/// "settled ± 1" (`docs/architecture-plan.md` §5) — the shipped behavior. Injectable so the
/// window size can be swapped for the fixed swipe-speed latency protocol in
/// `docs/prefetch-window-latency-results.md` without touching call sites; leave it at
/// `.default` for the actual submission.
struct PrefetchWindow {
    let behind: Int
    let ahead: Int

    static let `default` = PrefetchWindow(behind: 1, ahead: 1)

    fileprivate var slotCount: Int { behind + ahead + 1 }
}

/// Vertical, one-item-per-screen, snap-scrolling feed. Snapshots are driven exclusively by
/// `FeedViewModel.visibleItems` emissions — Report/Block never remove a collection view item
/// by hand (`docs/architecture-plan.md` §2/§3).
final class FeedViewController: UIViewController {
    private enum Section {
        case main
    }

    private let viewModel: FeedViewModel
    private let router: FeedRouter

    private let collectionView: UICollectionView
    private lazy var dataSource = makeDataSource()
    private var itemsByID: [String: FeedItem] = [:]

    private let webViewPool: WebViewPool
    private let prefetchWindow: PrefetchWindow
    private let playbackCoordinator = PlaybackCoordinator()

    private var cancellables = Set<AnyCancellable>()

    init(viewModel: FeedViewModel, router: FeedRouter, prefetchWindow: PrefetchWindow = .default) {
        self.viewModel = viewModel
        self.router = router
        self.prefetchWindow = prefetchWindow
        self.webViewPool = WebViewPool(slotCount: prefetchWindow.slotCount)

        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        webViewPool.delegate = self
        setUpCollectionView()
        bindViewModel()
        viewModel.loadInitialPageIfNeeded()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout {
            layout.itemSize = collectionView.bounds.size
        }
    }

    private func setUpCollectionView() {
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.isPagingEnabled = true
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.backgroundColor = .systemBackground
        collectionView.register(FeedItemCell.self, forCellWithReuseIdentifier: FeedItemCell.reuseIdentifier)
        collectionView.delegate = self
        view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    private func makeDataSource() -> UICollectionViewDiffableDataSource<Section, String> {
        UICollectionViewDiffableDataSource<Section, String>(
            collectionView: collectionView
        ) { [weak self] collectionView, indexPath, gameID in
            guard
                let self,
                let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: FeedItemCell.reuseIdentifier,
                    for: indexPath
                ) as? FeedItemCell,
                let item = self.itemsByID[gameID]
            else {
                return UICollectionViewCell()
            }

            cell.configure(
                with: item,
                onReport: { [weak self] in self?.viewModel.report(gameID: item.gameID) },
                onBlock: { [weak self] in
                    self?.viewModel.block(creatorID: item.creatorID, creatorName: item.creatorName)
                },
                onCreatorTapped: { [weak self] in
                    self?.router.showCreatorProfile(creatorID: item.creatorID, creatorName: item.creatorName)
                }
            )
            return cell
        }
    }

    private func bindViewModel() {
        viewModel.$visibleItems
            .sink { [weak self] items in
                guard let self else { return }
                // Reconcile playback only when the currently-playing item actually dropped
                // out of the list, or nothing has ever played yet (cold-start autoplay) —
                // not on every snapshot change, or an unrelated page-fetch mid-flick would
                // hijack playback onto whatever's transiently centered (`docs/architecture-plan.md` §6).
                let stillPresent = self.playbackCoordinator.currentlyPlayingID
                    .map { id in items.contains { $0.gameID == id } }
                let needsReconciliation = stillPresent == false || (stillPresent == nil && !items.isEmpty)
                self.applySnapshot(for: items) {
                    if needsReconciliation {
                        self.handleSettle()
                    }
                }
            }
            .store(in: &cancellables)

        viewModel.toastEvents
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                self?.showToast(message)
            }
            .store(in: &cancellables)
    }

    private func applySnapshot(for items: [FeedItem], completion: (() -> Void)? = nil) {
        itemsByID = Dictionary(uniqueKeysWithValues: items.map { ($0.gameID, $0) })

        var snapshot = NSDiffableDataSourceSnapshot<Section, String>()
        snapshot.appendSections([.main])
        snapshot.appendItems(items.map(\.gameID), toSection: .main)
        dataSource.apply(snapshot, animatingDifferences: true, completion: completion)
    }

    private func showToast(_ message: ToastMessage) {
        ToastView(text: message.text).show(in: view)
    }

    private func cell(for gameID: String) -> FeedItemCell? {
        guard let indexPath = dataSource.indexPath(for: gameID) else { return nil }
        return collectionView.cellForItem(at: indexPath) as? FeedItemCell
    }

    /// The single call site for `sekaiPlay`/`sekaiPause`, invoked from every settle trigger
    /// (`docs/architecture-plan.md` §6) and from `visibleItems` reconciliation above. Resolving to "no
    /// centered item" (empty list, or a snapshot mid-transition) is a normal outcome — it
    /// just pauses without playing anything, never a crash.
    private func handleSettle() {
        let centerPoint = CGPoint(x: collectionView.bounds.midX, y: collectionView.bounds.midY)
        let centeredIndexPath = collectionView.indexPathForItem(at: centerPoint)
        let centeredGameID = centeredIndexPath.flatMap { dataSource.itemIdentifier(for: $0) }

        let (toPlay, toPause) = playbackCoordinator.settled(on: centeredGameID)
        if let toPause {
            cell(for: toPause)?.pause()
        }
        if let toPlay {
            cell(for: toPlay)?.play()
        }

        if let centeredIndexPath {
            reconcileWindow(around: centeredIndexPath.item)
        }
    }

    /// Makes the pool's residency exactly match `prefetchWindow` around `index` (`{index -
    /// prefetchWindow.behind, ..., index + prefetchWindow.ahead}`, clipped to bounds — default
    /// is "settled ± 1", `docs/architecture-plan.md` §5). Called both from `willDisplay` (so a
    /// cell entering the screen gets a slot even before any settle has happened yet — cold
    /// start, or a cell reused far from the last window) and from `handleSettle` (so the
    /// settled item's neighbors start loading the moment you land, not only once you start
    /// scrolling toward them). Calling it twice for the same index is a no-op —
    /// `WebViewPool.reconcile` only touches what's actually changed.
    private func reconcileWindow(around index: Int) {
        let range = (index - prefetchWindow.behind)...(index + prefetchWindow.ahead)
        let desired = range.compactMap { item -> (gameID: String, url: URL)? in
            guard item >= 0 else { return nil }
            guard let gameID = dataSource.itemIdentifier(for: IndexPath(item: item, section: 0)) else { return nil }
            guard let feedItem = itemsByID[gameID] else { return nil }
            return (gameID, feedItem.gameURL)
        }
        webViewPool.reconcile(desired: desired)
    }
}

extension FeedViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        viewModel.loadNextPageIfNeeded(displayingIndex: indexPath.item)

        guard let feedCell = cell as? FeedItemCell, let gameID = dataSource.itemIdentifier(for: indexPath) else { return }

        reconcileWindow(around: indexPath.item)
        guard let webView = webViewPool.webView(for: gameID) else { return }
        feedCell.attach(webView: webView, gameID: gameID, isReady: webViewPool.isReady(for: gameID))
        if gameID == playbackCoordinator.currentlyPlayingID {
            feedCell.play()
        }
    }

    func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard let feedCell = cell as? FeedItemCell else { return }
        feedCell.pause()
        feedCell.detach()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            handleSettle()
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        handleSettle()
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        handleSettle()
    }
}

extension FeedViewController: WebViewPoolDelegate {
    func webViewPool(_ pool: WebViewPool, didFinishLoadingGameID gameID: String) {
        cell(for: gameID)?.markNavigationFinished(for: gameID)
        if gameID == playbackCoordinator.currentlyPlayingID {
            cell(for: gameID)?.play()
        }
    }

    func webViewPool(_ pool: WebViewPool, didFailLoadingGameID gameID: String) {
        cell(for: gameID)?.markNavigationFailed(for: gameID)
    }
}
