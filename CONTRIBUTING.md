# Contributing

Thanks for helping make Sakura Notes better!

## Setup

```bash
git clone https://github.com/yueseqaz/sakura-notes.git
cd sakura-notes
swift build          # or: swift run to launch the app
bash scripts/test.sh # run the test suite
```

Requirements: macOS 14+, Swift 6 toolchain (Xcode 16+ or Command Line Tools). On CLT-only machines the test script handles the Swift Testing macro plugin automatically.

## Project layout

```
Sources/
  SakuraCore/       pure markdown/logic layer (no UI, no file I/O)
  SakuraStorage/    vault, files, snapshots, workspaces
  SakuraSearch/     FTS5 index, search coordinator, link index
  SakuraAI/         OpenAI-compatible client, prompts, runners
  SakuraNotesApp/   the application (SwiftUI + AppKit)
Tests/SakuraNotesTests/
docs/
scripts/
```

Dependencies point downward only: App → Storage/Search/AI → Core. UI code lives exclusively in `SakuraNotesApp`.

## Ground rules

- **Data safety first.** Anything that writes user files must use `AtomicFile`, respect `VaultStore`'s conflict detection, and prefer the Trash. If your change can overwrite a note, it needs a snapshot and a test.
- **Test what you change.** New behavior in Core/Storage/Search gets tests in `Tests/SakuraNotesTests`. Run the suite before pushing; CI enforces it on macOS.
- **Keep the module boundaries.** No `import SwiftUI` below the app target. Pure logic goes in Core so it stays testable.
- **Match the design language.** Restrained, typography-led, native controls; spacing/colors come from the `DS` namespace. If a view needs local state, use the `VS` wrapper (see `ViewState.swift` for why it exists).
- **Honesty over polish.** Don't ship decorative buttons, fake results, or claims the tests don't back.

## Commit style

Short imperative subject (`Fix task parsing for cmark checkboxes`), a body explaining the *why* when it isn't obvious. Keep commits buildable; `swift build` before you commit.

## Pull requests

1. Fork/branch from `main`.
2. Make your change with tests.
3. `bash scripts/test.sh` green, `swift build` warning-clean for new code.
4. Describe what changed and why; note any behavior change visible to users so it can be added to the changelog.

## Reporting bugs

Open an issue with the macOS version, how you ran the app (swift run vs. built .app), and steps to reproduce. For data-loss concerns, please use a security advisory instead (see SECURITY.md).
