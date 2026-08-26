# Implementation slices — execution plan

This is the cross-session execution plan built on top of `docs/architecture-plan.md` (the
contract). Each slice below is meant to be handed to Claude as its own session/prompt —
possibly a different session than the one that did the previous slice — so this document is
the shared source of truth for what's done, what's next, and exactly what to ask for.

## Ground rules

- **One architectural concern per slice.** Don't ask for two slices' worth of work in one
  prompt, even if it seems faster — mixing concerns is how a bug's root cause becomes
  ambiguous (Combine wiring vs. UIKit vs. WKWebView).
- **Build (and test, where the slice has tests) before ending.** Never accept "this should
  compile" — actually run `xcodebuild build` / `xcodebuild test` and fix errors before the
  slice is considered done.
- **Review the diff for unnecessary abstractions** before committing — this project
  prioritizes correctness and simplicity over abstraction (see `WORKING-STYLE.md`,
  `SWIFT-STYLE.md`).
- **Commit at the end of each slice**, once build/test pass and the diff has been reviewed —
  this gives every slice a clean rollback point and lets a fresh session `git log` its way
  into context instead of re-deriving it.
- **After finishing a slice, update the status table below** (mark it Done, note the commit)
  so the next session — even a completely fresh one with no memory of this conversation —
  knows exactly where things stand by reading this file plus `docs/architecture-plan.md`.

## Status

