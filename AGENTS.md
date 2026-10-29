# Sakura Notes — Autonomous Development Master Plan

> **Project codename:** Sakura Notes  
> **Product type:** Native macOS Markdown notebook and personal knowledge workspace  
> **Primary objective:** Build a polished, reliable, high-performance macOS application that is suitable for real users and can be maintained as a serious open-source product.  
> **Execution mode:** Autonomous, end-to-end implementation. Do not stop at a prototype or MVP.  
> **Repository visibility:** Public  
> **Repository description and README:** English  
> **User-facing product:** English-ready architecture with localization-friendly strings; do not hard-code UI text throughout the codebase.

---

## 0. Mission and Non-Negotiable Rules

You are responsible for taking this project from an empty or existing working directory to the most complete, tested, polished, and release-ready product achievable in the available execution window.

Treat this as software intended for many real users—not a throwaway demo, tutorial, or mockup.

### Mandatory rules

1. **Do not build an MVP and stop.** Implement the full product described in this plan. If time or technical constraints prevent completion of a requirement, document the limitation honestly, complete the best safe implementation possible, and continue with the remaining work.
2. **Do not ask for confirmation for routine engineering decisions.** Inspect the environment, choose sensible defaults, and proceed autonomously. Ask only when a genuinely blocking decision requires user input.
3. **Do not fake functionality.** No decorative buttons without working actions, simulated search results, hard-coded demo notes presented as user data, empty placeholder screens presented as completed features, or tests claimed to pass without being run.
4. **Do not sacrifice data integrity for speed or appearance.** Saving, recovery, file conflict handling, and preservation of ordinary Markdown files are foundational requirements.
5. **Build a real native macOS application.** Prefer Swift, SwiftUI, and AppKit. Do not wrap a web application in Electron or a WebView as the primary application UI.
6. **Design quality is a first-class requirement.** The UI must be deliberate, elegant, restrained, cohesive, and comfortable for long writing sessions. Avoid visual noise, excessive borders, overcrowded panels, random colors, oversized cards, and gratuitous animations.
7. **Performance is a first-class requirement.** Measure where possible. Avoid needless background work, expensive full-library scans on every keystroke, memory leaks, blocking the main thread, and unnecessary dependencies.
8. **Keep the repository healthy.** Use meaningful commits, a useful English README, a license, clear build instructions, tests, and CI where practical.
9. **Inspect before changing.** If the directory already contains work, inspect it and preserve valuable existing code unless there is a clear reason not to.
10. **Finish with an honest delivery report.** State what works, what was tested, what remains incomplete, how to run the app, and the latest commit/tag. Never claim a build, test, signing, notarization, or release succeeded unless it actually did.

### Definition of success

Success is not merely that the app launches. It should have a coherent architecture, real end-to-end workflows, a refined UI, reliable local storage, comprehensive core features, automated tests, understandable documentation, and a reproducible build process.

---

## 1. Start Here: Repository Setup

Before implementing the application:

1. Inspect the current directory, Git status, installed tools, macOS version, Swift/Xcode command-line tool availability, and GitHub CLI authentication.
2. If this is not already a suitable Git repository, initialize it.
3. Use the `gh` command-line tool to create a **public GitHub repository**. Choose a clear repository name such as `sakura-notes`, unless that name is unavailable or a suitable repository already exists.
4. Prefer creating the repository from the current local project directory, for example:

   ```bash
   gh auth status
   gh repo create sakura-notes --public --source=. --remote=origin
   ```

   Adapt the command to the actual directory and existing repository state. Do not overwrite an existing remote or repository blindly. If the repository already exists, inspect it and continue with the correct remote.

5. Use an accurate, concise **English repository description**, for example:

   `A native macOS Markdown notebook with local-first storage, powerful search, linked notes, and an optional AI writing assistant.`

6. Write a substantial, professional **English `README.md`** covering:
   - Product overview and design principles
   - Feature set
   - Screenshots section, added only when real screenshots are available
   - Requirements and supported macOS versions
   - Build and run instructions
   - Testing instructions
   - Storage model and privacy
   - AI configuration and data handling
   - Import/export and backup guidance
   - Roadmap or known limitations
   - Contributing guidance
   - License
   - Current release status, without claiming an unreleased version is stable

