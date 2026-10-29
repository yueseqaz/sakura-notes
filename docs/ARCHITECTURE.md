# Architecture

Sakura Notes is a Swift package with four library modules and one app target. Dependencies point strictly downward; nothing in `SakuraCore` imports UI code, and the app target is the only place AppKit/SwiftUI appear.

```
┌──────────────────────────────────────────────────────┐
│ SakuraNotesApp (UI)                                  │
│ SwiftUI views · AppKit editor · WKWebView preview    │
│ panels · settings · quick capture · menus            │
└──────┬──────────────┬───────────────┬────────────────┘
       │              │               │
┌──────▼─────┐ ┌──────▼──────┐ ┌──────▼──────┐
│ SakuraStore│ │SakuraSearch │ │ SakuraAI    │
│ rage       │ │ FTS5 index  │ │ client      │
│ vault I/O  │ │ link index  │ │ prompts     │
│ snapshots  │ │ coordinator │ │ runners     │
└──────┬─────┘ └──────┬──────┘ └──────┬──────┘
       └──────────────┼───────────────┘
              ┌───────▼────────┐
              │  SakuraCore    │
              │ markdown AST   │
              │ front matter   │
              │ analyzer       │
              │ HTML renderer  │
              │ diff · query   │
              │ parser · templ.│
              └────────────────┘
```

## Modules

### SakuraCore
Pure logic with one external dependency: Apple's [swift-markdown](https://github.com/swiftlang/swift-markdown) (CommonMark/GFM AST).

- `FrontMatter` — parses a pragmatic YAML subset (scalar keys, block and flow lists). Unknown keys are preserved verbatim and round-trip safely.
- `NoteAnalyzer` — derives outline, tasks, inline tags, wiki links, external links, word counts, and reading time from a document in a single AST walk. cmark consumes task-list checkboxes into `ListItem.checkbox`; the analyzer reads that instead of text prefixes.
- `HTMLRenderer` — walks the AST to produce sanitized HTML: raw HTML (block and inline) is dropped, text is escaped, tables/checkboxes/mermaid get semantic markup. Math is left for KaTeX auto-render.
- `LineDiff` — LCS-based line diff with a size budget; used by conflict sheets, history, and AI review.
- `SearchQueryParser` — parses the operator query language into a structured query.
- `TemplateEngine` — expands `{{title}}`, `{{date}}`, `{{time}}`, `{{weekday}}`, `{{date:FORMAT}}`.

### SakuraStorage
Everything that touches your files.

- `VaultStore` — the model of a workspace folder. Owns the tree (folders/notes), all mutations (create/rename/move/duplicate/trash), atomic writes, external-change detection, and per-vault metadata (`.sakuranotes/meta.json`). All API is main-thread confined; scanning runs on a background queue and publishes results on main. FSEvents (via `FSEventsMonitor`) triggers a debounced rescan whose diff against tracked mtimes produces precise add/modify/remove events for observers.
- `AtomicFile` — temp file + `fsync` + `rename(2)`: an interrupted write can never truncate an existing note.
- `SnapshotStore` — version history as plain ISO-8601-named `.md` files under Application Support, with per-note retention. Snapshots are captured before risky overwrites (external changes, conflict resolution, AI edits, restores).
- `WorkspaceStore` — the list of workspaces and recent files as JSON in Application Support.

**Path safety:** relative paths from any user-controlled source must pass `VaultStore.isSafeRelativePath` (no leading `/`, no `.`/`..` components) before reaching `absoluteURL(for:)`, which asserts the invariant for internal callers.

### SakuraSearch
Derived, rebuildable indexes.

- `FTSIndex` — SQLite FTS5 (WAL mode) over title/body/tags plus a metadata table. Supports prefix/phrase/exclusion matching, operator filters, recency ordering, snippet highlighting, and a LIKE-based fallback for CJK text that the unicode61 tokenizer cannot segment. All operations run on an internal serial queue.
- `SearchCoordinator` — wires `VaultDelegate` events into incremental index updates (debounced, cancellable), runs full rebuilds with progress, and executes debounced searches off the main thread.
- `LinkIndex` — wiki link resolution (exact path → title → file name, same-folder preference), backlinks, broken links, orphans, and graph snapshots. Thread-safe.

