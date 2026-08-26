# Platform & scope

- **iOS only.** Do not create or scaffold an Android/Kotlin counterpart.
- **Deployment target: iOS 15.** Do not use `Observation` / `@Observable`, or any other
  API newer than iOS 15, even if Xcode suggests it. If a suggestion depends on a newer OS,
  say so instead of using it.
- **No third-party state library** (no ReactiveSwift, no RxSwift) unless the user explicitly
  asks for TCA. Default toolkit: Combine (`CurrentValueSubject`, `@Published`, `combineLatest`,
  `.assign`/`.sink`) or plain `AsyncStream`. Shared Kotlin `Flow`s bridged via SKIE are out of
  scope here since this is an iOS-only submission — don't introduce a KMP module.
- **Design polish is out of scope.** Use system/platform-default UI. Don't spend time on
  custom styling, animations, or theming unless asked.
- Do not build the Android app "just to compare" or scaffold both platforms.
