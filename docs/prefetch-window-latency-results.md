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
- **First attempt at this table was thrown out and re-run.** The harness drives the swipe
  gesture with synthetic mouse events at fixed screen coordinates; two environment issues
  corrupted that first pass and were fixed before the numbers below were captured: (1) the Mac
  went to display sleep during a long idle gap and synthetic clicks stopped reaching the
  Simulator window until `caffeinate -d` was used to hold the display awake, and (2) another
  window came to the front and intercepted a run's clicks entirely, fixed by having the harness
  re-activate the Simulator app before every swipe. This machine also had two other simulator
  instances running the same app the whole time (not something this test controls), so some
  residual shared-CPU/network noise is still expected — a handful of cells below still needed
  the full 25s per-cell timeout. Treat **median** as the trustworthy number; mean is skewed by
  those remaining outliers.

## Results

### ahead = 1 (`PrefetchWindow(behind: 1, ahead: 1)`, 3 pool slots)

| Run | Latency n | Latency mean | Latency median | Latency p90 | Latency max | Hitch n | Hitch mean | Hitch max |
|---|---|---|---|---|---|---|---|---|
| 1 | 9 | 3970.0 ms | 524.8 ms | 8538.4 ms | 8607.8 ms | 5 | 192.6 ms | 246.1 ms |
| 2 | 9 | 3939.5 ms | 1320.2 ms | 8392.1 ms | 8587.3 ms | 7 | 184.5 ms | 254.4 ms |
| **Combined** | **18** | **3954.7 ms** | **945.4 ms** | 8538.4 ms | 8607.8 ms | **12** | **187.9 ms** | 254.4 ms |

Both runs completed with every cell logging before its own timeout — no outliers this time.

### ahead = 3 (`PrefetchWindow(behind: 1, ahead: 3)`, 5 pool slots)

| Run | Latency n | Latency mean | Latency median | Latency p90 | Latency max | Hitch n | Hitch mean | Hitch max |
|---|---|---|---|---|---|---|---|---|
| 1 | 8 | 4717.1 ms | 573.5 ms | 7688.4 ms | 26755.7 ms | 6 | 183.3 ms | 252.7 ms |
| 2 | 9 | 2135.6 ms | 584.9 ms | 7580.1 ms | 7638.8 ms | 8 | 143.8 ms | 256.3 ms |
| **Combined** | **17** | **3350.5 ms** | **584.9 ms** | 7638.8 ms | 26755.7 ms | **14** | **160.8 ms** | 256.3 ms |

Run 1 still hit the timeout ceiling on its last 2 cells (the one 26.8s outlier above); run 2
was fully clean.

### ahead=1 vs ahead=3 — reading the medians

| | ahead=1 | ahead=3 | Δ |
|---|---|---|---|
| Latency median | 945.4 ms | 584.9 ms | **-38%** |
| Hitch mean | 187.9 ms | 160.8 ms | -14% (noisy — see sample sizes) |
| Hitch sample count | 12 | 14 | slightly more hitches with the bigger window |

Bigger prefetch window measurably lowers the appear-to-play latency (more concurrent
`WKWebView`s means more items get a real head start before you scroll to them). It does **not**
show a corresponding hitch-count blowup here — 12 vs 14 hitch samples, similar magnitude — but
this is only a 2-step comparison (ahead=1 → ahead=3) with 2 runs each; whether that trend holds
or reverses at ahead=5/7/9 (11 concurrent 5MB `WKWebView`s at ahead=9) is exactly what those
remaining groups would tell you.

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
