import UIKit

/// A short self-dismissing toast — no third-party library, two message strings only
/// (`docs/architecture-plan.md` §4).
final class ToastView: UIView {
    private let label = UILabel()

    init(text: String) {
        super.init(frame: .zero)
        backgroundColor = UIColor.label.withAlphaComponent(0.85)
        layer.cornerRadius = 8
        clipsToBounds = true

        label.text = text
        label.textColor = .systemBackground
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(in containerView: UIView, duration: TimeInterval = 2) {
        translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(self)

        NSLayoutConstraint.activate([
            centerXAnchor.constraint(equalTo: containerView.safeAreaLayoutGuide.centerXAnchor),
            bottomAnchor.constraint(equalTo: containerView.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            leadingAnchor.constraint(greaterThanOrEqualTo: containerView.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            trailingAnchor.constraint(lessThanOrEqualTo: containerView.safeAreaLayoutGuide.trailingAnchor, constant: -24),
        ])

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            self?.removeFromSuperview()
        }
    }
}