7. Add an appropriate open-source license if the repository has none. Choose a permissive license such as MIT only after checking that all included code and dependencies are compatible. Do not copy code with incompatible licensing.
8. Add `.gitignore`, `.editorconfig` if useful, and a sensible directory structure.
9. Create the initial commit once the repository is in a coherent state. Push the repository when authentication and network access permit.
10. If `gh` is missing or authentication fails, diagnose the issue and continue local development. Report the exact blocker instead of silently pretending that the repository was created.

Do not publish API keys, credentials, personal data, signing certificates, private configuration, or real user notes. Keep secrets out of Git history.

---

## 2. Product Vision and Principles

Sakura Notes is a native macOS Markdown writing and knowledge-management application. It combines the speed and ownership of ordinary files with the comfort of a refined native editor and the optional capabilities of an AI-assisted knowledge workspace.

### Core principles

- **Local-first:** Notes remain ordinary Markdown files in user-controlled directories.
- **Native:** Respect macOS conventions, keyboard behavior, window management, accessibility, and system appearance.
- **Writing-first:** The editor must feel fast, stable, and comfortable for long sessions.
- **Open format:** Users can inspect, edit, version, and move their notes without Sakura Notes.
- **Privacy by design:** No mandatory account, cloud dependency, or AI upload.
- **Predictable:** No silent overwrites, hidden destructive actions, or unexplained data transformations.
- **Elegant and restrained:** Strong hierarchy, generous whitespace, careful typography, and minimal chrome.
- **Extensible:** Use modular architecture and documented interfaces where extension points are justified.
- **Honest:** Distinguish implemented, tested, experimental, and planned functionality clearly.

---

## 3. Technical Direction

Choose a practical, maintainable architecture based on what is available in the environment. Prefer native macOS technologies.

### Preferred stack

- **Language:** Swift.
- **Application UI:** SwiftUI, using AppKit where native text editing or advanced window behavior requires it.
- **Editor:** Build on an appropriate native text-system foundation or a mature, license-compatible editor component. Do not assume SwiftUI `TextEditor` alone can satisfy the full editing specification.
- **Markdown parsing/rendering:** Prefer a well-maintained parser with predictable CommonMark/GFM behavior and explicit extension support.
- **Search:** SQLite FTS5 or another reliable local full-text index, with a rebuildable index.
- **Persistence:** Ordinary Markdown files and adjacent assets are the source of truth. Store only derived indexes, preferences, metadata that cannot safely live in Markdown, and application state in databases or configuration files.
- **File monitoring:** Use suitable macOS filesystem event APIs and handle external edits safely.
- **AI networking:** `URLSession` with an OpenAI-compatible API abstraction.
- **Testing:** XCTest and UI automation where available; include parser, file-system, indexing, and data-integrity tests.
- **Distribution:** Prepare a release build workflow. Use Developer ID signing, hardened runtime, and notarization only when the required credentials and entitlements are available.
- **CI:** GitHub Actions for building and testing on supported macOS runners, where practical.

### Architecture expectations

Separate the application into clear modules or layers, such as:

- App lifecycle and window coordination
- Design system and reusable UI
- Workspace and file-system access
- Markdown editor and rendering
- Note and attachment management
- Search and indexing
- Links, backlinks, and graph data
- Tasks, daily notes, and templates
- AI providers, context selection, and diff application
- Preferences, backup, history, and synchronization awareness
- Import/export
- Tests and developer tooling

Avoid a giant view, a giant view model, tightly coupled global state, or a single service that handles every concern. Use dependency injection or explicit service boundaries where they improve testability. Keep the architecture proportionate; do not create needless abstractions for their own sake.

Before adopting a dependency, check maintenance activity, license, macOS compatibility, security implications, binary size, and whether native APIs can meet the need. Document important trade-offs.

---

## 4. Complete Functional Specification

Implement the features below as integrated workflows, not as disconnected menu items. Prioritize data safety and end-to-end functionality, but do not treat the later sections as optional merely because the core editor is working.

### 4.1 Markdown Editor

