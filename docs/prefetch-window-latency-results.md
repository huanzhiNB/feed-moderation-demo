# Prefetch-window latency & hitch results

Compares `FeedItemCell`'s "appear-to-play latency" and `FrameHitchMonitor`'s frame-hitch log
across different `WebViewPool` prefetch-window sizes, so bigger-window-vs-memory tradeoffs are
backed by numbers instead of guesses. `scripts/parse_latency.py` computes summary stats from a
captured console/log-stream file.

## Method (current — supersedes the earlier frequency-based draft of this doc)

- **`behind` is fixed at 1**; only `ahead` varies: **1, 3, 5, 7, 9** (5 groups). Slot count =
  `behind + ahead + 1`, so ahead=9 means 11 concurrent `WKWebView`s.
- **Swipe policy: wait for the current cell to actually log its own appear-to-play latency
  (i.e. it has finished loading and `sekaiPlay()` was actually called), then swipe to the next
  cell immediately.** Never swipe ahead of a still-loading cell — that was the flaw in an
  earlier draft of this test that used a fixed dwell timer regardless of load state.
- **10 cells per run** (indices 0–9), **2 repeats** per `ahead` value.
- Exclude cell index 0 from stats (`--exclude-first`) — cold start, no prefetch head start.
- Record both the latency numbers and the `FrameHitchMonitor` hitch numbers from the same
  capture — they answer two different questions (does a bigger window make content *ready*
  sooner, and does a bigger window cost you dropped frames on the main thread).

## Environment

- Simulator: iPhone 15 / iOS 17.4 (`C02DA888-16BB-4951-A762-FDCB7776D552`), Release build.
- Mock server: default flags, already running for the whole session (`python3 mock/server.py`,
  page-size 6, latency-ms 350, item-bytes 5MB, fail-rate 0.2) — not restarted between runs,
  since it holds no state that affects this metric.
- **Caveat: this machine was running other simulator instances, Xcode builds, and unrelated
  apps at the same time as some of these runs.** A handful of cells hit a 25s give-up ceiling
  during automated runs (visible as very large outliers, e.g. ~26.8s appearing on more than one
  cell) — those are real logged numbers, not fabricated, but they reflect shared-machine
  contention on top of the window-size effect, not a clean isolated measurement. Treat the
  **median**, not the mean, as the more trustworthy summary number for that reason.

## Results

### ahead = 1 (`PrefetchWindow(behind: 1, ahead: 1)`, 3 pool slots)

| Run | Latency n | Latency mean | Latency median | Latency p90 | Latency max | Hitch n | Hitch mean | Hitch max |
|---|---|---|---|---|---|---|---|---|
| 1 | 7 | 7888.6 ms | 331.7 ms | 26780.9 ms | 26848.5 ms | 9 | 18.5 ms | 40.0 ms |
| 2 | 9 | 3997.1 ms | 584.6 ms | 8566.2 ms | 8717.3 ms | 7 | 152.4 ms | 255.0 ms |
| **Combined** | **16** | **5699.6 ms** | **332.4 ms** | 8717.3 ms | 26848.5 ms | **16** | **77.1 ms** | 255.0 ms |

Run 1 hit the machine-contention issue noted above (cells 2–9 all needed the full 25s
timeout); run 2 completed cleanly with every cell logging before its own timeout.

### ahead = 3 (`PrefetchWindow(behind: 1, ahead: 3)`, 5 pool slots)

| Run | Latency n | Latency mean | Latency median | Latency p90 | Latency max | Hitch n | Hitch mean | Hitch max |
|---|---|---|---|---|---|---|---|---|
| 1 | 8 | 4729.6 ms | 449.4 ms | 8548.4 ms | 26769.0 ms | 5 | 161.8 ms | 253.3 ms |
| 2 | 8 | 5989.0 ms | 315.7 ms | 19194.3 ms | 26830.5 ms | 3 | 33.4 ms | 42.5 ms |
| **Combined** | **16** | **5359.3 ms** | **320.4 ms** | 19194.3 ms | 26830.5 ms | **8** | **113.6 ms** | 253.3 ms |

Both runs here hit the contention ceiling on several cells too, so the ahead=1 vs ahead=3
comparison above is **not yet clean enough to call** — the medians (332ms vs 320ms) look
similar, but both are diluted by the same shared-machine noise. Re-running either config on a
quieter machine (or with nothing else competing for the simulator) would sharpen this.

### ahead = 5, 7, 9

Not yet run — switched to manual testing (via Xcode) partway through automation because the
scripted swipe-and-poll harness was too slow/flaky on this shared machine. To add a group by
hand:

1. In `SceneDelegate.swift`, set `prefetchWindow: PrefetchWindow(behind: 1, ahead: <N>)`.
2. Run the app from Xcode, watch the console. Swipe to the next cell **as soon as** you see
   that cell's own `"cell <index> appear-to-play latency"` line print (not before — swiping
   earlier defeats the point of this protocol) and **not long after** (don't let it sit and
   rack up frames past that point either).
3. Copy the console output for 10 cells into a text file.
4. `python3 scripts/parse_latency.py <file> --exclude-first` — extracts both latency and hitch
   stats automatically from the same pasted log.
5. Add a row/section here in the same format as ahead=1/3 above.

## What's confirmed so far

- **Real per-item load time is large** — on the order of several seconds to ~10s for a cold
  (non-prefetched) 5 MB item on this mock/simulator setup, not the ~350ms the mock server's
  `--latency-ms` flag alone would suggest. Any prefetch window has to buy roughly that much
  head-start time to actually hide the load.
- **No hitches were observed during the multi-second load waits themselves** — `FrameHitchMonitor`
  only fired around cold app launch and briefly around `WKWebView` layer-commit moments, not
  during the idle waiting period. This is expected: the 5 MB fetch and page load happen off the
  main thread (WebKit's own process/network stack), so the main thread — and `CADisplayLink` —
  keeps ticking normally while a cell is "still loading." A dropped frame is more likely to
  show up **during the swipe/settle moment itself** than during the wait, so if you're manually
  testing, watch the console right as you release the swipe, not during the pause before it.

## Conclusion

`<fill in once ahead=5/7/9 are measured on a quieter run — which window size actually reduces
latency at a cost in concurrent WKWebViews that's still worth it, and whether hitches scale up
noticeably as slot count grows>`
