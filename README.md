# Feed Moderation Demo

## How to run it

1. Start the mock server (dependency-free Python 3):

   ```bash
   python3 mock/server.py            # serves http://127.0.0.1:8787
   ```

2. Open `FeedModerationDemo.xcodeproj` in Xcode and run the `FeedModerationDemo` scheme on
   an iOS 15+ simulator.

   The simulator reaches the mock server directly at `http://127.0.0.1:8787` — an ATS
   localhost exception for it is already set in `Info.plist`.

## Screen recording

[Demo recording](https://drive.google.com/file/d/1KPMVB_mCb-q_WnG9VFdT3sFXO9Q9Nm4z/view?usp=sharing)

## Moderation

Block and report are optimistic and local-first:

- `ModerationStore` holds `blockedCreatorIDs` and `reportedGameIDs` as `@Published` sets,
  persisted to `UserDefaults` — the only source of truth for what's hidden.
- `visibleItems = fetchedPages - blockedCreators - reportedSekais` is derived reactively
  (`FeedViewModel`, via `combineLatest` over the feed pages and both moderation sets), so
  hiding an item is never a one-off `list.remove(...)` call — it holds across scrolling back
  up, later page fetches that re-deliver the same item, and the creator's own page.
- A block/report writes into `ModerationStore` synchronously — the item disappears the same
  frame — and shows a toast, before the network call is even made.

### What happens when the moderation call fails

The `POST /blockUser` / `POST /reportContent` call is fired after the local state is already
updated, and its result is discarded (`try? await apiClient.blockUser(...)`). A failure —
including the mock server's built-in ~20% failure rate — **never reverts the local hide**: the
item stays gone, no error is surfaced, and there is no retry. The product tradeoff is
deliberate: once a user has blocked or reported something, showing it again because a backend
call failed would be a worse experience than a silent best-effort write.

## Sliding-window preload

Each ~5 MB item is a `WKWebView`, and the app cannot keep them all alive. `WebViewPool` is a
fixed pool of `WKWebView`s (sharing one `WKProcessPool`) whose residency is a deterministic
**sliding window**, not an LRU cache: on every settle, `FeedViewController` calls
`reconcile(desired:)` with exactly the `game_id`s that should be resident right now —
`PrefetchWindow(behind: 1, ahead: 5)` around the settled cell, 7 pool slots — and the pool
evicts (pause + stop loading) whatever's no longer desired, then loads whatever's missing into
the freed slots. A game already resident is left untouched, so its JS state (frame counter,
play/pause) survives scrolling past it and back.

### How it was tested

- `FrameHitchMonitor` samples `CADisplayLink` on every vsync and logs a hitch whenever the
  actual frame gap exceeds 1.5× the display's nominal frame duration (ProMotion-safe, not a
  fixed 60 fps assumption). `FeedItemCell` logs its own **appear-to-play latency** — the time
  from becoming the settled cell to `sekaiPlay()` actually firing. Both log to the same
  unified-logging stream, captured with `log stream` and parsed by `scripts/parse_latency.py`.
- Compared 5 window sizes — `ahead` = 1, 3, 5, 7, 9 (`behind` fixed at 1; pool slots =
  `behind + ahead + 1`) — swiping through 10 cells per run, 2 runs per size, only advancing to
  the next cell once the current one had actually logged its own appear-to-play latency (never
  swiping ahead of a still-loading cell). Cell index 0 (cold start, no prefetch head start) was
  excluded from the stats.
- Environment: iPhone 15 / iOS 17.4 simulator, Release build, mock server defaults
  (page-size 6, latency-ms 350, item-bytes 5 MB, fail-rate 0.2).

### Results (numbers, not adjectives)

