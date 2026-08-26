# Prefetch-window latency & hitch results

Compares `FeedItemCell`'s "appear-to-play latency" and `FrameHitchMonitor`'s frame-hitch log
across different `WebViewPool` prefetch-window sizes, so bigger-window-vs-memory tradeoffs are
backed by numbers instead of guesses. `scripts/parse_latency.py` computes summary stats from a
captured console/log-stream file.

## Summary

| ahead | Pool 并发数 | Latency 中位数 | Hitch 均值 |
|---|---|---|---|
| 1 | 3 | 945.4 ms | 187.9 ms |
| 3 | 5 | 584.9 ms | 160.8 ms |
| 5 | 7 | 320.5 ms | 157.5 ms |
| 7 | 9 | 317.8 ms | 64.5 ms |
| 9 | 11 | 315.4 ms | 32.1 ms |

1. **拐点在 ahead=5，不是越大越好**：延迟中位数从 945ms 一路降到 320ms 就基本触底了，再往上加到 7、9
   几乎没有进一步收益（318ms、315ms，属于测量噪声范围）。
2. **本次测试没测出"窗口越大、主线程掉帧越多"的现象**——hitch 数量和强度反而是随 ahead 增大而下降的
   （187.9ms→32.1ms），推翻了这个实验最初想验证的假设（至少在延迟/hitch 这两个维度上）。
3. **但这不代表内存开销是免费的**——这次全程没测实际内存占用（RSS）。ahead=9 同时开 11 个 5MB 的
   WKWebView，内存压力大概率比 ahead=1 高很多，只是在 Simulator 上（不会像真机那样触发内存紧张/
   jetsam）体现不出来。要验证真实的"内存 vs 性能"权衡，还需要用 Instruments 的 Allocations/VM
   Tracker（记得开 "All Processes"，因为 WebContent 是独立进程）分别测一下这 5 组配置的峰值内存
   ——这是这份文档目前唯一没回答的部分。

**Decision**: shipped default set to `PrefetchWindow(behind: 1, ahead: 5)` (7 pool slots) —
see `Sources/FeedModerationDemo/Feed/FeedViewController.swift`.

Full per-run tables, environment notes, and the reasoning behind each point above follow below.

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

### ahead = 5 (`PrefetchWindow(behind: 1, ahead: 5)`, 7 pool slots)

| Run | Latency n | Latency mean | Latency median | Latency p90 | Latency max | Hitch n | Hitch mean | Hitch max |
|---|---|---|---|---|---|---|---|---|
| 1 | 9 | 1031.3 ms | 331.9 ms | 1183.7 ms | 4850.1 ms | 5 | 156.3 ms | 249.5 ms |
| 2 | 8 | 944.1 ms | 320.4 ms | 1218.2 ms | 4189.0 ms | 5 | 158.7 ms | 251.5 ms |
| **Combined** | **17** | **990.3 ms** | **320.5 ms** | 1218.2 ms | 4850.1 ms | **10** | **157.5 ms** | 251.5 ms |

Both runs clean, no timeouts.

### ahead = 7 (`PrefetchWindow(behind: 1, ahead: 7)`, 9 pool slots)

| Run | Latency n | Latency mean | Latency median | Latency p90 | Latency max | Hitch n | Hitch mean | Hitch max |
|---|---|---|---|---|---|---|---|---|
| 1 | 8 | 315.9 ms | 315.5 ms | 322.6 ms | 325.3 ms | 3 | 28.1 ms | 51.1 ms |
| 2 | 9 | 621.5 ms | 319.3 ms | 1515.9 ms | 1897.9 ms | 3 | 101.0 ms | 252.9 ms |
| **Combined** | **17** | **477.7 ms** | **317.8 ms** | 325.3 ms | 1897.9 ms | **6** | **64.5 ms** | 252.9 ms |

Run 1's harness polling lagged badly here (every cell after 0 reported "TIMED OUT" in the
script's own progress log) — but the *content itself* was already fast (each cell's own
internally-computed latency is ~310-325ms, not delayed), confirming this was the capture
pipeline lagging under load, not the app. The numbers are kept as-is since they're genuine
values written by the app, just detected later than intended; wall-clock pacing (not data
validity) was the casualty.

### ahead = 9 (`PrefetchWindow(behind: 1, ahead: 9)`, 11 pool slots)

