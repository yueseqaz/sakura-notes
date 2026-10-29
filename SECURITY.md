# Security Policy

## Reporting a vulnerability

Please open a [GitHub security advisory](https://github.com/yueseqaz/sakura-notes/security/advisories/new) rather than a public issue. Include a description, reproduction steps, and the affected version/commit. You can expect an initial response within a week; fixes land on `main` and are noted in the changelog.

## Scope and design posture

Sakura Notes is a local application for private notes. The security-relevant surfaces are:

1. **Note content is untrusted input.** Markdown is parsed with swift-markdown and rendered through a sanitizer that drops raw HTML (block and inline) and escapes text. The preview renders only this sanitized HTML.
2. **The preview web view has no file access.** Content and assets are served over a custom `sakura-preview://` scheme by a handler that only serves (a) the generated document, (b) resources from the app bundle, and (c) vault media files (images/PDF) whose vault-relative path contains no traversal. External navigation is redirected to the browser; `window.open` is blocked; remote subresources are never fetched.
3. **Path handling.** Any externally supplied relative path must pass `VaultStore.isSafeRelativePath` (no leading `/`, no `..` components) before file APIs touch it; the link updater, importer, and preview handler all normalize `..` segments themselves as well.
4. **Secrets.** AI provider keys live only in the macOS Keychain. They are never written to notes, settings, logs, snapshots, or the repository.
5. **Network.** The only outbound traffic is AI requests to a user-configured endpoint, triggered by explicit user action. There is no telemetry.
6. **Destructive operations** go to the macOS Trash, and risky overwrites are preceded by snapshots. Conflict resolution never overwrites either version silently.
7. **AI output is untrusted.** Generated text is shown as a diff and requires explicit acceptance before it touches a note; it is inserted as plain Markdown, never executed.

## Known limitations

- The app is **not** sandboxed (arbitrary workspace folders) and ships unsigned/un-notarized without available Developer ID credentials.
- Mermaid diagrams are rendered with `securityLevel: 'strict'`; the Mermaid project treats diagram text as untrusted, but as with any renderer, defense in depth is the dropped-raw-HTML guarantee above.
- No end-to-end encryption: file-level protection is whatever your macOS account and FileVault provide.

## Dependency inventory

| Dependency | License | Role |
| --- | --- | --- |
| swift-markdown (+ swift-cmark) | Apache-2.0 (cmark BSD-2/MIT variants) | Markdown AST |
| highlight.js 11.9 (bundled) | BSD-3-Clause | preview code highlighting |
| KaTeX 0.16.11 (bundled) | MIT | math rendering |
| Mermaid 10.9.1 (bundled) | MIT | diagrams |

Vendored bundle assets are pinned copies under `Sources/SakuraNotesApp/Resources/Preview/vendor/` — updates are deliberate commits, never fetched at runtime.