- Source editing mode.
- Live preview mode.
- WYSIWYG-style editing mode if it can be implemented reliably without corrupting Markdown.
- Accurate rendering of headings, paragraphs, bold, italic, strikethrough, blockquotes, ordered/unordered lists, task lists, horizontal rules, links, and images.
- Markdown syntax assistance and context-aware shortcuts.
- Automatic list continuation and correct exit behavior.
- Indentation, paired delimiters where appropriate, sensible cursor movement, and selection preservation.
- Toolbar for common formatting commands.
- Headings and outline navigation.
- Code blocks with language selection, syntax highlighting, line numbers where appropriate, and copy actions.
- Tables, including insertion, editing, alignment, row/column operations, and useful paste behavior.
- LaTeX inline and block math rendering.
- Mermaid diagrams with useful error states and secure rendering.
- Image insertion through paste, drag-and-drop, file selection, and screenshot workflows.
- Attachment insertion and relative-link management.
- Link recognition and sensible editing behavior.
- Word, character, selection, and estimated reading-time statistics.
- Focus/distraction-free mode and adjustable reading width.
- Undo/redo with correct behavior across editing operations.
- Autosave and crash recovery.
- Large-document responsiveness.
- Correct handling of Unicode, emoji, CJK text, IME composition, and accessibility.
- Preserve source formatting where feasible. Do not silently rewrite the entire file just because the user switches view modes.

### 4.2 Workspace and Note Management

- Multiple workspaces or vaults, each mapped to a user-selected local directory.
- Create, open, switch, rename, and close workspaces.
- Folder tree with nested directories.
- Note list with sorting and filtering.
- Create, rename, move, duplicate, and delete notes.
- Batch move, rename, tag, and other safe bulk actions where appropriate.
- Favorites, pinned notes, recent notes, and recently opened files.
- Multi-tab editing, tab pinning, tab reordering, and clear unsaved-change indicators.
- Split editor panes, including side-by-side comparison of notes.
- Configurable sidebar visibility and workspace layout.
- Reveal the current file in Finder and open the workspace in a terminal.
- Respect hidden files and provide a setting for showing them.
- Detect files created, deleted, moved, or changed externally.
- Handle filename collisions and case sensitivity safely.
- Searchable recent files and quick navigation.
- Soft delete/trash and recovery, with clear behavior when a file is deleted externally.
- Never treat sample content as real user content after first launch.

### 4.3 Search and Navigation

- Full-text search across note title, content, and supported metadata.
- Incremental search with debouncing and cancellation.
- Search-result snippets with highlighted matches.
- Filters for workspace, path, tags, file type, and dates.
- Search operators such as `tag:`, `path:`, `ext:`, and date filters, documented clearly.
- Exact phrase search, exclusions, and case-sensitivity options when supported.
- Quick switcher for notes, headings, tabs, and commands.
- Recent and saved searches.
- Index status and a way to rebuild the index.
- Search must not block the main thread.
- Index failures must not make the underlying notes inaccessible.

### 4.4 Tags and Metadata

- Parse tags from Markdown using a documented convention.
- Display and filter by multiple tags.
- Optional hierarchical tag support.
- Note metadata/properties with a documented format, such as YAML front matter, if implemented.
- Metadata editing that preserves unknown properties and original content where possible.
- Views for tags and tag usage.
- No proprietary metadata should be required just to read a note in another editor.

### 4.5 Linked Notes and Knowledge Graph

- Wiki-style links such as `[[Note Name]]`, with autocomplete.
- Resolve links deterministically, including duplicate note titles.
- Backlinks and outgoing links.
- Unlinked mentions, with safe suggestions to create links.
- Broken-link detection and repair tools.
- Update internal links when notes are renamed or moved, with preview/undo where practical.
- Local graph and whole-workspace graph.
- Graph filters by folder, tag, and relationship.
- Identify orphan notes.
- Avoid rendering an enormous graph without controls or performance safeguards.
- Provide a useful non-graph navigation experience for users who do not want a graph.

### 4.6 Templates, Daily Notes, and Tasks

- User-editable templates for meeting notes, daily logs, learning notes, reading notes, technical documentation, project notes, weekly reports, and retrospectives.
- Create notes from templates with date and title variables.
- Daily notes with calendar navigation and configurable storage path/name.
- Markdown task parsing using standard checkbox syntax.
- Task aggregation across the workspace.
- Completed/incomplete filters and source-note navigation.
- Optional due dates and reminders using documented metadata.
- Notifications only when enabled by the user.
- Preserve task syntax in Markdown files.
- Do not invent a proprietary task format without a clear reason.

