# Performance

All numbers below are real measurements from this project's `PerformanceTests` suite (`swift test --filter Performance`), which generates a workspace of **2,000 notes** (≈2.6 KB each, spread across three folders, with links, tags, and task lines) and times the operations end-to-end on the main thread where the app would run them.

## Environment

- Apple Silicon Mac (arm64), macOS 27.0.1 (26A434)
- Swift 6.4 (swiftlang-6.4.0.34.1), Command Line Tools toolchain
- Release configuration (`swift test -c release --filter Performance`)
- Local APFS volume (temporary directory)

## Results (release build, 2,000 notes)

| Operation | Time | Notes |
| --- | --- | --- |
| Full vault scan (tree walk + mtime stat) | **272 ms** | one-time per workspace open |
| Full index build (parse + analyze + FTS insert, all notes) | **3.7 s** | one-time, runs on a background queue with a progress indicator |
| 20 mixed searches (term, tag:, path:, phrase, exclusion) | **83 ms** total | ≈4 ms per query |
| Single-note re-index (edit → index update) | **2.0 ms** | the steady-state cost while typing |

Debug configuration, same machine: scan 421 ms, index 4.2 s, 20 searches 85 ms, re-index 2.2 ms.

## Reading the numbers

- The only per-keystroke costs are paragraph-scoped syntax highlighting (O(edited paragraph)) and the 2 ms incremental index update (debounced 0.25 s, background queue). Typing stays interactive regardless of vault size.
- The one-time index build is dominated by markdown parsing (swift-markdown AST) and runs off the main thread; the UI shows progress and remains responsive.
- Search runs on a background serial queue with a 150 ms debounce; the FTS5 queries over 2,000 notes are ~4 ms each. CJK queries fall back to LIKE scans, which are slower but still bounded by the note count.

## Design rules enforced in code

- No disk scans, whole-vault parsing, or network calls on the main thread.
- FSEvents callbacks are coalesced (0.2 s) before any rescan.
- Search is debounced and cancellable; index rebuilds are generation-guarded so a stale rebuild never overwrites a newer one.
- The graph caps rendered nodes (default 250, slider 40–400) and pre-filters by degree.
- The editor highlights only the edited paragraph range; a full pass happens on load and appearance changes only.

## Reproducing

```bash
swift test -c release --filter Performance
```

The test prints `PERF <operation>: <ms>` lines and deletes its generated workspace afterwards. Numbers vary with hardware; if you rerun, note your machine and OS version.
