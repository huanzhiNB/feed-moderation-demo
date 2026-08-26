import UIKit

/// Temporary placeholder for the creator page — Slice 5 replaces this with the real screen
/// (avatar, bio, paged sekais, block from the `⋯` panel).
final class CreatorProfilePlaceholderViewController: UIViewController {
    private let creatorID: String
    private let creatorName: String

    init(creatorID: String, creatorName: String) {
        self.creatorID = creatorID
        self.creatorName = creatorName
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = creatorName

        let label = UILabel()
        label.text = "\(creatorName)\n\(creatorID)"
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
        ])
    }
}
