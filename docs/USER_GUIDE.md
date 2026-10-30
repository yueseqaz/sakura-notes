# User Guide

## Getting started

1. Launch Sakura Notes and either **Create a New Workspace** (makes a folder) or **Open Existing Folder…**. Any folder works — it becomes a workspace.
2. Create a note with ⌘N, from the note list's ✎ button, or from a template (✎ → *From Template…*).
3. Type Markdown. Toggle **Editor / Split / Preview** with the segmented control or ⌘R.

## Keyboard shortcuts

| Action | Shortcut |
| --- | --- |
| New note | ⌘N |
| New tab | ⌘T |
| New folder | ⇧⌘N |
| Open workspace | ⇧⌘O |
| Quick switcher | ⌘O |
| Command palette | ⌘P |
| Today's daily note | ⇧⌘D |
| Cycle editor/split/preview | ⌘R |
| Save now | ⌘S |
| Close tab | ⌘W |
| Bold / italic | ⌘B / ⌘I |
| Strikethrough | ⌃⌘S |
| Link / wiki link | ⌘K / ⌃⌘L |
| Headings 0–6 | ⌥⌘0…⌥⌘6 |
| Task item | ⇧⌘L |
| Code block | ⌥⌘C |
| Move note to trash | ⌘⌫ |
| Reveal in Finder | ⌥⌘R |
| Knowledge graph | ⌥⌘G |
| All tasks | ⌥⌘T |
| Version history | ⌥⌘H |
| Toggle sidebar / note list | ⌥⌘S / ⌥⌘L |
| Toggle AI panel | ⌥⌘A |
| Quick capture (global) | ⇧⌘Space (configurable) |

## Workspaces

Workspaces are folders. Switch between them from the sidebar's workspace menu, add more with ⇧⌘O, and remove one via Settings → Advanced (files are never touched). `Reopen last workspace at launch` is on by default.

## Linking notes

- Type `[[` in the editor to open the wiki-link autocomplete; pick a suggestion and press Return.
- `[[Note Title]]`, `[[Note Title|display text]]`, and `[[Note Title#Heading]]` all work.
- Resolution order: exact vault path → note title → file name; same-folder notes win ties.
- ⌘-click a wiki link to open it. If it doesn't exist, the app offers to create it.
- The **Backlinks** panel (toolbar link icon) lists notes linking to the current note and can show *unlinked mentions*.
- Renaming or moving notes/folders updates internal links automatically; a status banner reports how many links were rewritten, and version history stores the previous text of every modified note.

## Tags

Write `#tag` anywhere in a note, or list them in front matter:

```markdown
---
tags: [project, alpha]
---
```

Hierarchical tags (`#area/ship`) are supported; the sidebar shows tag counts, and `tag:` in search filters them.

## Tasks

Use standard checkboxes:

```markdown
- [ ] buy coffee
- [x] write the spec
```

The **Tasks** sheet (⌥⌘T) aggregates every task in the workspace; clicking one toggles it in its source note and saves. Optional due dates: append `@due(2026-12-01)` to a task.

## Daily notes and templates

- ⇧⌘D opens (or creates) today's note in the daily folder (default `Daily`, configurable in Settings).
- Put templates in the vault's `Templates` folder; they appear under the note list's ✎ menu. Available variables: `{{title}}`, `{{date}}`, `{{time}}`, `{{weekday}}`, `{{year}}`, `{{month}}`, `{{day}}`, `{{date:yyyy-MM-dd}}`.

## Search operators

| Operator | Meaning |
| --- | --- |
| `word` | all terms must match (prefix match) |
| `"exact phrase"` | phrase in order |
| `-word` | exclude |
| `tag:project` | note carries the tag (includes sub-tags) |
| `path:journal` | path contains the text |
| `ext:md` | file extension |
| `title:plan` | title contains the text |
| `before:2026-01-01` | modified before that day (inclusive) |
| `after:2026-01-01` | modified since that day |

## Version history and conflicts

- Open a note's history from the toolbar clock icon (⌥⌘H): pick a snapshot, read the diff against the current text, and restore it. Restoring a restore is possible — every restore is itself snapshotted.
- Snapshots are taken before conflict resolution, before AI edits apply, and when an external change would otherwise be overwritten.
- If a file changes outside the app while you have unsaved edits, a comparison sheet appears with **Keep Mine / Take Theirs / Keep Both** (the "theirs" copy lands next to yours as a dated conflict file). Nothing is ever overwritten silently.

## Opening files from Finder

After launching the app once, you can open Markdown files from Finder via right-click → **Open With → Sakura Notes** (or by dragging a file onto the app icon). Opening a file outside any workspace opens its containing folder as a new workspace and selects the note; folders dragged onto the icon open as workspaces.

## Quick capture

Press ⇧⌘Space anywhere: a small panel appears, type, ⌘⏎ appends the text with a timestamp to `<Quick capture folder>/Quick Notes.md`. The shortcut is re-recordable in Settings; if it doesn't fire, another app owns that combination.

## AI assistant

1. Settings → AI Assistant → add a provider (e.g. `OpenAI`, `https://api.openai.com/v1`, a model id), paste your API key, **Save** (Keychain), and **Test Connection**.
2. Open the panel (toolbar ✨ or ⌥⌘A). Run actions on the current note or selection; replace-style results appear as a **diff** you accept or reject.
3. *Ask your notes* answers from a context scope you choose; answers cite `[[note titles]]` and label inference as such. The first use explains exactly what will be sent; note content leaves your machine only when you press the button.

## Images and attachments

Paste or drag an image into the editor: it is saved as a PNG in the vault's attachments folder (default `Attachments`) and inserted as a relative Markdown image. PDFs and other attachments can be linked relatively; the preview serves vault media through its sandboxed scheme handler.

## Backup guidance

- Your notes are files: back the folder up with anything (Time Machine, git, rsync). Sakura Notes is git-friendly — no lock files inside the vault except a hidden `.sakuranotes/meta.json`.
- Version history lives under `~/Library/Application Support/SakuraNotes/History/` — include it in backups if you want note history too.
- The search index (`…/SakuraNotes/Indexes/`) is disposable; Settings → Advanced → Rebuild Index recreates it from your files.

## Syncing

Point a workspace at an iCloud Drive/Dropbox/etc. folder and it works. The app detects external changes, never overwrites blindly, and shows conflict sheets for concurrent edits. Sync providers create their own "conflict copy" files; Sakura Notes shows them as regular notes so you can merge and delete them yourself.
