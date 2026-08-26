# Architecture plan — Sekai feed (UIKit + Combine + WKWebView + async/await, iOS 15+)

Design notes written before implementation, per the take-home requirements in `README.md`.
Not implementation — this is the plan to build against and revisit if something in code
drifts from it.

## 1. State ownership

Three independent stores, each owned by exactly one object and injected everywhere it's
needed — never re-instantiated per screen:

| Store | Owns | Lifetime | Persisted? |
|---|---|---|---|
| `FeedRepository` | `fetchedPages: [FeedItem]`, pagination cursor, loading/exhausted flags | App-scoped singleton (one feed) | No — refetched on cold start |
| `ModerationStore` | `blockedCreatorIDs: Set<String>`, `reportedGameIDs: Set<String>` | App-scoped singleton, injected into **both** Feed and Creator screens | **Yes** (required — see §8) |
| `PlaybackCoordinator` | `currentlyPlayingID: String?` | Owned by the feed screen only (playback is a feed-screen concern; creator page has no autoplay requirement) | No |

The single most important ownership decision: **`ModerationStore` must be one instance
shared by both the feed and the creator page**, injected via `init`. Two separately
constructed stores is the #1 way to silently fail "block from the `⋯` panel hides
everywhere."

## 2. Reactive data flow

The derivation is the architecture — everything else hangs off it:

```swift
visibleItems = Publishers.CombineLatest3(
    feedRepository.$pages,
    moderationStore.$blockedCreatorIDs,
    moderationStore.$reportedGameIDs
)
.map { pages, blocked, reported in
    pages.filter { !blocked.contains($0.creatorID) && !reported.contains($0.gameID) }
}
.removeDuplicates()
.receive(on: DispatchQueue.main)
```

Pull the `.map` body out as a **free function**
(`func visibleItems(pages:blocked:reported:) -> [FeedItem]`) rather than an inline closure —
that's what makes it unit-testable without Combine/UIKit in the test target (see §10).

Block/report handlers write **only** into `ModerationStore` — they never touch `pages` or
the diffable data source directly. New pages appended to `FeedRepository.pages` flow
through the same `CombineLatest3` automatically, so an already-blocked creator's future
items are filtered without any special-casing at fetch time.

