# Release process

## Versioning

Semantic versioning; `0.x.y` until the public product is stable. Versions are cut as Git tags `vX.Y.Z`; `CHANGELOG.md` records user-visible changes.

## What a release requires

1. `swift build` and `bash scripts/test.sh` green on a clean checkout.
2. `bash scripts/build_app.sh dist` produces `dist/SakuraNotes.app`; launch it and smoke-test: create workspace → edit → preview → search → graph → export.
3. Update `CHANGELOG.md`.
4. Tag: `git tag -a vX.Y.Z -m "…" && git push origin vX.Y.Z`.
5. CI (`.github/workflows/ci.yml`) builds the app bundle on a `macos-15` runner for tags and uploads it as a workflow artifact.

## Building the app bundle locally

```bash
bash scripts/build_app.sh dist
```

The script:
1. Builds the release executable with `swift build -c release`.
2. Assembles `SakuraNotes.app/Contents/{MacOS,Resources}` with `Info.plist` (bundle id `app.sakuranotes.SakuraNotes`, document types for Markdown, LSMinimumSystemVersion 14.0) and `PkgInfo`.
3. Copies the preview assets (highlight.js, KaTeX incl. fonts, Mermaid) and the app icon.
4. Ad-hoc code-signs (`codesign -s -`) so macOS Gatekeeper accepts local execution.

## Signing and notarization

Not available in this project: there are no Developer ID credentials. If you have them:

```bash
codesign --force --options runtime --timestamp \
  --sign "Developer ID Application: NAME (TEAMID)" \
  dist/SakuraNotes.app
xcrun notarytool submit SakuraNotes.zip --apple-id … --team-id … --password …
xcrun stapler staple dist/SakuraNotes.app
```

The app uses the hardened-runtime-compatible feature set (no unusual entitlements), so notarization should succeed once credentials exist; this has **not** been verified and must not be claimed until it is.

## App icon

`scripts/make_icon.swift` renders the sakura-petal icon with CoreGraphics at all required sizes and `iconutil` packs `AppIcon.icns`. Regenerate with:

```bash
swift scripts/make_icon.swift
```

## Known release constraints

- The CLT-only toolchain used for local development cannot build the *test* target in release configuration reliably (toolchain explicit-modules bug, documented in docs/TESTING.md); CI on full Xcode is authoritative for release verification.
- Unsigned builds trigger Gatekeeper on first launch (`xattr -cr` or right-click → Open).