### SakuraAI
- `OpenAIClient` — chat completions (streaming via SSE) against any OpenAI-compatible endpoint, with typed error mapping (401/429/5xx/network/malformed).
- `KeychainStore` — API keys only ever live in the Keychain.
- `PromptLibrary` — the built-in action catalog and prompt construction.
- `AIActionRunner` / `AIContextBuilder` — streaming execution with a bounded, explicitly-selected context payload; request summaries contain counts only, never note content.

### SakuraNotesApp (UI)
- `AppEnvironment` — the dependency container: builds the vault, index, link graph, sessions; routes vault events; owns the conflict queue and facts cache.
- `NoteSession` — one open note buffer: text, dirty state, debounced autosave, facts recomputation, conflict detection (`externalFileChanged`, save-time mtime compare-and-swap) and resolution.
- `WorkspaceModel` — tabs (with pinning), sidebar selection, note-list filtering/sorting, editor mode.
- `EditorTextView` — AppKit `NSTextView` subclass: incremental markdown highlighting (paragraph-aligned, triggered on edit), automatic list continuation, image paste/drop, formatting selectors as responder-chain targets (menu items route there), wiki-link autocomplete via a floating panel.
- `MarkdownPreviewView` + `PreviewSchemeHandler` — the preview is sanitized HTML rendered in a WKWebView served over a custom `sakura-preview://` scheme: the web view has no file access; the handler serves the document, bundle assets, and vault media only. highlight.js, KaTeX (fonts embedded), and Mermaid ship in the bundle; nothing loads from the network. Navigation to external URLs opens the browser.
- `LinkUpdater` — rewrites wiki/relative links after moves, snapshotting each modified note.
- `ViewState` (`VS`) — a macro-free `@State` replacement (see below).

## Data flow: saving a note

1. Typing → `EditorTextView` delegate → `NoteSession.textDidChange` → dirty flag + autosave timer + facts refresh.
2. Timer fires → `vault.writeNote(path, content, requireUnchangedSince: lastSynced)`.
3. If the on-disk mtime moved past `lastSynced`, the write **refuses** (`externalChangeDetected`), the external version is snapshotted, and a `ConflictInfo` is queued for the resolution sheet. Otherwise the atomic write lands and the model updates.

## Data flow: external change

FSEvents → debounced rescan → diff against tracked mtimes → `VaultDelegate` events → `SearchCoordinator` re-indexes, `AppEnvironment` refreshes the facts cache/link graph, and open sessions auto-reload (clean) or surface a conflict (dirty).

## The VS property wrapper

This project must build with the Command-Line-Tools toolchain, which does not ship SwiftUI's macros plugin (`SwiftUIMacros`), so `@State` cannot compile there. `VS` is a `DynamicProperty` wrapper whose storage lives in a process-wide store keyed by declaration site (or an explicit key for multi-instance views). Semantics match `@State`: initial value used once, writes trigger view updates, projected value is a `Binding`. On full Xcode CI the same code compiles unchanged (plain Swift, no macros). This is documented in `ViewState.swift` and is a deliberate, honest trade-off for the CLT-only build environment.

## Deliberate trade-offs

- **swift-markdown (Apache-2.0)** instead of a hand-rolled parser: predictable CommonMark/GFM behavior, Apple-maintained; costs a modest compile-time dependency.
- **SQLite FTS5 via the system library** instead of a wrapper ORM: zero dependencies, FTS5 is enabled in macOS's libsqlite3.
- **Non-sandboxed app**: workspace folders are arbitrary user-chosen directories, which the sandbox restricts poorly for file-manager-style apps. The app requests no other entitlements or daemons.
- **Source + preview instead of WYSIWYG**: a reliable source-preserving editor beats a fragile round-trip pretender; the preview pipeline is shared with HTML/PDF export.
