# Architecture

## Pattern

- **MVVM required.** All new code follows Model-View-ViewModel. Do not introduce new MVC,
  Handler, Builder, or Coordinator patterns.
- **ViewModel naming:** `XxxViewModel` (e.g. `FeedViewModel`, `ProfileViewModel`). ViewModels
  must be testable — do not `import UIKit` in a ViewModel.
- **Model naming:** name models after the domain object itself (`News`, `Comment`, `User`).
  Do not use an `XxxDataModel` suffix.
- **Dependency injection only.** Never let a class find its own dependencies — pass everything
  in via `init` or a `configure` method. Do not access singletons (`.shared`,
  `.sharedInstance()`) from new code.
- **Navigation via Router, not Coordinator.** Use a `Router` per feature domain (`FeedRouter`,
  `ProfileRouter`, `VideoRouter`, …). Do not write a Coordinator-style class (one that owns a
  `UINavigationController`, manages child flows, or exposes a `start()` method).

## The one rule that matters

The visible feed must be **derived**, not mutated:

```
visibleFeed = fetchedPages - blockedCreators - reportedSekais
```

That means one source of truth (fetched pages) combined with block/report state through a
`Combine` operator (`combineLatest`, `map`, etc.) into the list the UI renders — not
`list.remove(...)` called from the block handler, the report handler, and again after each
page fetch. If you (Claude) are about to write code that mutates an array in place from a
moderation action handler, stop and route it through the derivation instead. This is the
single thing the exercise's grading rubric weights most heavily — do not shortcut it even
under time pressure.

Newly blocked/reported IDs must persist across: scrolling back up, a later page fetch that
re-delivers the same item, and opening the creator's own profile page (which paginates the
same `game_id`s the feed does — see `mock/server.py`, creators repeat every 7 items).
