import WebKit

/// Notified about navigation outcomes for a pooled WebView's currently-assigned game.
/// `gameID` is resolved by the pool from the slot's *current* assignment at callback time,
/// so a stale callback from a superseded load never gets attributed to the wrong game
/// (`ARCHITECTURE.md` §5).
protocol WebViewPoolDelegate: AnyObject {
    func webViewPool(_ pool: WebViewPool, didFinishLoadingGameID gameID: String)
    func webViewPool(_ pool: WebViewPool, didFailLoadingGameID gameID: String)
}

/// A small fixed pool of `WKWebView`s ("settled ± 1" — 3 instances, `ARCHITECTURE.md` §5)
/// sharing one `WKProcessPool`, instead of one WebView per cell. A cell outside the pool's
/// window gets no WebView at all.
final class WebViewPool: NSObject {
    weak var delegate: WebViewPoolDelegate?

    private struct Slot {
        let webView: WKWebView
        var gameID: String?
        var url: URL?
        var lastUsedTick: Int
    }

    private var slots: [Slot]
    private var tick = 0

    init(slotCount: Int = 3) {
        let processPool = WKProcessPool()
        slots = (0..<slotCount).map { _ in
            let configuration = WKWebViewConfiguration()
            configuration.processPool = processPool
            return Slot(webView: WKWebView(frame: .zero, configuration: configuration), gameID: nil, url: nil, lastUsedTick: 0)
        }
        super.init()
        for index in slots.indices {
            slots[index].webView.navigationDelegate = self
        }
    }

    /// Returns the pooled WebView assigned to `gameID`, loading `url` into it if it wasn't
    /// already assigned there. Reassigns a free slot, or evicts the least-recently-used
    /// assigned slot (pausing + stopping it first) if none are free.
    func acquireWebView(for gameID: String, url: URL) -> WKWebView {
        tick += 1

        if let index = slots.firstIndex(where: { $0.gameID == gameID }) {
            slots[index].lastUsedTick = tick
            return slots[index].webView
        }

        let targetIndex = slots.firstIndex(where: { $0.gameID == nil })
            ?? slots.indices.min(by: { slots[$0].lastUsedTick < slots[$1].lastUsedTick })
            ?? 0

        pause(slotIndex: targetIndex)
        slots[targetIndex].webView.stopLoading()
        slots[targetIndex].gameID = gameID
        slots[targetIndex].url = url
        slots[targetIndex].lastUsedTick = tick
        slots[targetIndex].webView.load(URLRequest(url: url))
        return slots[targetIndex].webView
    }

    /// Cell exiting the pool's window: pause, stop loading, and free the slot for reuse.
    /// The `WKWebView` instance itself stays alive in the pool.
    func release(gameID: String) {
        guard let index = slots.firstIndex(where: { $0.gameID == gameID }) else { return }
        pause(slotIndex: index)
        slots[index].webView.stopLoading()
        slots[index].gameID = nil
        slots[index].url = nil
    }

    private func pause(slotIndex: Int) {
        slots[slotIndex].webView.evaluateJavaScript("window.sekaiPause && window.sekaiPause();")
    }

    private func slotIndex(for webView: WKWebView) -> Int? {
        slots.firstIndex { $0.webView === webView }
    }
}

extension WebViewPool: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
        guard let index = slotIndex(for: webView), let gameID = slots[index].gameID else { return }
        delegate?.webViewPool(self, didFinishLoadingGameID: gameID)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation?, withError error: Error) {
        guard let index = slotIndex(for: webView), let gameID = slots[index].gameID else { return }
        delegate?.webViewPool(self, didFailLoadingGameID: gameID)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation?, withError error: Error) {
        guard let index = slotIndex(for: webView), let gameID = slots[index].gameID else { return }
        delegate?.webViewPool(self, didFailLoadingGameID: gameID)
    }

    /// The WebContent process can die under memory pressure from repeated ~5 MB loads
    /// (`ARCHITECTURE.md` §5). Recover by reloading from the slot's own stored URL — not
    /// `webView.url`, which can be stale or nil right after the process terminates.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard let index = slotIndex(for: webView), let url = slots[index].url else { return }
        webView.load(URLRequest(url: url))
    }
}