### 4.7 AI Assistant

AI is optional and disabled until the user configures a provider.

**Current-note actions**
- Summarize, rewrite, proofread, expand, shorten, translate, and adjust tone.
- Generate a title, abstract, outline, keywords, or table of contents.
- Convert selected text into a table, checklist, timeline, or structured note.
- Explain selected code, error messages, and technical concepts.
- Generate questions and flashcards from a note.
- Organize rough notes into a user-selected template.

**Knowledge-base actions**
- Ask questions across selected notes or permitted workspaces.
- Cite the source note and, where possible, relevant sections.
- Compare notes and identify disagreements or duplicated content.
- Generate study guides, FAQs, summaries, and project overviews from existing notes.
- Suggest links and tags without silently applying them.
- Clearly distinguish source-grounded information from model-generated inference.

**Workflow and safety**
- Support configurable OpenAI-compatible endpoints, models, and user-supplied API keys.
- Allow configuration of request context, temperature, and relevant provider options where supported.
- Let users select which notes/folders can be included in context.
- Show what information will be sent to an external service before a first or materially changed request.
- Never transmit the whole vault by default.
- Apply generated edits through a diff/preview workflow with accept, reject, and undo.
- Never silently overwrite the original note.
- Handle timeouts, network failures, rate limits, invalid credentials, and malformed responses gracefully.
- Redact secrets from logs and never commit API keys.
- Provide useful provider status and token/cost information only when the provider makes reliable data available.
- Avoid claiming that AI output is factually verified.

### 4.8 File Integrity, History, Backup, and Sync Awareness

- Autosave with visible saved/unsaved status.
- Recover unsaved edits after a crash where technically possible.
- Detect external changes and present a safe reload/compare/keep-local/merge path.
- Never silently overwrite an external change.
- Version history with diffs and restoration where feasible.
- Workspace backup and restore.
- Export/backup to a user-selected location.
- Attachment integrity checks.
- Broken relative-link and missing-asset checks.
- Warn users about sync conflict copies when detectable.
- Work correctly in ordinary local directories and supported synced directories.
- Document that file synchronization providers can have their own conflict semantics.
- Optional Git integration only if it can be implemented without compromising file safety; otherwise document a Git-friendly workflow.
- All indexes must be rebuildable from the underlying files.
- Destructive operations require clear confirmation and sensible recovery.
- Do not claim end-to-end encryption unless it is actually implemented and audited.

### 4.9 Import, Export, and Sharing

- Import Markdown folders while preserving directory structure.
- Import plain-text files where appropriate.
- Export a workspace or selected notes as Markdown.
- Export selected notes to standalone HTML with styles, table of contents, code highlighting, and local assets where supported.
- Export to PDF using a reliable macOS-compatible approach.
- Consider DOCX export if a reliable implementation is available.
- Copy notes with assets while preserving or rewriting relative links correctly.
- Report skipped, conflicting, or failed files in batch operations.
- Avoid destructive “move” imports until the user has a clear preview.
- Ensure exported content is readable outside Sakura Notes.

### 4.10 Native macOS Experience

- Native app lifecycle and standard window behavior.
- Multiple windows where practical.
- Light and dark appearances, including following the system.
- A coherent design system for typography, spacing, colors, icons, and controls.
- Command menu and keyboard-first workflows.
- Configurable global quick-capture shortcut, with conflict detection and permission awareness.
- Menu-bar quick capture that does not require the full workspace window.
- System share integration where practical.
- Finder integration and drag-and-drop.
- Clipboard support for text, rich text conversion, images, and file URLs.
- Keyboard shortcuts for core operations, documented in the app.
- Adjustable font, font size, line spacing, content width, and editor appearance.
- Respect Reduce Motion and relevant accessibility settings.
- VoiceOver labels, keyboard focus order, contrast, and scalable text.
- Optional Spotlight integration if robust and privacy-conscious.
- Shortcuts integration or documented automation hooks if feasible.
- Avoid unnecessary background agents, login items, or privileged permissions.

