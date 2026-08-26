import UIKit
import WebKit

/// Title, creator, Report, and Block, with a pooled `WKWebView` for the sekai content
/// underneath. The WebView is owned by `WebViewPool`; this cell only borrows it while
/// assigned (`ARCHITECTURE.md` §5) and is the sole place that gates `sekaiPlay()` on
/// navigation actually finishing.
final class FeedItemCell: UICollectionViewCell {
    static let reuseIdentifier = "FeedItemCell"

    private let titleLabel = UILabel()
    private let creatorButton = UIButton(type: .system)
    private let reportButton = UIButton(type: .system)
    private let blockButton = UIButton(type: .system)

    private var onReport: (() -> Void)?
    private var onBlock: (() -> Void)?
    private var onCreatorTapped: (() -> Void)?

    private(set) weak var webView: WKWebView?
    private(set) var assignedGameID: String?
    private var isNavigationFinished = false
    private var pendingPlay = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUpLayout()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        detach()
    }

    /// Cell entering the pool's window. `webView` is on loan from `WebViewPool` — inserted
    /// below the existing title/creator/Report/Block stack so those stay visible and
    /// tappable, and so a failed/blank load still shows sensible content. `isReady` reflects
    /// the pool's own load state at attach time: a pre-fetched settled±1 neighbor
    /// (`ARCHITECTURE.md` §5) may already have finished loading before this cell ever
    /// attached to it, so navigation-finished state must come from the pool, not always
    /// reset to false.
    func attach(webView: WKWebView, gameID: String, isReady: Bool) {
        self.webView = webView
        assignedGameID = gameID
        isNavigationFinished = isReady
        pendingPlay = false

        // A reused pool slot's WKWebView still visually shows the *previous* occupant's
        // last-rendered frame until this gameID's own load actually paints — hide it until
        // then so a cell never displays the wrong game's content, even briefly.
        webView.isHidden = !isReady

        webView.translatesAutoresizingMaskIntoConstraints = false
        contentView.insertSubview(webView, at: 0)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: contentView.topAnchor),
            webView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        ])
    }

    /// Cell exiting the pool's window (or being reused). Playback is stopped by the caller
    /// (`WebViewPool.release`) before this is called; this only detaches the borrowed view.
    func detach() {
        webView?.removeFromSuperview()
        webView = nil
        assignedGameID = nil
        isNavigationFinished = false
        pendingPlay = false
    }

    /// Gated on navigation having actually finished — `sekaiPlay` isn't defined until the
    /// page's own `<script>` has run. If not ready yet, defers until
    /// `markNavigationFinished` arrives for this same `gameID`.
    func play() {
        guard webView != nil else { return }
        guard isNavigationFinished else {
            pendingPlay = true
            return
        }
        webView?.evaluateJavaScript("window.sekaiPlay && window.sekaiPlay();")
    }

    func pause() {
        pendingPlay = false
        guard webView != nil else { return }
        webView?.evaluateJavaScript("window.sekaiPause && window.sekaiPause();")
    }

    /// `gameID` is guarded against the cell's *current* assignment — a late callback for a
    /// game this cell was reassigned away from must not act (`ARCHITECTURE.md` §5).
    func markNavigationFinished(for gameID: String) {
        guard gameID == assignedGameID else { return }
        isNavigationFinished = true
        webView?.isHidden = false
        if pendingPlay {
            pendingPlay = false
            play()
        }
    }

    func markNavigationFailed(for gameID: String) {
        guard gameID == assignedGameID else { return }
        pendingPlay = false
    }

    func configure(
        with item: FeedItem,
        onReport: @escaping () -> Void,
        onBlock: @escaping () -> Void,
        onCreatorTapped: @escaping () -> Void
    ) {
        titleLabel.text = item.title
        creatorButton.setTitle(item.creatorName, for: .normal)
        self.onReport = onReport
        self.onBlock = onBlock
        self.onCreatorTapped = onCreatorTapped
    }

    private func setUpLayout() {
        contentView.backgroundColor = .secondarySystemBackground

        titleLabel.font = .preferredFont(forTextStyle: .title2)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0

        creatorButton.addTarget(self, action: #selector(creatorTapped), for: .touchUpInside)

        reportButton.setTitle("Report", for: .normal)
        reportButton.addTarget(self, action: #selector(reportTapped), for: .touchUpInside)

        blockButton.setTitle("Block", for: .normal)
        blockButton.addTarget(self, action: #selector(blockTapped), for: .touchUpInside)

        let actionsStack = UIStackView(arrangedSubviews: [reportButton, blockButton])
        actionsStack.axis = .horizontal
        actionsStack.spacing = 24
        actionsStack.distribution = .fillEqually

        let stack = UIStackView(arrangedSubviews: [titleLabel, creatorButton, actionsStack])
        stack.axis = .vertical
        stack.spacing = 16
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -24),
        ])
    }

    @objc private func creatorTapped() {
        onCreatorTapped?()
    }

    @objc private func reportTapped() {
        onReport?()
    }

    @objc private func blockTapped() {
        onBlock?()
    }
}
