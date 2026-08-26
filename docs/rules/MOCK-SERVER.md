# Mock server (`mock/`)

- **Do not modify `mock/server.py` or `mock/README.md`** — the take-home is graded by running
  the submitted app against this exact server. If a change genuinely seems necessary, stop and
  ask first, and it must be called out explicitly in the app's own README with a reason.
- Treat its documented quirks as fixed constraints, not bugs to "fix": `GET /game/feed` returns
  a bare JSON array while every other endpoint wraps in `{code, message, data}`; wire format is
  `snake_case`; moderation POSTs fail ~20% of the time on purpose (`--fail-rate`).
- iOS simulator reaches the server at `http://127.0.0.1:8787` directly. Both endpoints need an
  ATS / App Transport Security localhost exception in `Info.plist` — add it and note it in the
  app README, don't silently disable ATS globally.
- When testing, prefer smaller/faster flags for iteration (`--item-bytes`, `--latency-ms`,
  `--total`) but validate the final behavior against the real ~5 MB / default-latency
  defaults before calling something done.