### 4.11 Appearance and Personalization

- Carefully designed light and dark themes.
- Optional accent color, with restrained defaults.
- Editor font and size controls.
- Line height, paragraph spacing, and reading-width controls.
- Code theme and syntax highlighting options.
- Sidebar and panel visibility preferences.
- Optional CSS customization for rendered Markdown if it can be sandboxed and maintained safely.
- Preferences should be searchable or clearly organized.
- Settings should persist predictably and be resettable.
- Avoid a theme marketplace until the core theming architecture is stable.

### 4.12 Advanced Features and Extensibility

Implement the most valuable features when the core product is stable:

- Reading mode with outline and reading progress.
- Presentation mode that turns headings/slides into navigable pages.
- Web clipping through a share extension or browser integration if feasible.
- Annotations or comments that do not corrupt the source Markdown.
- Preview support for common attachments such as PDF and images.
- Duplicate-note and stale-note detection.
- Link/asset maintenance tools.
- Writing statistics and optional history charts.
- Plugin architecture only with a clear permission and security model.
- Documented extension APIs for commands or renderers if genuinely supported.
- Do not ship a fake plugin system or unsafe arbitrary code execution merely to check a box.

---

## 5. UI and Interaction Quality Bar

UI quality is one of the highest-priority requirements. Do not treat design as a final coat of paint.

### Visual direction

Aim for a calm, premium, native macOS writing environment:

- Minimal, spacious, typography-led layout.
- Strong visual hierarchy without excessive decoration.
- Neutral surfaces with a restrained accent color.
- Consistent spacing and alignment.
- Subtle separators only when they clarify structure.
- Carefully designed empty, loading, error, and recovery states.
- Elegant light and dark modes.
- Native-feeling hover, focus, selection, menus, popovers, and keyboard navigation.
- No unnecessary gradients, glow effects, oversized rounded cards, emoji icons in core navigation, or excessive animation.
- Avoid a cluttered three-column layout: allow panes to collapse and widths to adapt.
- Keep the writing surface visually dominant.
- Make important actions discoverable without permanently occupying large amounts of screen space.

### Main workspace layout

Use a flexible three-pane workspace as a starting point:

1. **Sidebar:** workspace switcher, folders, tags, favorites, daily notes, and navigation.
2. **Note list:** search, sorting, filters, note titles, and lightweight metadata.
3. **Editor:** tabs, Markdown editor/preview, outline, backlinks, and optional AI panel.

Allow the sidebar, note list, outline, backlinks, and AI panel to be hidden or resized as appropriate. Include a distraction-free writing mode and a small quick-capture window.

### Required design iteration

Before calling the UI complete:

1. Build the actual application UI, not just static mockups.
2. Run it and inspect screenshots at realistic window sizes.
3. Check light mode and dark mode.
4. Check a small window and a large window.
5. Check empty workspace, populated workspace, long filenames, long documents, large folder trees, search results, errors, and loading states.
6. Look for inconsistent margins, cramped controls, awkward text wrapping, excessive borders, unclear hierarchy, low contrast, and mismatched icon sizes.
7. Fix the most visible problems and repeat the inspection.
8. Use native controls where they provide a better platform fit; customize only where it improves usability.

If screenshot tooling or UI automation is unavailable, use the best available manual or programmatic inspection method and state the limitation honestly.

---

## 6. Performance, Memory, and Reliability Requirements

The application should feel immediate during ordinary writing and remain usable with large note collections.

### Engineering rules

- Never perform expensive disk scans, parsing of the whole vault, or network requests synchronously on the main thread.
- Debounce and cancel search/indexing work when inputs change.
- Use incremental indexing and file-change events rather than rescanning everything on each edit.
- Avoid retaining every rendered document or image in memory indefinitely.
- Cache only what is useful and invalidate it correctly.
- Use lazy loading or virtualization for large lists and graph views.
- Avoid unnecessary timers, polling, animation, and background tasks.
- Avoid dependency bloat.
- Avoid excessive disk writes for every keystroke; balance autosave latency and storage wear without risking data loss.
- Measure startup, editor responsiveness, indexing, search, and memory use where tooling permits.
- Test with a generated workspace containing many notes and large documents.
- Handle permission errors, disk-full errors, missing files, malformed Markdown, invalid images, and interrupted writes.
- Use atomic writes or equivalent safe persistence patterns when appropriate.
- Ensure background tasks are cancelled when their workspace or view is no longer relevant.
- Keep the app responsive while importing, exporting, indexing, and generating AI responses.