| `ahead` | pool slots | latency median | latency mean | hitch count | hitch mean |
|---|---|---|---|---|---|
| 1 | 3 | 945.4 ms | 3954.7 ms | 12 | 187.9 ms |
| 3 | 5 | 584.9 ms | 3350.5 ms | 14 | 160.8 ms |
| 5 | 7 | 320.5 ms | 990.3 ms | 10 | 157.5 ms |
| 7 | 9 | 317.8 ms | 477.7 ms | 6 | 64.5 ms |
| 9 | 11 | 315.4 ms | 314.0 ms | 6 | 32.1 ms |

Full per-run tables and environment notes: `docs/prefetch-window-latency-results.md`.

### Conclusion

- **Shipped `ahead: 5` (7 pool slots), not a larger window.** Latency median drops from
  945 ms (`ahead=1`) to 320 ms (`ahead=5`) — more than 3×. Going further to `ahead=7`/`9` only
  reaches 317.8 ms / 315.4 ms, a difference inside measurement noise, for 2–4 more concurrent
  5 MB `WKWebView`s.
- **No frame-hitch cost from a bigger window was observed** — hitch count and average
  magnitude both trended *down* as `ahead` grew (187.9 ms mean at `ahead=1` → 32.1 ms mean at
  `ahead=9`), the opposite of this test's original hypothesis. Likely explanation: with a
  small window, a cold `WKWebView`'s first layer-tree commit tends to land on the main thread
  right at the scroll-settle moment; with a bigger window that work already happened seconds
  earlier while the cell was still just a neighbor.

### What we cut

- **Memory (RSS) was never measured.** `ahead=9` holds 11 concurrent ~5 MB `WKWebView`s vs. 3
  for `ahead=1` — that almost certainly costs real memory even though it cost no frames in
  this test. Quantifying it needs Instruments Allocations/VM Tracker ("All Processes", since
  `WebContent` is a separate process) per window size; not done given the time budget.
- **Measured only in Simulator, not on a real device.** The Simulator has no real memory
  pressure/jetsam behavior, so a real device is where a too-large window could still lose on
  memory even though it didn't lose on frames here.
- **No pause on `UIApplicationDidEnterBackground`.** Implied by "nothing keeps running off
  screen" but not written explicitly into the requirements; not implemented.
- **No automated UI test coverage** — explicitly out of scope for this exercise; correctness
  of the derived-feed and playback rules is covered by unit tests instead.

## To do

- **Memory-consumption monitoring.** Add an actual measurement of live `WKWebView`/`WebContent`
  footprint (Instruments Allocations/VM Tracker or `vmmap`, "All Processes") per prefetch-window
  size, to close the gap called out above — latency and hitches were measured, memory wasn't.
- **More realistic test cases.** The current latency/hitch protocol is one steady swipe speed
  through 10 cells; add scenarios closer to real usage — fast continuous flicks, pausing mid-feed,
  scrolling back up past already-seen items, backgrounding/foregrounding mid-scroll.
- **Retry the block/report network call on failure.** `blockUser`/`reportContent` currently fire
  once and discard the result (`try? await ...`); the local hide is correct and immediate, but a
  failed call (the mock server's ~20% built-in failure rate) is never retried, so the server-side
  state can permanently disagree with the client's. If retry is added, it must not surface a
  second toast that contradicts the first optimistic one when the retry eventually fails too —
  the "never revert the local hide" decision above applies to the UI feedback as well, not just
  the visible state.
- **Render SVG avatars.** `GET /avatar/<creatorId>` serves an SVG, but `CreatorProfileView` loads
  it through SwiftUI's `AsyncImage`, which only decodes bitmap formats (PNG/JPEG) — an SVG avatar
  currently just falls back to the placeholder. Needs an SVG parser/renderer (e.g. `WKWebView`-
  based rendering or a lightweight SVG-to-`UIImage` library) in its place.
- **Pause playback when the app backgrounds.** Not written explicitly into the requirements, but
  implied by "nothing keeps running off screen" — currently there's no
  `UIApplicationDidEnterBackground`/`willResignActive` handling, so a playing item keeps running
  after the app is backgrounded.
