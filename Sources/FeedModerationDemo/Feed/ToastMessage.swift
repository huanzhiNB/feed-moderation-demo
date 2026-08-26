import Foundation

/// A one-shot confirmation event — fired the moment a moderation action is applied locally,
/// not tied to the network response (see `docs/architecture-plan.md` §4).
struct ToastMessage: Equatable {
    let text: String
}