### Performance test scenarios

Create repeatable tests or a test-data generator for:
- A small workspace.
- A workspace with thousands of Markdown files.
- Large notes with many headings, tables, and code blocks.
- Many images and attachments.
- Rapid edits while indexing is running.
- Files changing externally during editing.
- Large search-result sets.
- AI timeouts and repeated cancellation.

Do not invent benchmark numbers. Record measurements only when actually obtained, along with hardware, macOS version, dataset size, and method.

---

## 7. Security, Privacy, and Data Handling

- Request filesystem access only when needed and explain why.
- Respect macOS sandbox and entitlement constraints if using App Sandbox.
- Keep credentials in appropriate secure storage, such as Keychain, when suitable.
- Never store API keys in Markdown files, logs, screenshots, test fixtures, or Git.
- Do not send notes to AI services without an explicit user action and clear context selection.
- Do not include note contents in analytics or crash reports by default.
- Treat Markdown, imported files, HTML, Mermaid, and external links as untrusted content.
- Prevent unsafe HTML or script execution in previews.
- Use safe file path resolution and protect against path traversal when importing or extracting archives.
- Avoid destructive operations without confirmation and recovery.
- Minimize telemetry; if telemetry is introduced, make it opt-in, documented, and free of note contents.
- Provide a clear privacy statement in the README.
- Audit dependencies for known vulnerabilities and license compatibility where tooling permits.

---

## 8. Testing and Acceptance Criteria

Tests are part of implementation, not a final optional phase.

### Unit and integration tests

Test at minimum:

- Markdown parsing and rendering for supported syntax.
- Round-trip editing and source preservation for supported operations.
- File create, rename, move, delete, and recovery.
- Filename collision handling and Unicode paths.
- Relative links and attachment paths.
- Backlink and broken-link calculations.
- External file-change detection and conflict handling.
- Search indexing, incremental updates, and rebuilds.
- Search operators and filters.
- Autosave, recovery, and atomic-write behavior.
- Import/export structure and asset rewriting.
- AI response parsing, failures, cancellation, and diff application.
- Preferences persistence.
- Task and template parsing.
- Data integrity after app restart.

### UI tests or manual acceptance checks

Verify:

- A user can create a workspace and their first note without confusion.
- Editing, switching tabs, and reopening the app preserve content.
- Source, preview, and supported WYSIWYG workflows behave consistently.
- Search results open the correct note and context.
- Dragging in images creates valid local references.
- Renaming a note does not silently break managed links.
- The app handles external modifications without losing either version.
- Keyboard shortcuts and command navigation work.
- Empty and error states provide a clear next action.
- Light and dark themes are legible and visually consistent.
- AI edits require review and can be undone.
- The app remains responsive during indexing and large-file operations.
- All visible controls either work or are clearly disabled with an explanation.

### Build and release checks

- Build from a clean checkout.
- Run the test suite and record the actual result.
- Run static analysis or compiler warnings checks where available.
- Verify app launch and core workflows on the available macOS environment.
- Confirm the repository contains no secrets.
- Verify README instructions against the real project.
- Verify dependency and license information.
- Verify the release artifact and checksum if an artifact is produced.
- Sign and notarize only if credentials and tooling are available; clearly report when they are not.

Never claim full acceptance if important tests have not run. Distinguish “not implemented,” “implemented but untested,” “tested and passed,” and “blocked by environment.”

---

## 9. Git, Versioning, and Release Management

You own day-to-day version management and may choose when to commit, tag, and publish releases.

### Commit discipline

- Make commits at coherent milestones rather than one giant end-of-night commit.
- Use clear, descriptive commit messages.
- Keep commits buildable when practical.
- Do not commit generated build products, secrets, local user data, or temporary screenshots containing private information.
- Review `git diff` and `git status` before committing.
- Never rewrite or force-push public history without a compelling reason.
- Push regularly when the remote is available.
- Do not create a release merely to make the project look active.

