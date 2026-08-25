import UIKit

final class RootViewController: UIViewController {
    private let statusLabel = UILabel()
    private let healthCheckClient = HealthCheckClient()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.text = "Checking mock server…"
        view.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            statusLabel.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            statusLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24
            ),
            statusLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24
            ),
        ])

        checkMockServer()
    }

    private func checkMockServer() {
        Task { [weak self] in
            guard let self else { return }
            let isReachable = await self.healthCheckClient.checkHealth()
            await MainActor.run {
                self.statusLabel.text = isReachable ? "Mock server: ok" : "Mock server: unreachable"
            }
        }
    }
}
