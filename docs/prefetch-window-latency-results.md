# Prefetch-window latency test — protocol & results

Fixed protocol for comparing `FeedItemCell`'s "appear-to-play latency" log across (a) scroll
speed and (b) `WebViewPool` prefetch-window size, so numbers stay comparable run to run.
`scripts/parse_latency.py` computes the summary stats from captured logs.

## Fixed environment (keep identical across every run in this doc)

- **Simulator**: one specific device + iOS version, e.g. iPhone 15 / iOS 17.4 — pick one and
  record the exact simctl id here once chosen: `<fill in>`.
- **Build configuration**: Debug (same as normal `xcodebuild ... build`/Xcode Run).
- **Mock server**: fresh restart before each run, default flags —
  `python3 mock/server.py` (page-size 6, latency-ms 350, item-bytes 5MB, fail-rate 0.2).
- **App state**: fully kill and cold-launch the app before each run (never resume from
  background) — avoids `WebViewPool` residency carrying over between runs.

## Frequency conditions (dwell time on a cell before swiping to the next, paced by a
metronome/stopwatch so the cadence is reproducible by hand)

| Condition | Dwell | What it's meant to show |
|---|---|---|
| Slow | 5s / cell | Ample time for the ahead-neighbor(s) to fully load before you reach them — latency should floor out near 0 regardless of window size |
| Medium-slow | 3s / cell | Comfortably longer than one load; window size differences should mostly wash out |
| Medium | 1s / cell | Near the boundary of one load's duration — where a bigger `ahead` window should start to pay off |
| Fast | 0.2s / cell | Deliberately outruns any window size tested here — worst case, upper bound |

## Sample size

- 30 cells per run (indices 0–29).
- 3 runs per (window config × frequency) cell of the matrix → 90 samples.
- **Exclude cell index 0** from stats (`--exclude-first`): it's the cold-start cell, never
  benefits from a prefetched neighbor regardless of window size or scroll speed, and would
  flatten the differences between conditions.

## Window configs under test

Set in `Sources/FeedModerationDemo/App/SceneDelegate.swift`, the `prefetchWindow:` argument
passed to `FeedViewController.init`:

| Label | `PrefetchWindow` | `WebViewPool` slot count |
|---|---|---|
| a (current default) | `PrefetchWindow(behind: 1, ahead: 1)` | 3 |
| b | `PrefetchWindow(behind: 1, ahead: 2)` | 4 |
| c | `PrefetchWindow(behind: 1, ahead: 3)` | 5 |

Slot count scales with the window automatically (`behind + ahead + 1`) — more slots means
more concurrently-loading ~5 MB `WKWebView`s resident at once; watch simulator memory if this
gets extended past config c.

## Procedure per (window, frequency) cell

1. Edit `prefetchWindow:` in `SceneDelegate.swift` to the config under test, rebuild.
2. Restart the mock server fresh.
3. Cold-launch the app.
4. Start log capture:
   ```bash
   xcrun simctl spawn booted log stream --style compact \
     --predicate 'eventMessage CONTAINS "appear-to-play latency"' \
     > perf-logs/<config>_<frequency>_run<N>.log
   ```
5. Swipe through 30 cells at the fixed dwell pace for this frequency condition.
6. Stop capture (Ctrl-C).
7. Repeat steps 2–6 two more times (3 runs total for this matrix cell).
8. Summarize:
   ```bash
   python3 scripts/parse_latency.py perf-logs/<config>_<frequency>_run*.log --exclude-first
   ```
9. Record mean / median / p90 / max in the matching table below.
10. Once all four frequencies are done for a window config, move to the next config. **Set
    `prefetchWindow:` back to `.default` before submitting the app** — configs b and c are for
    this experiment only, not the shipped behavior.

## Results

### Config a — `behind:1, ahead:1` (current default, "settled ± 1")

| Frequency | Runs | N | Mean (ms) | Median (ms) | P90 (ms) | Max (ms) |
|---|---|---|---|---|---|---|
| 5s | 3 | 90 | | | | |
| 3s | 3 | 90 | | | | |
| 1s | 3 | 90 | | | | |
| 0.2s | 3 | 90 | | | | |

### Config b — `behind:1, ahead:2`

| Frequency | Runs | N | Mean (ms) | Median (ms) | P90 (ms) | Max (ms) |
|---|---|---|---|---|---|---|
| 5s | 3 | 90 | | | | |
| 3s | 3 | 90 | | | | |
| 1s | 3 | 90 | | | | |
| 0.2s | 3 | 90 | | | | |

### Config c — `behind:1, ahead:3`

| Frequency | Runs | N | Mean (ms) | Median (ms) | P90 (ms) | Max (ms) |
|---|---|---|---|---|---|---|
| 5s | 3 | 90 | | | | |
| 3s | 3 | 90 | | | | |
| 1s | 3 | 90 | | | | |
| 0.2s | 3 | 90 | | | | |

## Conclusion

`<fill in once all three configs are measured — which window size actually reduces latency at
the frequencies that matter, and whether the extra WKWebView memory cost of config b/c is
worth it>`
