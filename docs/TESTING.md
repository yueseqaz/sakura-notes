# Testing

## Running the suite

```bash
bash scripts/test.sh          # debug build + tests
swift test                    # equivalent on full Xcode toolchains
```

On Command-Line-Tools-only machines (no Xcode.app), Swift Testing's macro plugin is not auto-resolved by the build; `scripts/test.sh` passes `-Xswiftc -load-plugin-library …/libTestingMacros.dylib` explicitly to work around it.

The suite uses [Swift Testing](https://developer.apple.com/xcode/swift-testing/) (`import Testing`, `@Test`) rather than XCTest, because the CLT toolchain ships Swift Testing but not XCTest.

## What is covered (73 tests, 14 suites)

### SakuraCore
- **Front matter** — scalar extraction, flow `[a, b]` and block list styles, absent/unterminated blocks, unknown-key preservation and round-trip through serialization.
- **Note analyzer** — outline levels/titles, inline and hierarchical tags (with code exclusion), task parsing including due dates, wiki/external link extraction, CJK-aware word counts, title fallback chain (front matter → first heading → file name).
- **HTML renderer** — raw HTML dropped (block and inline), text escaping, table alignment, task checkboxes, mermaid divs, code language classes, front-matter stripping, TOC anchor generation.
- **Line diff** — insert/delete detection, identical inputs, apply round-trip, large-input degradation.
- **Search query parser** — terms, phrases, exclusions, all operators, extension normalization.
- **Template engine** — date variables, custom formats, passthrough of unknown variables.
- **String utilities** — file-name sanitization, relative paths, excerpts, Unicode word counting.

### SakuraStorage
- **Vault store** — note creation with auto-rename, hostile-title sanitization, nested folders, duplicate-name errors, rename/move/duplicate/trash with delegate events and model consistency, external-change detection on save (compare-and-swap by mtime), path validation, external file detection on rescan, hidden-file handling, metadata persistence across instances.
- **Snapshot store** — capture/dedupe/list/restore, retention cap, stable vault folder naming.
- **Workspace store** — persistence, recents ordering, removal.

### SakuraSearch
- **FTS index** — term/prefix/phrase matching, exclusions, tag/path/ext/title/date operators, CJK substring fallback, updates and removal, mention lookup, rebuild.
- **Link index** — resolution rules (path → title → file name, same-folder preference), backlinks, orphans, broken links, rename remapping.

### SakuraNotesApp
- **Link updater** — wiki-link rewrites on title change (exact matches only), relative-link rewrites for moved files and folders, relative-path computation, path resolver.

### Performance
- `PerformanceTests` generates a 2,000-note workspace (~2.6 KB each) and measures scan, full index build, search latency, and single-note re-index. See [PERFORMANCE.md](PERFORMANCE.md) for recorded numbers and methodology.

## What is not covered by automation

- UI behavior (typing, keyboard shortcuts, window management) — verified manually in the running app; the test target does compile the full app module, which guards against build regressions.
- Keychain operations (require a real user session and TCC prompts).
- FSEvents real-time delivery (tests use explicit rescans; live monitoring is exercised manually).
- AI network paths (the client is exercised via the Settings "Test Connection" button; error mapping is code-reviewed, not unit-tested against a live provider).

## Writing tests

- Each suite gets isolated temporary directories (`makeTemporaryVault()` in StorageTests).
- Tests are `@MainActor` where they touch `VaultStore`/UI types, matching the app's threading model.
- Prefer asserting observable behavior (file contents, delegate events, query results) over internal state.