| Run | Latency n | Latency mean | Latency median | Latency p90 | Latency max | Hitch n | Hitch mean | Hitch max |
|---|---|---|---|---|---|---|---|---|
| 1 | 9 | 317.5 ms | 317.6 ms | 323.4 ms | 325.2 ms | 4 | 25.0 ms | 40.1 ms |
| 2 | 9 | 310.6 ms | 312.2 ms | 317.2 ms | 322.3 ms | 2 | 46.2 ms | 53.7 ms |
| **Combined** | **18** | **314.0 ms** | **315.4 ms** | 322.3 ms | 325.2 ms | **6** | **32.1 ms** | 53.7 ms |

Both runs clean, no timeouts — and the tightest, most consistent numbers of any group (every
single sample lands in a 296–325ms band).

## ahead = 1 / 3 / 5 / 7 / 9 — full comparison

| ahead | Pool slots | Latency median | Latency mean | Hitch n | Hitch mean |
|---|---|---|---|---|---|
| 1 | 3 | 945.4 ms | 3954.7 ms | 12 | 187.9 ms |
| 3 | 5 | 584.9 ms | 3350.5 ms | 14 | 160.8 ms |
| 5 | 7 | 320.5 ms | 990.3 ms | 10 | 157.5 ms |
| 7 | 9 | 317.8 ms | 477.7 ms | 6 | 64.5 ms |
| 9 | 11 | 315.4 ms | 314.0 ms | 6 | 32.1 ms |

**Latency drops monotonically and converges.** Going from ahead=1 to ahead=5 more than
triples the effective throughput (945ms → 320ms median); ahead=5 → 9 barely moves the needle
(320ms → 315ms) because the median has already hit the floor — the ~300-325ms left over is
just `evaluateJavaScript` + native call overhead once content is already sitting in memory
fully loaded, not something any bigger window can shave further. **The real win is in going
from ahead=1 to somewhere around ahead=5; ahead=7 and ahead=9 buy almost nothing more.**

**Hitches did not get worse with more concurrent `WKWebView`s — they got *better*.** Both hitch
count and average magnitude trend down as `ahead` grows (187.9ms → 32.1ms mean; 12 → 6
samples). The likely explanation: with a small window, a cold `WKWebView` navigation often has
to actually start and commit its first layer tree at the exact moment you land on that cell
(visible in earlier testing as `WKWebView _didCommitLayerTree` calls near a settle) — that's
main-thread work happening right when you're also mid-scroll-settle. With a bigger window,
that same work already happened seconds earlier while the cell was still just a "neighbor," so
by the time you actually swipe there the main thread has nothing to do but flip a boolean and
call `sekaiPlay()`.

**Caveat — this is latency and hitches only, not memory.** None of these runs measured actual
RSS/footprint per config. Going from 3 to 11 concurrent `WKWebView`s (each holding a ~5MB page)
almost certainly costs real memory even though it didn't cost frames here — that tradeoff still
needs Instruments Allocations/VM Tracker (or `vmmap`) per config to quantify, which is the
one piece this test doesn't answer.

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

- **ahead=5 is the sweet spot, not ahead=9.** Latency median: 945ms (ahead=1) → 585ms (ahead=3)
  → 320ms (ahead=5) → 318ms (ahead=7) → 315ms (ahead=9). Almost all the win is captured by
  ahead=5; going past it to 7 or 9 pays for 4-6 more concurrent 5MB `WKWebView`s for a few
  milliseconds of further improvement that's within measurement noise.
- **No evidence of a frame-hitch cost from more concurrent WebViews in this test** — hitches
  actually trended down, not up, as `ahead` grew. So the "bigger window = worse main-thread
  performance" hypothesis this whole experiment was built to check did **not** show up in
  latency/hitch terms.
- **That doesn't mean the memory cost is free** — this test never measured RSS. ahead=9's 11
  concurrent 5MB pages are almost certainly heavier on memory than ahead=1's 3, even though
  neither one dropped a frame here. On a real device (unlike this Mac-backed Simulator, which
  has no real memory pressure/jetsam behavior) that memory cost is where a large window could
  still lose — measuring actual footprint per config (Instruments Allocations/VM Tracker,
  "All Processes" so the separate `WebContent` processes are included) is the natural next
  step before picking ahead=5 as a real shipping default.
