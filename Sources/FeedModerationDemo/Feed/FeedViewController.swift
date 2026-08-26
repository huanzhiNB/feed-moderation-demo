import Combine
import UIKit

/// Vertical, one-item-per-screen, snap-scrolling feed. Snapshots are driven exclusively by
/// `FeedViewModel.visibleItems` emissions — Report/Block never remove a collection view item
/// by hand (`ARCHITECTURE.md` §2/§3).
final class FeedViewController: UIViewController {
    private enum Section {
        case main
    }

    private let viewModel: FeedViewModel
    private let router: FeedRouter

    private let collectionView: UICollectionView
    private lazy var dataSource = makeDataSource()
    private var itemsByID: [String: FeedItem] = [:]

    private var cancellables = Set<AnyCancellable>()

    init(viewModel: FeedViewModel, router: FeedRouter) {
        self.viewModel = viewModel
        self.router = router

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
                self?.applySnapshot(for: items)
            }
            .store(in: &cancellables)

        viewModel.toastEvents
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                self?.showToast(message)
            }
            .store(in: &cancellables)
    }

    private func applySnapshot(for items: [FeedItem]) {
        itemsByID = Dictionary(uniqueKeysWithValues: items.map { ($0.gameID, $0) })

        var snapshot = NSDiffableDataSourceSnapshot<Section, String>()
        snapshot.appendSections([.main])
        snapshot.appendItems(items.map(\.gameID), toSection: .main)
        dataSource.apply(snapshot, animatingDifferences: true)
    }

    private func showToast(_ message: ToastMessage) {
        ToastView(text: message.text).show(in: view)
    }
}

extension FeedViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        viewModel.loadNextPageIfNeeded(displayingIndex: indexPath.item)
    }
}
