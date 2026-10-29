# Privacy

Sakura Notes is local-first. This document describes exactly what the app stores, reads, and — only with your explicit action — sends over the network.

## What stays on your Mac

- **Your notes** live in the workspace folders you choose. The app never uploads, "phones home", or includes note content in any analytics (there is no analytics or telemetry at all).
- **Derived data** lives in `~/Library/Application Support/SakuraNotes/`:
  - `Indexes/*.sqlite` — the full-text search index (a copy of your note text, deletable and rebuildable from your files)
  - `History/` — version-history snapshots
  - `workspaces.json` — the workspace list and recent files
- **Per-vault metadata** is `.sakuranotes/meta.json` inside the vault (an ID and folder preferences).

## What leaves your Mac

Only AI requests, and only when you trigger one:

- When you run an AI action or ask a question, the app sends your prompt plus the **explicitly selected context** (current note / current note + linked notes / all notes, capped by a configurable character budget) to the provider endpoint you configured, authenticated with your API key.
- The first session shows a notice describing exactly what will be sent, per request; the AI panel shows a content-free summary ("N notes, ~X characters will be sent") for every request.
- The AI menu actions operate on the current note or your selection only, with no extra context, unless you chose a broader scope.
- **Nothing else ever makes a network request.** The preview, diagram rendering, and export are fully local; bundled assets (highlight.js, KaTeX, Mermaid) are loaded from the app bundle, never a CDN.

## Credentials

API keys are stored in the macOS **Keychain** (accessible after first unlock). They are never written to notes, settings files, logs, snapshots, or Git history. Logs, when enabled for development, contain no note content.

## Crash reports

The app does not collect or submit crash reports.

## Permissions

- **File access**: limited to the workspace folder you pick (and Trash via the system trash API). The app is not sandboxed because workspaces are arbitrary folders; it requests no other entitlements.
- **Automation (optional)**: "Open Workspace in Terminal" asks macOS for permission to control Terminal. You can deny it; the feature simply reports that it is unavailable.
- No accessibility permissions, login items, or background daemons are used. The global quick-capture shortcut uses the legacy Carbon hot-key API, which does not require Accessibility permission.
