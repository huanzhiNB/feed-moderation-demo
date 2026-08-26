import QuartzCore

/// Frame-timing measurement for the "scrolling does not drop frames" requirement
/// (`README.md`): samples `CADisplayLink` on every vsync and flags a hitch whenever the
/// actual gap since the previous frame overruns the display's own nominal frame duration
/// (`link.duration`, so this stays correct under ProMotion's variable refresh rate rather than
/// assuming a fixed 60fps). Logs once per hitch via `NSLog` — same unified-logging channel as
/// `FeedItemCell`'s appear-to-play latency — so both show up in one `log stream` capture for
/// the prefetch-window comparison in `docs/prefetch-window-latency-results.md`.
final class FrameHitchMonitor {
    /// A frame counts as a hitch once it overruns the nominal duration by this factor —
    /// 1.5x tolerates ordinary jitter while still catching a single dropped frame.
    private let hitchThresholdMultiplier: Double = 1.5

    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?

    func start() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        lastTimestamp = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        defer { lastTimestamp = link.timestamp }
        guard let lastTimestamp else { return }

        let actualDuration = link.timestamp - lastTimestamp
        let nominalDuration = link.duration
        guard nominalDuration > 0, actualDuration > nominalDuration * hitchThresholdMultiplier else { return }

        let hitchMilliseconds = (actualDuration - nominalDuration) * 1000
        NSLog(
            "FrameHitchMonitor: hitch %.1f ms (frame took %.1f ms, expected %.1f ms)",
            hitchMilliseconds,
            actualDuration * 1000,
            nominalDuration * 1000
        )
    }
}
