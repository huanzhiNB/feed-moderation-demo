import UIKit

/// Simple placeholder cell — title, creator, Report, and Block. No WKWebView yet (Slice 6).
final class FeedItemCell: UICollectionViewCell {
    static let reuseIdentifier = "FeedItemCell"

    private let titleLabel = UILabel()
    private let creatorButton = UIButton(type: .system)
    private let reportButton = UIButton(type: .system)
    private let blockButton = UIButton(type: .system)

    private var onReport: (() -> Void)?
    private var onBlock: (() -> Void)?
    private var onCreatorTapped: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUpLayout()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