### Semantic versioning

Use Semantic Versioning when releases are warranted:

- `0.x.y` while the public product is still evolving, if appropriate.
- `1.0.0` only when the product has a stable core, documented behavior, reliable data safety, meaningful test coverage, and a reproducible release process.
- Patch releases for compatible fixes.
- Minor releases for compatible features.
- Major releases for breaking changes.

You decide when a milestone deserves a version number. Record meaningful changes in `CHANGELOG.md`. If a release cannot be built, tested, signed, or published, report that fact rather than fabricating a release.

### GitHub automation

Create GitHub Actions workflows where practical for:

- Building on supported macOS runners.
- Running unit and integration tests.
- Linting or formatting checks if a suitable tool is adopted.
- Validating release tags and building release artifacts.
- Publishing artifacts only when the required permissions and secrets are configured.

Keep workflows secure, least-privilege, and free of hard-coded credentials.

---

## 10. Documentation Deliverables

Maintain these files as appropriate to the project:

- `README.md` — complete English product and developer documentation.
- `AGENTS.md` — this development plan, updated only when necessary to reflect important decisions.
- `CHANGELOG.md` — release notes and user-visible changes.
- `CONTRIBUTING.md` — local setup, tests, contribution workflow, coding conventions.
- `LICENSE` — selected open-source license.
- `SECURITY.md` — vulnerability reporting guidance.
- `PRIVACY.md` — local-first behavior and AI/network data handling.
- `docs/ARCHITECTURE.md` — major components, data flow, storage model, and key decisions.
- `docs/USER_GUIDE.md` — core workflows, shortcuts, workspace setup, backup, and AI configuration.
- `docs/TESTING.md` — how to run tests and what they cover.
- `docs/RELEASE.md` — versioning, signing, notarization, and release steps.
- `docs/DECISIONS.md` or ADRs — important architectural trade-offs.

Do not add empty boilerplate just to satisfy a file list. Each document must contain accurate, useful information.

---

## 11. Autonomous Execution Loop

Work continuously through the following loop until the available time is exhausted or the acceptance bar is met:

1. **Inspect:** Review the repository, current code, build status, TODOs, and outstanding issues.
2. **Plan:** Choose the highest-value next tasks based on user impact, dependencies, and risk.
3. **Implement:** Make a focused, coherent change.
4. **Build:** Compile as soon as practical; do not accumulate a large amount of uncompiled code.
5. **Test:** Run relevant automated tests and add tests for newly introduced behavior.
6. **Inspect:** Review the diff, error paths, accessibility, UI consistency, and performance implications.
7. **Refine:** Fix defects and design weaknesses discovered during inspection.
8. **Commit:** Save a coherent, verified milestone to Git.
9. **Update:** Keep documentation and the task checklist truthful.
10. **Repeat:** Continue without waiting for the user after every routine milestone.

When a command fails:
- Read the actual error.
- Determine whether the cause is code, configuration, environment, dependency availability, permissions, or network access.
- Fix the root cause where possible.
- Do not blindly repeat failing commands.
- Do not hide failures or mark blocked tasks complete.

When choosing what to implement next, prefer:
1. Data-loss and security risks.
2. Build failures and broken core workflows.
3. Editor correctness and file-system integrity.
4. Search, workspace management, and performance.
5. Visual polish and accessibility.
6. Knowledge-management and AI capabilities.
7. Advanced integrations and optional enhancements.

This ordering is for risk management, not permission to permanently abandon lower-priority requirements.

---

## 12. Final Self-Review: Repeat Until the Best Achievable State

Before finishing, perform multiple explicit review passes. Do not rely on memory or intuition alone.

### Pass A — Product completeness
- Compare every functional section of this plan against the actual code.
- Mark each requirement as implemented, partial, unimplemented, or blocked.
- Verify the main user journeys end to end.
- Remove misleading placeholders and dead controls.

### Pass B — Data integrity and security
- Look for silent overwrites, unsafe deletes, broken relative paths, stale indexes, leaked secrets, unsafe previews, and unintended AI uploads.
- Test external edits, interrupted saves, and restart recovery.
- Fix any data-loss risk before adding decorative features.