**State vs. one-shot events use different Combine primitives.** `pages`,
`blockedCreatorIDs`, `reportedGameIDs`, and `visibleItems` are all continuous *state* — they
have a meaningful "current value" a late subscriber should see, so `CurrentValueSubject` /
`@Published` is correct. A toast (§4) is a one-shot *event*, not state — nothing should
"replay" the last toast to a screen that just appeared. That's a `PassthroughSubject<Toast,
Never>`, fired once per action, with no current-value semantics.

## 3. Feed architecture

- `UICollectionView` + `UICollectionViewFlowLayout`, `scrollDirection = .vertical`,
  `itemSize = collectionView.bounds.size`, `minimumLineSpacing = 0`,
  `minimumInteritemSpacing = 0`, and `collectionView.isPagingEnabled = true`.

  **Correction (was wrong in the original draft):** the original plan called for
  `UICollectionViewCompositionalLayout` with `.groupPagingCentered` as the paging
  mechanism. That's a misapplication — `NSCollectionLayoutSection.orthogonalScrollingBehavior`
  governs a section's scrolling in the axis **orthogonal** to the collection view's primary
  scroll direction (e.g. a horizontal carousel row inside a vertically-scrolling list). For a
  vertical collection view, `.groupPagingCentered` would only page a horizontal sub-scroll —
  it does nothing for paging the *primary* vertical axis, which is what "snaps to an item, no
  resting between two" actually needs. `isPagingEnabled` is the correct mechanism: it's a
  `UIScrollView`-level behavior that snaps to multiples of the scroll view's own bounds size
  in the scroll direction, independent of the layout — it works correctly here as long as
  `itemSize.height == collectionView.bounds.height` and spacing is `0`, so a page boundary
  always lines up with a cell boundary. Flow layout is also simpler than compositional layout
  for a single full-bleed column, which fits "prioritize simplicity over abstraction."
- `UICollectionViewDiffableDataSource<Section, String>` keyed by `game_id` — gives correct
  insert/remove animations for free when `visibleItems` changes, and (critically) gives
  cells a stable identity across reloads, which the WebView pool depends on (§5).
- Infinite-scroll trigger: `collectionView(_:willDisplay:forItemAt:)`, fire the next-page
  fetch when the **visible (filtered) index** is within N (e.g. 2) of the end of
  `visibleItems` — not `fetchedPages.count`. See §7 for why that distinction matters.

## 4. Moderation architecture

- `ModerationStore` (state) and `ModerationService` (network) are separate — the store is
  what the UI derives from; the service is what talks to `/blockUser` / `/reportContent`.
- Flow for both actions is identical:
  1. Write the ID into `ModerationStore` synchronously on the main thread — item disappears
     same frame, before any network call starts.
  2. Fire the `URLSession` async/await POST in a `Task`.
  3. On success: nothing further — state was already committed.
  4. On failure: **do not revert.** Reverting resurrects content the user explicitly asked
     to hide, which is the wrong default for a compliance surface. Keep the optimistic hide,
     optionally track it in a `pendingSync: Set<String>` for a silent background retry. This
     is a judgment call the assignment explicitly wants documented in the submission
     README — flag it there, don't bury it.
- Idempotency: `Set.insert` is naturally idempotent, but disable the tapped button
  immediately anyway to prevent duplicate POSTs from a double-tap.
- Creator page's `⋯ → Block` calls the exact same `ModerationStore.block(creatorID:)` +
  `ModerationService.block(creatorID:)` — no parallel implementation.

**Toast (missing from the original draft — this is a written requirement, not polish).**
README: "The item disappears immediately — no waiting for the network round trip. A toast
(or platform equivalent) confirms what happened." Concretely:
- Fire the toast at the same moment as the `ModerationStore` write in step 1 — i.e. the toast
  is tied to the optimistic local action, not to the network response. It must appear
  immediately, same as the item's disappearance.
- Model it as a `PassthroughSubject<ToastMessage, Never>` on the view model (see §2) —
  a one-shot event, not state. The view controller subscribes and presents a small
  self-dismissing view (a short-timer `UIView`, no third-party toast library needed for two
  message strings).
- Content: `"Blocked \(creatorName)"` / `"Reported"` — fixed text per §4's "don't revert"
  decision. Because the optimistic hide is never reverted on the ~20% failure, the toast
  text must **not** later be corrected or superseded by a second "actually, that failed"
  message — that would contradict the hide the user already saw and undermine trust in the
  first toast. One toast per action, worded as already-done.

## 5. WKWebView lifecycle

This is where "don't drop frames" and "5 MB items" collide, and it's the section worth the
most design care.

- **Small pooled window, not one WebView per cell, not create-on-demand per scroll event.**
  Keep a fixed pool of `WKWebView` instances sized from `PrefetchWindow` (default
  `behind: 1, ahead: 5` → 7 slots, chosen from the measured latency/hitch comparison in
  `docs/prefetch-window-latency-results.md` — appear-to-play latency floors out by ahead=5),
  sharing one `WKProcessPool`. A cell outside that window shows a static placeholder (cover
  image), no WebView at all.
- On enter-window: assign a pooled WebView to the cell,
  `load(URLRequest(url: item.gameURL))`.
- On exit-window: `stopLoading()`, call `sekaiPause()` if it was playing, detach from the
  cell, return the instance to the pool for reassignment.
- Gate `sekaiPlay()` on `WKNavigationDelegate.didFinish` — never fire-and-forget
  `evaluateJavaScript` right after `load(_:)`, since `sekaiPlay` isn't defined until the
  page's `<script>` has executed.
- Implement `webViewWebContentProcessDidTerminate` — under memory pressure with repeated
  5 MB loads, the WebContent process can die; without a reload-on-terminate handler that
  cell goes permanently blank.
- Be ready to name and justify the pool size (7, from `ahead: 5`) in the submission README —
  this is graded explicitly ("what is alive while scrolling, and why that number").

Cell reuse racing async work: if a pooled WebView is reassigned to a new `game_id` while a
previous `load()` is still in flight, a late-arriving `didFinish` must not call
`sekaiPlay()` against a WebView that now represents a different item — check the WebView's
currently-assigned `game_id` before acting on any deferred callback.

## 6. Playback lifecycle

- Settle detection has **two independent triggers**, both required:
  - `scrollViewDidEndDecelerating` and `scrollViewDidEndScrollingAnimation` (programmatic
    scroll).
  - `scrollViewDidEndDragging(_:willDecelerate:)` **when `willDecelerate == false`.**

  **Correction (missing from the original draft):** a drag that's released without enough
  velocity to enter a deceleration phase never fires `scrollViewDidEndDecelerating` at all —
  UIKit calls `didEndDragging` with `willDecelerate: false` and stops there. Without this
  second trigger, that release can land the feed on a new settled item that never gets a
  play command — a slow, deliberate drag-and-release is exactly the gesture most likely to
  hit this path, not an edge case that only shows up under stress.
  ```swift
  func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
      if !decelerate { handleSettle() }
  }
  func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { handleSettle() }
  func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) { handleSettle() }
  ```
  **Never** `scrollViewDidScroll` as a settle signal — that fires continuously during a
  flick and would trigger play on every intermediate cell.
- On settle, compute the centered item
  (`indexPathForItem(at: CGPoint(x: bounds.midX, y: bounds.midY))`), then hand
  `(previousID, newID)` to a pure `PlaybackCoordinator.settled(on:)` function that returns
  `(toPlay, toPause)`. Same ID twice → no-op (don't restart the animation).
- The coordinator issues `sekaiPlay()`/`sekaiPause()` through the cell — it's the **only**
  call site for both, so "exactly one playing" is a structural property, not something
  re-verified at every call site.
- Pause explicitly on WebView pool eviction (§5) even if the coordinator's
  `currentlyPlayingID` already changed — belt and suspenders, since an evicted-but-still-
  running animation is invisible but not free (CPU, thread).
- **Reconcile playback on every `visibleItems` change, not only on scroll settle.**

  **Correction (missing from the original draft):** playback was designed as purely
  scroll-driven, but the currently-playing item can also disappear without any scroll
  happening — the user reports or blocks the item they're currently watching. The
  derivation (§2) removes it from `visibleItems` and the diffable data source drops its
  cell immediately, but nothing in a scroll-only design tells `PlaybackCoordinator` that its
  `currentlyPlayingID` is now gone — no settle event fires, since the user never scrolled.
  Left alone, this violates "exactly one playing" for however long it takes until the next
  real scroll: the old item's `sekaiPause()` never gets called, and the newly-centered item
  never gets `sekaiPlay()`. Fix: the same subscriber that applies a new snapshot after
  `visibleItems` changes must also reconcile playback —
  ```
  visibleItems changed → apply snapshot →
      is currentlyPlayingID still in visibleItems?
          no  → pause it, compute the new centered item, play that
          yes → no-op
  ```
  This makes `PlaybackCoordinator` driven by two independent event sources (scroll settle,
  and visible-set changes), not scroll alone. **The "compute the new centered item" step can
  legitimately find nothing** — the removed item may have been the last one visible, or the
  snapshot may be mid-transition with zero cells laid out yet — so `indexPathForItem(at:)`
  returning `nil` here must resolve to "nothing is playing," not a force-unwrap or crash.
- Nice-to-have, likely worth a line item in "what I cut": pause on
  `UIApplicationDidEnterBackground`. Not explicit in the written requirements, but is
  implied by "nothing keeps running off screen."

## 7. Pagination

- `refresh` param is the page cursor (0-indexed); `FeedRepository` owns `nextCursor`,
  `isLoading`, `isExhausted`.
- Guard against duplicate fetches: `willDisplay` can fire multiple times before a response
  returns — check `isLoading` before issuing a new request.
- Append with dedup by `game_id` before writing into `pages` — defensive, since a duplicate
  ID would break the diffable data source's identity guarantee.
- Exhaustion: an empty response (only possible with `--total` set) sets
  `isExhausted = true` and stops further fetches.

Starvation edge case: trigger the next-page fetch off `visibleItems` (post-filter)
proximity to the end, not `fetchedPages` proximity. If a fetched page is mostly/entirely
from a blocked creator, the raw count can look "full" while the *visible* count is nearly
exhausted — using the raw count as the trigger can leave the user scrolled to a dead end
with no fetch in flight.

### Creator page pagination (missing from the original draft)

README requires the creator's sekais to be paged too (`userGames`), and the original plan
only spelled out pagination state for the feed. It needs the same shape, owned by its own
repository, not folded loosely into `CreatorViewModel`:

- `CreatorGamesRepository` — mirrors `FeedRepository`: `page: Int` (starts at 0),
  `size: Int`, `isLoading: Bool`, `items: [FeedItem]` (raw, appended per page, deduped by
  `game_id` — same defensive reasoning as feed).
- **One real difference from feed pagination:** `userGames` returns `has_more` directly in
  its envelope — use that field as `hasMore`, don't re-derive exhaustion from an
  empty-page/`--total` inference like the feed has to. The feed only needs inference because
  `/game/feed` doesn't expose an authoritative flag; the creator endpoint does, so use it.
- `loadNextPage()` triggered the same way as feed's infinite scroll: proximity to the end of
  the *visible* (post-filter) items, not raw `items.count` — the same starvation caveat
  above applies here too.
- Filtering: reuse the **exact same** `visibleItems(pages:blocked:reported:)` free function
  from §2, passing this repository's `items` instead of the feed's `pages`. In practice
  `blockedCreatorIDs` rarely intersects here (you can't navigate to a blocked creator's page
  through the feed, since their cards are already hidden there), but passing it through is
  free and correct — and it means blocking *this* creator from their own `⋯` panel
  immediately empties this same page's list through the identical derivation, with no
  special-cased "also clear my own screen" logic. `reportedGameIDs` filtering still matters
  here on its own: an individual sekai can be reported without blocking the whole creator,
  and must stay hidden on that creator's own page too — a plain copy of the feed's filter
  that only checks `blockedCreatorIDs` would miss this.

## 8. Persistence

- `blockedCreatorIDs` and `reportedGameIDs` **must survive an app restart** — this is
  explicit in the grading table, not just "nice to have," and is easy to miss since nothing
  about it appears in the three headline "hard requirements."
- `UserDefaults` storing two `Set<String>` (as arrays) under fixed keys is the right-sized
  solution — load once in `ModerationStore.init`, write-through synchronously on every
  mutation. No CoreData/SQLite — that's scope creep for two small sets of strings.
- Nothing else is persisted: feed pages, WebView pool state, playback state, and scroll
  position are all fine to lose on relaunch — refetching from `refresh=0` reproduces the
  same deterministic content.

## 9. Network failure behavior

- `/game/feed` and creator-page fetches: surface a retryable error state (inline "Couldn't
  load — Retry"), reset the loading flag so a later `willDisplay`/manual retry can
  re-trigger — never leave `isLoading` stuck `true` on failure.
- Moderation POSTs: per §4, keep the optimistic hide on the ~20% failure rate; this decision
  (and the reasoning) belongs in the submission README, not just in code comments.
- WebView content load failures (`didFail`/`didFailProvisionalNavigation`): show a fallback
  state in the cell (placeholder, no play control), and make sure the playback coordinator
  can still settle *past* that cell without hanging — a failed load must not become a stuck
  `currentlyPlayingID`.
- All network calls are `URLSession` async/await inside `Task`s, off the main thread by
  construction; only the final `@Published` assignment hops to `DispatchQueue.main` /
  `@MainActor`.

## 10. Unit-test boundaries

Test the parts that carry the rules; skip anything that requires UIKit rendering (out of
scope per the assignment).

**Test:**
- The pure `visibleItems(pages:blocked:reported:)` function — table-test: item removed on
  block, removed on report, stays removed when re-delivered by a later page, restored to
  visibility is never possible without explicit unblock (not in scope, so no un-hide path
  should exist).
- `ModerationStore.block`/`.report` — idempotency, persistence round-trip (inject a test
  `UserDefaults(suiteName:)`).
- `PlaybackCoordinator.settled(on:)` — pure transition logic: differing IDs → pause old +
  play new; same ID → no-op; nil previous → play only.
- `FeedRepository` pagination — cursor increment, dedup-by-`game_id`, exhaustion on empty
  page (using fixture JSON, not a live server).
- `Codable` decoding for both response shapes — bare array (`/game/feed`) vs
  `{code,message,data}` envelope, snake_case keys, and `code != 0` mapped to a typed error.
- **The actual Combine publisher chain in `FeedViewModel`, not only the pure derivation
  function.** README calls out "data flows through a stream" as a graded property, and a
  pure-function test proves the filtering *logic* is right without proving the
  `CombineLatest3` wiring is connected correctly — publish a change on `FeedRepository` /
  `ModerationStore` and assert `FeedViewModel.visibleItems` updates through the real
  pipeline. If the pipeline includes `.receive(on: DispatchQueue.main)`, the test can't
  assert synchronously right after `.send()` — use an `XCTestExpectation` fulfilled inside
  the `sink`, not a bare assertion, or the test will read a stale value (or hang).

**Don't test:** WKWebView pool mechanics, collection view paging/layout, scroll-to-settle
wiring — these need instrumented manual verification (the frame-timing measurement) or UI
tests, which are explicitly out of scope.

## 11. Frame-timing measurement plan

Missing from the original draft: the plan discussed *design decisions* for performance
(the WebView pool) but never committed to a concrete measurement procedure. This is one of
the three named Hard Requirements, and the README explicitly disqualifies "it felt smooth" —
it wants "numbers, not adjectives" reported in the submission README. Decide this now, not
at the end:

- **Tool:** Instruments' "Hitches and Frame Rate" template (Xcode 12+). It reports
  hitch count and hitch-time ratio, which is the right metric here — not raw FPS, since
  target refresh rate varies by device (60 Hz vs. 120 Hz ProMotion) and Instruments
  normalizes for that. Prefer a physical device over the simulator; if only the simulator is
  available, say so explicitly in the submission README since simulator numbers aren't
  representative of real GPU/memory pressure.
- **Scenario (fixed and repeatable, not "scrolled around a bit"):** run against the mock
  server's *default* settings (~5 MB items, 350 ms latency) — not `--item-bytes` turned
  down for a lighter loop, since that would understate the real cost. Record one pass of
  continuous fast flicks through ~20 consecutive items with no pauses (the stress case most
  likely to reveal drops), and one pass of ordinary deliberate scrolling for comparison.
- **Metrics to record and report:**
  - Hitch count / hitch-time ratio for both passes (from Instruments).
  - Peak and steady-state memory during the fast-flick pass (Instruments' Allocations /
    memory graph on the same trace), to substantiate the WebView pool size decision (§5).
  - Live `WKWebView` count during the same window — cheap to expose via a debug counter
    incremented/decremented at pool assign/evict (§5) — cross-referenced against the memory
    timeline to demonstrate the pool bound (e.g. 3) is actually respected at runtime, not
    just asserted in code.
- **Deliverable:** the actual numbers from this procedure go in the submission app's
  README, with a one-line note on how they were captured — that's the grading artifact, this
  document is only the plan for producing it.

## 12. Screen-recording acceptance flow

Missing from the original draft: the README requires a ~1 minute recording and says
explicitly that several requirements ("immediate removal, no reappearance, one item
playing") are "only visible in motion" — so this needs to be treated as an acceptance test
run against the finished app *before* the final recording, not an afterthought once coding
feels done. A failure at any step here is a P0 blocker, not a nit.

Rehearsal script (matches the README's ask, expanded to touch each hard requirement):

1. Fresh launch (clean state) → scroll through a few items → confirm the settled item's own
   on-page UI shows `PLAYING` with its frame counter incrementing, and the previously-settled
   item shows `PAUSED` — the mock content page renders this itself specifically so a
   recording can verify the play/pause contract without any extra instrumentation.
2. Block a creator from a feed item → toast appears, item disappears **immediately** (not
   after the ~350 ms round trip).
3. Scroll back up past where that item was → confirm it does not reappear.
4. Keep scrolling forward through pagination (into pages not yet fetched at block time) →
   confirm none of that creator's other items (`game_id % 7` match) ever appear.
5. Open a *different* (non-blocked) creator's page → observe profile info + their paged
   sekai list.
6. Open the `⋯` panel → Block → toast → every sekai on this page disappears immediately.
7. Navigate back to the feed → confirm that creator's items are also gone there — this is
   the only place the shared-`ModerationStore` requirement (§1) is actually visible; it's
   invisible in a code read.
8. Time permitting: report a single item (not a full block) → toast → only that one item
   disappears, demonstrating report and block are independently derived.

Run this whole sequence as a real rehearsal pass — treating it as the closest thing to an
end-to-end acceptance test, since automated UI tests are explicitly out of scope (§10) —
before recording the take that ships.

## Edge cases and requirements that are easy to violate (consolidated)

1. **Filter-on-write instead of derive-on-read.** Filtering new items at fetch time
   (`newItems.filter { !blocked.contains(...) }` before appending) looks equivalent to the
   derivation but silently breaks once a block happens *after* a page was already
   appended — only recombining on every read is actually correct.
2. **Two `ModerationStore` instances** (one built per screen instead of injected) — block on
   the feed won't hide items on the creator page, or vice versa.
3. **Play/pause hooked to `scrollViewDidScroll`** instead of the "did end" callbacks — fires
   on every intermediate cell during a flick, violating "exactly one playing."
4. **WebView not paused on pool eviction** — a cell scrolled out of the live window keeps
   its animation running until the WebView is reused, unless pause is called explicitly at
   eviction, not just at "new settle."
5. **Stale async completions after cell/WebView reuse** — a `load()` or moderation POST that
   completes after its cell has been reassigned to a different item must be identity-checked
   before acting on it.
6. **`sekaiPlay()` fired before `didFinish`** — calling it immediately after `load(_:)` races
   the page's own script execution.
7. **`webViewWebContentProcessDidTerminate` unhandled** — a WebContent process death under
   memory pressure permanently blanks that cell with no recovery path.
8. **Double-fetch on `willDisplay`** — without an `isLoading` guard, near-end proximity can
   trigger duplicate page requests before the first resolves.
9. **Pagination starvation from filtered pages** — see §7; using raw fetched count instead
   of visible count as the "near end" signal can leave the feed looking exhausted early.
10. **No persistence for blocked/reported IDs** — explicitly graded ("...and an app
    restart"), but absent from the three headline hard requirements, so easy to deprioritize
    by accident.
11. **Reverting the optimistic hide on the ~20% moderation failure** — technically "safer"
    sounding, but wrong for this feature: it resurrects content the user already asked to
    hide.
12. **No app-backgrounding pause** — not written explicitly, but implied by "nothing keeps
    running off screen"; worth a conscious cut decision if time runs out, not a silent
    omission.
13. **Asserting frame smoothness instead of measuring it** — the requirement explicitly
    disqualifies "it felt smooth"; an actual instrumented number (CADisplayLink-based drop
    counter or an Instruments trace) is required.
14. **`orthogonalScrollingBehavior`/`.groupPagingCentered` used for main-axis paging** —
    that API pages a section's *orthogonal* (cross-axis) scrolling, not the collection
    view's primary scroll direction; it silently does nothing for vertical snap-paging.
    Use `UICollectionViewFlowLayout` + `collectionView.isPagingEnabled = true` with
    `itemSize == bounds.size` and zero spacing instead.
15. **Settle missed on a drag that never decelerates** — relying only on
    `scrollViewDidEndDecelerating` misses `scrollViewDidEndDragging(willDecelerate: false)`,
    so a slow drag-and-release can land on a new item that never receives a play command.
16. **Playing item removed by the user's own moderation action, with no scroll to trigger
    reconciliation** — reporting/blocking the currently-playing item removes it from
    `visibleItems` without any scroll event; if playback is wired to scroll-settle only,
    the old item is never paused and nothing new is ever played until the next unrelated
    scroll. Playback must also reconcile whenever `visibleItems` changes.
17. **Frame-timing requirement satisfied by "it felt fine" instead of a committed
    measurement procedure** — README explicitly disqualifies adjectives; without deciding
    the tool/scenario/metrics up front (§11), it's easy to arrive at submission time with no
    real numbers to report.
18. **Screen recording treated as a last-step formality instead of an acceptance test** —
    several hard requirements are only checkable in motion; recording it for the first time
    at the very end, instead of rehearsing the flow in §12 beforehand, is how a late-stage
    regression (e.g. a reappearing blocked item) ships unnoticed.
19. **Creator page pagination copied from the feed but missing `has_more`** — `userGames`
    gives an authoritative `has_more`; re-deriving exhaustion by inference (the way the feed
    has to, since `/game/feed` has no such field) is unnecessary and easy to get subtly
    wrong on the creator page specifically.
20. **Toast dropped entirely, or contradicted after a failed background retry** — it's an
    explicit written requirement ("A toast confirms what happened"), easy to deprioritize
    while focused on the harder concurrency/lifecycle issues; and per the "don't revert"
    decision (§4/§9), a second toast walking back the first after a failed moderation POST
    would undermine the very confirmation the first toast gave.
