import Combine
import SwiftUI
import UIKit

/// Hosts `CreatorProfileView` directly — subclassing `UIHostingController` (rather than
/// embedding it as a child) so SwiftUI's `.toolbar`/`.navigationTitle` bridge to this view
/// controller's own `navigationItem`, which is the one `UINavigationController` actually reads.
/// Toast presentation and popping back to the feed after a block stay UIKit-native.
final class CreatorProfileViewController: UIHostingController<CreatorProfileView> {
    private let viewModel: CreatorProfileViewModel
    private var cancellables = Set<AnyCancellable>()

    init(viewModel: CreatorProfileViewModel) {
        self.viewModel = viewModel
        super.init(rootView: CreatorProfileView(viewModel: viewModel))
    }

    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        bindViewModel()
    }

    private func bindViewModel() {
        viewModel.toastEvents
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                // Block also pops back to the feed, which happens right after this same
                // Combine tick — show the toast on the navigation controller's view, not
                // this screen's own view, so it survives the pop instead of disappearing
                // with it.
                guard let self, let containerView = self.navigationController?.view ?? self.view else { return }
                ToastView(text: message.text).show(in: containerView)
            }
            .store(in: &cancellables)

        viewModel.didBlockCreator
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.navigationController?.popViewController(animated: true)
            }
            .store(in: &cancellables)
    }
}