| Slice | Concern | Status |
|---|---|---|
| 0 | Project bootstrap + mock-server connectivity proof | Done (`8138576`, branch `huanzhiNB/slice-1-models-api`) |
| 1 | Models + `APIClient` | Done (`b4f1b53`, branch `huanzhiNB/slice-1-models-api`) |
| 2 | `ModerationStore` + tests | Done (`50914d8`, branch `huanzhiNB/slice-2-moderation-store`) |
| 3 | `FeedRepository` + reactive `FeedViewModel` | Done (`97254cd`, branch `huanzhiNB/slice-3-feed-repository-viewmodel`) |
| 4 | Feed UI without WKWebView | Done (`48a91bc`, branch `huanzhiNB/slice-4-feed-ui`) |
| 5 | Creator page | Done (`7cfc87b`, branch `huanzhiNB/slice-5-creator-page`) |
| 6a | WKWebView/playback risk analysis (no code) | Done (analysis in slice 6b's commit message context, `1826655`, branch `huanzhiNB/slice-6-webview-playback`) |
| 6b | WKWebView/playback implementation | Done (`1826655`, branch `huanzhiNB/slice-6-webview-playback`) |
| — | Requirement audit (hostile reviewer pass) | Not started |
| — | Manual acceptance test (§12 rehearsal script) | Not started |
| — | Instruments measurement (§11) | Not started |
| — | Measured-bottleneck analysis + one-change-at-a-time optimization | Not started |
| — | Final submission audit | Not started |
| — | App README + screen recording | Not started |

---

## Slice 0 — Project bootstrap + mock-server connectivity proof

No Xcode project exists yet. This slice is pure infrastructure — no feature code — so that
every later slice is debugging feature logic, never debugging whether the project itself is
configured correctly.

**Scope:**
- Xcode project generated via `xcodegen` from a committed `project.yml` (deterministic,
  diffable — not a hand-edited `.pbxproj`).
- Programmatic UIKit app target (no storyboards; `UILaunchScreen = {}` in Info.plist),
  iOS 15.0 deployment target, an empty test target that actually runs.
- `Info.plist` ATS exception scoped to `127.0.0.1` only (not a blanket
  `NSAllowsArbitraryLoads`).
- One screen: a label that calls `GET /health` via `URLSession` async/await on launch and
  shows "Mock server: ok" or "Mock server: unreachable."
- `HealthCheckClient` — not throwaway; the seed of the shared network client Slice 1 extends.

**Files:**
```
project.yml
FeedModerationDemo.xcodeproj/                         (generated)
Sources/FeedModerationDemo/Info.plist
Sources/FeedModerationDemo/App/AppDelegate.swift
Sources/FeedModerationDemo/App/SceneDelegate.swift
Sources/FeedModerationDemo/App/RootViewController.swift
Sources/FeedModerationDemo/Networking/HealthCheckClient.swift
Tests/FeedModerationDemoTests/HealthCheckClientTests.swift
```

**Verify:**
1. `xcodegen generate` succeeds.
2. `xcodebuild ... build` succeeds.
3. `xcodebuild ... test` succeeds (the one real decoding test passes).
4. Start `python3 mock/server.py`, run the app in the simulator, confirm the label reads
   "Mock server: ok."
5. Stop the mock server, relaunch, confirm "Mock server: unreachable" with no crash.

---

## Slice 1 — Models + `APIClient`

**Prompt:**
```
Implement slice 1 only: models and networking.

Scope:
- FeedItem
- UserProfile
- userGames response
- generic wrapped API response where appropriate
- APIClient
- GET feed
- GET userProfile
- GET userGames
- POST blockUser
- POST reportContent
- snake_case decoding
- bare-array feed response
- non-zero API code as an error
- HTTP error handling

Use URLSession async/await.
Keep this implementation small.
Do not implement repositories, view models, moderation state, or UI yet.

After implementation:
1. Build the project.
2. Fix compilation errors.
3. Review your own diff for unnecessary abstractions.
4. Summarize exactly what changed and any assumptions.
```

**Human review checklist before committing:**
- Feed bare-array decode correct?
- `userGames` `has_more` decoded correctly?
- POST body shape correct (`{"user_id": ...}` / `{"game_id": ..., "reason": ...}`)?
- `code != 0` handled as an error, not silently ignored?

If clean, commit.

---

## Slice 2 — `ModerationStore` + tests

The single most important slice — this is where `visible = fetched - blocked - reported`
gets proven correct, before any UI exists to obscure whether it actually works.

**Prompt:**
```
Implement slice 2: global moderation state.

Before writing production code, add unit tests that encode these requirements:

1. Reporting a game hides that game.
2. Blocking a creator hides every game from that creator.
3. Other games from the same creator remain visible after reporting only one game.
4. A game from an already-blocked creator remains invisible when it arrives in a later
   fetched page.
5. Reported game IDs survive recreation of ModerationStore.
6. Blocked creator IDs also survive recreation as our deliberate product choice.
7. Repeating the same block/report operation is idempotent.

Then implement the minimum production code to satisfy those tests.

Architecture constraints:
- ModerationStore owns only blockedCreatorIDs and reportedGameIDs.
- It does not know about UICollectionView or feed UI.
- Visible games are derived using the shared pure filtering function.
- Never remove games imperatively from fetched arrays.
- Use injectable persistence so tests do not touch production UserDefaults.

Build and run the tests when finished.
```

Note on requirement 6: README's grading text only explicitly requires *reported* items to
survive a restart. Treating blocked-creator persistence the same way is a deliberate,
documented product choice (consistency — it would be strange for report to persist and block
not to), not a literal requirement — say so in the submission README.

---

## Slice 3 — `FeedRepository` + reactive `FeedViewModel`

**Prompt:**
```
Implement slice 3: feed repository and reactive FeedViewModel.

Requirements:
- FeedRepository owns raw fetched items.
- It owns refresh cursor, isLoading, and exhaustion state.
- loadNextPage() appends raw fetched results.
- Deduplicate by game_id.
- Do NOT apply moderation filtering inside FeedRepository.

FeedViewModel derives visibleItems reactively from:
- FeedRepository fetched items
- ModerationStore blockedCreatorIDs
- ModerationStore reportedGameIDs

Use Combine as described in Architecture plan.

Add tests for the actual reactive wiring, especially:

1. Page 1 contains creator A and B.
2. Block A.
3. visibleItems contains only B.
4. Append a later page containing another creator A game.
5. visibleItems must still exclude it automatically.

Do not implement UICollectionView or WKWebView yet.

Build and run tests.
```

**Important:** README explicitly grades "data flows through a stream," so this slice needs a
test that exercises the *actual* `CombineLatest3` pipeline in `FeedViewModel` — not only the
pure `visibleItems(pages:blocked:reported:)` function from Slice 2. A pure-function test
proves the filtering logic is right; it doesn't prove the publisher chain is wired correctly.
If the pipeline includes `.receive(on: DispatchQueue.main)`, the test cannot assert
synchronously right after `.send()` — use an `XCTestExpectation` fulfilled inside the `sink`,
or the test will read a stale value (or hang).

---

## Slice 4 — Feed UI without WKWebView

Deliberately no WebView yet — isolates UIKit/Combine/diffable-data-source bugs from
WKWebView/JS/pool bugs, which is the highest-risk layer (Slice 6).

**Prompt:**
```
Implement slice 4: the feed UI without WKWebView content yet.

Build:
- FeedViewController
- vertical UICollectionViewFlowLayout
- full-bounds item size
- zero spacing
- isPagingEnabled = true
- UICollectionViewDiffableDataSource keyed by game_id
- simple placeholder cell showing title, creator, Report, and Block
- tapping creator opens a temporary placeholder creator screen
- pagination when approaching the end
- immediate Report / Block through ModerationStore
- toast event through PassthroughSubject

Important:
- UI must render visibleItems from FeedViewModel.
- Report/Block handlers must never manually remove collection-view items.
- Snapshot changes must come from visibleItems emissions.

Do not add WKWebView yet.

Build and manually verify:
1. vertical paging
2. pagination
3. block immediately removes all fetched games by that creator
4. report removes only one game
5. scrolling back does not restore hidden content
6. later pagination does not restore blocked content
```

**Why this ordering matters:** if `block creator → UI bug` shows up now, the bug space is
Combine/diffable-data-source/UICollectionView — not WKWebView reuse/JS/navigation/pool. Much
smaller surface to debug.

---

## Slice 5 — Creator page

**Prompt:**
```
Implement slice 5: Creator page.

Requirements:
- Fetch userProfile.
- Fetch paged userGames.
- Use page/size/has_more exactly as returned by the API.
- Display avatar, creator name, and games.
- Add the top-right ... button with a Block action.
- Creator games must use the same global ModerationStore.
- visible creator games must use the same shared visibility derivation as the feed.
- Reported games must also remain hidden here.
- Blocking the creator must immediately remove all their games.
- Show the Block toast.
- Pop back to the feed after blocking.

Add focused tests for creator pagination / moderation derivation where useful.

Do not implement WKWebView changes in this slice.

Build and manually verify the cross-screen block behavior.
```

After this slice, all product logic is done except WebView/playback/performance.

---

## Slice 6a — WKWebView/playback risk analysis (no code)

Two-phase by design: analyze failure modes and invariants first, get them reviewed, *then*
implement against them. This is the highest-risk slice — treat it accordingly.

**Prompt:**
```
We are about to implement the highest-risk slice: WKWebView lifecycle and playback.

Re-read sections 5 and 6 of Architecture plan.

Before modifying code, inspect the existing feed implementation and give me concrete failure
sequences for:

1. fast scrolling through several items
2. WebView reassignment while navigation is still loading
3. sekaiPlay requested before didFinish
4. currently playing item being reported
5. currently playing creator being blocked
6. cell reuse
7. pooled WebView eviction
8. slow drag ending without deceleration
9. WebContent process termination under memory pressure (webViewWebContentProcessDidTerminate)

For each, explain what invariant the implementation must maintain.

Do not write code yet.
```

Review the reasoning before proceeding to 6b. (Failure sequence 9 was added to the original
8-item list — `webViewWebContentProcessDidTerminate` is a real, documented risk in §5 of the
architecture plan given a pooled WebView repeatedly loading ~5 MB pages under memory
pressure.)

---

## Slice 6b — WKWebView/playback implementation

**Prompt:**
```
Now implement the WKWebView/playback slice according to those invariants and Architecture
plan.

Important invariants:

- Exactly one settled item plays.
- Intermediate items crossed during fast scrolling do not play.
- Previous playing item pauses before a new item plays.
- No WebView continues running after eviction.
- sekaiPlay is deferred until navigation is ready.
- Stale navigation callbacks cannot act on a reassigned game.
- Removing the currently-playing item through moderation reconciles playback even though no
  scroll event occurred.
- didEndDragging(willDecelerate: false), didEndDecelerating, and didEndScrollingAnimation
  all reconcile settled playback.
- Reconciliation that finds no centered item to play (empty visible set, or a snapshot
  mid-transition) resolves to "nothing is playing" — never a force-unwrap or crash.

Do not modify moderation or networking architecture while implementing this slice.

Build after implementation.
```

Do not immediately continue adding features after this builds — switch roles next.

---

## Post-implementation: hostile reviewer pass

Switch Claude from *implementer* to *reviewer*. This prompt is deliberately narrow — it
exists specifically to prevent "maybe introduce protocol X..." scope creep from an AI that
just finished building the thing.

**Prompt:**
```
Stop implementing features.

Re-read the original take-home README from beginning to end.

Audit the current repository as if you were a Sekai senior iOS engineer reviewing a
candidate submission.

Do not modify code.

For every explicit requirement, report:

- PASS
- FAIL
- UNCERTAIN / requires runtime verification

For FAIL:
identify the exact code path responsible.

For UNCERTAIN:
give me the exact manual test or Instruments measurement needed.

Focus on correctness and the grading rubric, not style.
Do not recommend optional refactors or architecture improvements.
```

## Post-implementation: manual acceptance test

Run the §12 rehearsal script from `docs/architecture-plan.md` against the real app —
treat it as an acceptance test, not a formality before recording.

## Post-implementation: Instruments measurement

Run the §11 measurement plan from `docs/architecture-plan.md` on a real device where
possible. Get real numbers — hitch count/ratio, memory, live `WKWebView` count. Do not let
Claude assert smoothness; only real Instruments output counts.

**Then hand the real numbers to Claude:**
```
Here are my actual Instruments results:

Device:
...
Scenario:
...
Hitch count:
...
Hitch-time ratio:
...
Memory:
...
Live WebViews:
...

Do not modify code yet.

Inspect the WebView/feed implementation and rank the three most likely causes of the
measured hitches by:
1. expected performance impact
2. confidence
3. implementation risk

Recommend the smallest experiment that would validate each hypothesis.
```

**Then, one variable at a time:** measurement → hypothesis → change *one* thing → remeasure.
Never "Claude thinks 5 optimizations sound good, implement all 5" — that makes it impossible
to know afterward which change actually helped.

## Post-implementation: final submission audit

**Prompt:**
```
Perform a final submission audit.

Do not modify code.

Check only:
1. every take-home requirement
2. correctness of moderation derived state
3. playback correctness
4. WebView lifecycle/memory risks
5. creator-page behavior
6. persistence
7. pagination
8. tests
9. error behavior
10. whether README claims are supported by the actual implementation and measurements

Separate findings into:
- submission blocker
- should fix
- optional

Do not report style preferences.
```

Fix only **submission blocker** and genuinely meaningful **should fix** items. Then freeze
the code.

## Post-implementation: README + recording

Write the submission README (how to run, what was cut, real frame-timing numbers, moderation
failure behavior, the design decisions this project's docs already argued for — e.g.
optimistic-hide-never-reverts, blocked-creator persistence as a deliberate choice) and record
the take following the §12 script.

---

## Full pipeline

```
Architecture plan (docs/architecture-plan.md)
       ↓
Slice 0 — bootstrap                          ↓ build
Slice 1 — Models + API                       ↓ build
Slice 2 — Moderation + tests                 ↓ test
Slice 3 — Feed reactive state                ↓ test
Slice 4 — Feed UI placeholder                ↓ manual test
Slice 5 — Creator page                       ↓ manual test
Slice 6a — WKWebView risk analysis (no code)
Slice 6b — WKWebView + playback              ↓ build
Requirement audit (hostile reviewer)
Manual acceptance test (§12 rehearsal)
Instruments measurement (§11)
AI analyzes measured bottlenecks
One-variable-at-a-time optimization → remeasure
Final submission audit
README + recording
```
