# Swift style

## Language: Swift only

- New files must be Swift — do not introduce new `.m` or `.h` files. Modifying an existing
  Objective-C file is fine; there aren't any in this repo yet.

## Code quality

- **No force unwraps (`!`).** Use `guard let`, `if let`, or `??` instead. Exceptions: IBOutlets
  and test code.
- **No force casts (`as!`).** Use `as?` with proper handling.
- **No force try (`try!`).** Use `do`/`catch` or `try?`.
- **No implicit `self`.** Use explicit `self` in closures so capture semantics are visible.
- **Most restrictive access control possible** (`private`, `fileprivate`, `internal`). Don't
  mark things `public`/`open` by default.
- **`final` by default.** Mark classes `final` unless they're explicitly designed for
  subclassing.

## Memory management

- Use `[weak self]` or `[unowned self]` in escaping closures to avoid retain cycles.
- Delegate properties are `weak`.
- No circular strong references between objects.

## Concurrency

- All UI updates happen on the main thread — `@MainActor`, `DispatchQueue.main`, or
  `MainActor.run`.
- Never call `DispatchQueue.main.sync` from the main thread (deadlock risk) — use
  `DispatchQueue.main.async`, or check whether you're already on main first.
- Prefer structured concurrency (`async`/`await`, `Task`) over raw GCD for new code.

## Style

- Follow Swift API Design Guidelines: `camelCase` for variables/functions, `PascalCase` for
  types/protocols.
- Prefer `let` over `var` — only use `var` when mutation is actually required.
- Prefer value types — `struct` over `class` when reference semantics aren't needed.
- Use `guard` for precondition checks and early returns instead of nested `if`.
- Use trailing closure syntax when the last parameter is a closure.