### Pass C — UI and interaction
- Inspect the app in realistic window sizes and both appearances.
- Look for clutter, inconsistent spacing, weak hierarchy, unreadable contrast, awkward empty states, and unnecessary chrome.
- Check keyboard behavior, focus, accessibility, and error messaging.
- Improve the interface and inspect again.

### Pass D — Performance
- Inspect main-thread work, repeated parsing, full scans, unbounded caches, expensive view updates, and unnecessary dependencies.
- Test a large generated workspace.
- Record real measurements when available.
- Fix regressions rather than guessing.

### Pass E — Engineering quality
- Build from a clean checkout.
- Run tests and review warnings.
- Inspect `git diff`, dependency licenses, and repository contents.
- Verify build and setup documentation.
- Ensure no temporary or private files are tracked.

### Pass F — Release readiness
- Confirm app identity, version, bundle configuration, icons, app name, and user-facing metadata.
- Verify the README description and screenshots are accurate.
- Verify GitHub Actions and release instructions.
- Ensure every claim in the delivery report is supported by actual results.

If a pass discovers a defect, fix it and rerun the relevant checks. Continue the loop until no high-impact defect remains or a real environmental/time constraint prevents further progress. Document the remaining constraint precisely.

---

## 13. Practical Execution Plan for an Overnight Run

Use the available time aggressively but intelligently. Do not spend the entire session planning or polishing one screen.

Suggested sequence:

1. **Repository and foundation:** inspect tools, create the public GitHub repository with `gh`, establish project structure, app target, license, README, and CI skeleton.
2. **Native app shell and design system:** app lifecycle, workspace window, sidebar, note list, editor surface, theme, typography, spacing, and navigation.
3. **Real Markdown workflow:** file-backed notes, editing, preview, autosave, tabs, basic formatting, and recovery.
4. **Workspace and search:** folder navigation, create/rename/move/delete, full-text indexing, quick switcher, and external file-change detection.
5. **Writing features:** images, links, tables, code blocks, outline, templates, daily notes, and task lists.
6. **Knowledge features:** tags, backlinks, wiki links, broken-link checks, and graph navigation.
7. **Reliability and privacy:** conflict handling, backup, import/export, safe AI context selection, and secrets handling.
8. **AI integration:** provider configuration, current-note actions, diff-based editing, and source-grounded workspace queries where practical.
9. **Advanced features:** implement remaining valuable functionality such as HTML/PDF export, reading mode, and additional integrations.
10. **Hardening:** run tests, inspect the UI, profile performance where possible, fix defects, update docs, commit, and push.
11. **Release preparation:** select a version only if justified, create a release artifact if possible, and report exact results.

This is a work sequence, not a reason to stop after any one stage. Continue as far as possible, revisiting incomplete sections.

---

## 14. Completion Report Format

At the end of the autonomous run, provide a concise but specific report with:

1. **Repository:** public GitHub URL, repository description, and whether README/license/CI are present.
2. **Build:** exact build command and result.
3. **Tests:** exact tests run, pass/fail counts where available, and tests not run.
4. **Implemented features:** grouped by editor, workspace, search, knowledge management, AI, safety, and native macOS UX.
5. **Known gaps:** incomplete, partial, untested, or environment-blocked requirements.
6. **Data safety:** what is persisted, how backups/recovery work, and any known risks.
7. **Performance:** actual measurements only, including the environment and method.
8. **Release:** latest commit, tag/version if any, artifact location, and signing/notarization status.
9. **Next steps:** the most important remaining work, ranked by impact.

Do not report a feature as complete merely because a class or UI control exists. A feature is complete only when the user can use it through a coherent workflow and relevant behavior has been tested.

---

## 15. Start Now

Begin by inspecting the environment and repository. Then create or connect the public GitHub repository using `gh`, write the English README and foundational project documents, and immediately start implementing the real application.

Do not respond with only a plan. Do not stop after creating the repository. Do not wait for approval at each milestone. Work autonomously, build frequently, test honestly, inspect the actual UI, refine the product, commit coherent milestones, and continue until the best achievable release-ready state is reached.

**The goal is a trustworthy, polished native macOS Markdown product—not a mockup, not a feature checklist, and not a demo that only looks finished.**
