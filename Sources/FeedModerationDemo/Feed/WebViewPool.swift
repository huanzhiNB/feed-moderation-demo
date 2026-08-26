import WebKit

/// Notified about navigation outcomes for a pooled WebView's currently-assigned game.
/// `gameID` is resolved by the pool from the slot's *current* assignment at callback time,
/// and cross-checked against the slot's `currentNavigation` (see below) so a stale callback
/// from a superseded load never gets attributed to the wrong game
/// (`docs/architecture-plan.md` §5).
protocol WebViewPoolDelegate: AnyObject {
    func webViewPool(_ pool: WebViewPool, didFinishLoadingGameID gameID: String)
    func webViewPool(_ pool: WebViewPool, didFailLoadingGameID gameID: String)
}

/// A small fixed pool of `WKWebView`s sharing one `WKProcessPool`, instead of one WebView
/// per cell. Residency is a deterministic sliding window, not an LRU cache: `reconcile(desired:)`
/// is always called with exactly the up-to-3 games that belong in the pool right now
/// ("settled ± 1", `docs/architecture-plan.md` §5) — the caller always knows the answer, so the
/// pool doesn't need to guess from access recency. Evicting only what's no longer desired means a
/// currently on-screen cell's game — always a member of the window computed around itself or
/// its immediate neighbor, since adjacent windows overlap — can never be evicted out from
/// under it; that's a structural property of the reconciliation, not a case that needs a
/// separate "don't touch this one" flag.
final class WebViewPool: NSObject {
    weak var delegate: WebViewPoolDelegate?

    /// Number of slots currently holding a game — exposed for Instruments cross-referencing
    /// (`docs/architecture-plan.md` §11): confirms the pool bound is actually respected at
    /// runtime, not just asserted in code.
    private(set) var occupiedSlotCount = 0

    private struct Slot {
        let webView: WKWebView
        var gameID: String?
        var url: URL?
        var isFinishedLoading = false
        /// The `WKNavigation` for this slot's current load, captured from `webView.load(_:)`'s
        /// return value. A delegate callback whose `navigation` doesn't match this is for a
        /// superseded load — evicted and reassigned to a different game before the callback for
        /// the *old* load arrived — and must not be attributed to whatever game now occupies the
        /// slot (`docs/architecture-plan.md` §5).
        var currentNavigation: WKNavigation?
    }

    private var slots: [Slot]

    init(slotCount: Int = 3) {
        let processPool = WKProcessPool()
        slots = (0..<slotCount).map { _ in
            let configuration = WKWebViewConfiguration()
            configuration.processPool = processPool
            return Slot(webView: WKWebView(frame: .zero, configuration: configuration), gameID: nil, url: nil)
        }
        super.init()
        for index in slots.indices {
            slots[index].webView.navigationDelegate = self
        }
    }

    /// Makes the pool's residency match `desired` exactly: evicts (pauses + stops) any slot
    /// whose game isn't in `desired`, then loads any of `desired` not already resident into
    /// the freed slots. A game already resident is left completely untouched — no reload,
    /// preserving its JS state (frame counter, play/pause) — since `desired` always fits
    /// within the pool's fixed size, eviction only ever frees exactly as many slots as are
    /// needed for what's missing.
    func reconcile(desired: [(gameID: String, url: URL)]) {
        let desiredIDs = Set(desired.map(\.gameID))
        for index in slots.indices where slots[index].gameID.map({ !desiredIDs.contains($0) }) ?? false {
            pause(slotIndex: index)
            slots[index].webView.stopLoading()
            slots[index].gameID = nil
            slots[index].url = nil
            slots[index].isFinishedLoading = false
            slots[index].currentNavigation = nil
            occupiedSlotCount -= 1
        }

        for pair in desired where !slots.contains(where: { $0.gameID == pair.gameID }) {
            guard let index = slots.firstIndex(where: { $0.gameID == nil }) else { continue }
            slots[index].gameID = pair.gameID
            slots[index].url = pair.url
            slots[index].isFinishedLoading = false
            slots[index].currentNavigation = slots[index].webView.load(URLRequest(url: pair.url))
            occupiedSlotCount += 1
        }
    }

    /// The WebView currently holding `gameID`'s content, if it's resident.
    func webView(for gameID: String) -> WKWebView? {
        slots.first(where: { $0.gameID == gameID })?.webView
    }

    /// Whether `gameID`'s currently-assigned slot has already finished loading — lets a
    /// cell that attaches to an already-resident WebView skip the deferred-play wait instead
    /// of always assuming a fresh, unfinished load.
    func isReady(for gameID: String) -> Bool {
        slots.first(where: { $0.gameID == gameID })?.isFinishedLoading ?? false
    }

    private func pause(slotIndex: Int) {
        slots[slotIndex].webView.evaluateJavaScript("window.sekaiPause && window.sekaiPause();") { _, error in
            if let error {
                print("WebViewPool: sekaiPause failed: \(error)")
            }
        }
    }

    private func slotIndex(for webView: WKWebView) -> Int? {
        slots.firstIndex { $0.webView === webView }
    }
}

extension WebViewPool: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
        guard
            let index = slotIndex(for: webView),
            let gameID = slots[index].gameID,
            navigation === slots[index].currentNavigation
        else { return }
        slots[index].isFinishedLoading = true
        delegate?.webViewPool(self, didFinishLoadingGameID: gameID)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation?, withError error: Error) {
        guard
            let index = slotIndex(for: webView),
            let gameID = slots[index].gameID,
            navigation === slots[index].currentNavigation
        else { return }
        delegate?.webViewPool(self, didFailLoadingGameID: gameID)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation?, withError error: Error) {
        guard
            let index = slotIndex(for: webView),
            let gameID = slots[index].gameID,
            navigation === slots[index].currentNavigation
        else { return }
        delegate?.webViewPool(self, didFailLoadingGameID: gameID)
    }

    /// The WebContent process can die under memory pressure from repeated ~5 MB loads
    /// (`docs/architecture-plan.md` §5). Recover by reloading from the slot's own stored URL —
    /// not `webView.url`, which can be stale or nil right after the process terminates.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard let index = slotIndex(for: webView), let url = slots[index].url else { return }
        slots[index].currentNavigation = webView.load(URLRequest(url: url))
    }
}
