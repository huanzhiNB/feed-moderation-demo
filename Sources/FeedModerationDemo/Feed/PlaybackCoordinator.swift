/// Decides which single feed item should be playing. Pure — no UIKit/WebKit — so
/// "exactly one playing" is a structural property of this one call site
/// (`docs/architecture-plan.md` §6), not something re-verified wherever `sekaiPlay`/`sekaiPause` are
/// issued.
final class PlaybackCoordinator {
    private(set) var currentlyPlayingID: String?

    /// Same ID twice → no-op (don't restart the animation). Otherwise pauses whatever was
    /// playing (if anything) and plays `newID` (if any).
    func settled(on newID: String?) -> (toPlay: String?, toPause: String?) {
        guard newID != currentlyPlayingID else { return (nil, nil) }
        let toPause = currentlyPlayingID
        currentlyPlayingID = newID
        return (newID, toPause)
    }
}
