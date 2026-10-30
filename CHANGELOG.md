# Changelog

All notable changes to Sakura Notes are documented here. The project follows [Semantic Versioning](https://semver.org/); it is in 0.x while the core is settling.

## [0.1.1] — 2026-10-30

### Fixed
- **Crash on opening a note in the packaged app** (`SakuraNotes.app`): the SwiftPM
  resource bundle required by `Bundle.module` was not copied into the bundle, so
  the first preview render aborted (EXC_BREAKPOINT in `NSBundle.module`). The
  bundle is now shipped in `Contents/Resources` and preview asset lookups
  degrade gracefully instead of trapping.
- **New windows opened nearly fullscreen**: fresh windows were sized from the
  root view's ideal size, which the preview web view inflates. Windows now
  default to 1180×760.
- **Opening Markdown files from Finder**: double-click / Open With / dragging a
  file onto the Dock icon now opens the containing folder as a workspace (if
  needed) and selects the note. Folders open as workspaces.

### Changed
- Settings layout rewritten with the native grouped form style; README roadmap
  restructured.

## [0.1.0] — 2026-10-30

Initial public release.

### Editor
- Source editor with incremental Markdown syntax highlighting; automatic list continuation and ordered-list numbering; tab indentation
- Live preview (Editor / Split / Preview modes) with sanitized rendering: tables, task checkboxes, code highlighting, LaTeX math (KaTeX), Mermaid diagrams — all bundled locally
- Formatting commands (bold/italic/strikethrough/link/wiki link/headings/tasks/tables/code blocks) with menu shortcuts; image paste and drag-and-drop into the vault's attachments folder
- Adjustable font, size, line spacing, writing width; spell check; find bar; word/character counts and reading time
- Autosave with visible save state; undo/redo

### Workspace
- Multiple workspaces; folder tree, note list with filtering/sorting/excerpts, recents
- Create/rename/move/duplicate notes and folders; trash-based deletes
- Tabs with pinning; quick switcher (⌘O) and command palette (⌘P)
- External-change detection with compare-and-resolve sheet; internal links rewritten on rename/move
- Daily notes, templates with variables, per-vault metadata

### Search
- SQLite FTS5 index with incremental updates and full rebuild
- Operators: tag:, path:, ext:, title:, before:, after:, exclusions, phrases, prefixes; highlighted snippets; CJK substring fallback

### Knowledge
- Wiki links with autocomplete and deterministic resolution; backlinks, unlinked mentions, broken-link detection
- Knowledge graph with filters and orphan hiding; aggregated task list with toggling

### Safety
- Atomic writes; version history with diff/restore; snapshots before risky overwrites; conflict resolution that never discards either version silently

### AI assistant (optional)
- OpenAI-compatible streaming client; Keychain-stored keys
- Current-note and selection actions with diff review (accept/reject)
- Workspace Q&A with citations, bounded context scopes, transparency notices

### Platform
- Native menus, keyboard shortcuts, global quick-capture hotkey and floating panel, light/dark appearance, VoiceOver labels, reduced-motion-friendly animations

### Infrastructure
- 73 automated tests (Swift Testing) across parser, storage, search, and link layers
- GitHub Actions CI building and testing on macOS runners
- Performance-verified on 2,000-note workspaces (see docs/PERFORMANCE.md)
