#!/bin/bash
# Builds SakuraNotes.app into the given output directory (default: dist).
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${1:-dist}"
APP_NAME="Sakura Notes"
BUNDLE_ID="app.sakuranotes.SakuraNotes"
VERSION="$(git describe --tags --always 2>/dev/null || echo "0.1.0")"
BUILD="$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")"

echo "==> Building release executable"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/SakuraNotes"

APP="$OUT/SakuraNotes.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "==> Assembling bundle"
cp "$BIN" "$APP/Contents/MacOS/SakuraNotes"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>SakuraNotes</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION#v}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 Sakura Notes contributors. MIT licensed.</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>Markdown Document</string>
            <key>CFBundleTypeRole</key>
            <string>Editor</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>net.daringfireball.markdown</string>
                <string>public.plain-text</string>
            </array>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
        </dict>
        <dict>
            <key>CFBundleTypeName</key>
            <string>Folder</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.folder</string>
            </array>
            <key>LSHandlerRank</key>
            <string>None</string>
        </dict>
    </array>
</dict>
</plist>
PLIST

printf 'APPL????' > "$APP/Contents/PkgInfo"

# App icon (generate once if missing).
if [ ! -f "$APP/Contents/Resources/AppIcon.icns" ]; then
    if [ -f "Resources/AppIcon.icns" ]; then
        cp "Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
    else
        echo "==> Generating app icon"
        mkdir -p Resources
        swift scripts/make_icon.swift || echo "warning: icon generation failed; continuing without icon"
        [ -f "Resources/AppIcon.icns" ] && cp "Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
    fi
fi

echo "==> Copying preview assets"
mkdir -p "$APP/Contents/Resources/Preview"
cp -R Sources/SakuraNotesApp/Resources/Preview/. "$APP/Contents/Resources/Preview/"

echo "==> Ad-hoc code signing"
codesign --force --sign - "$APP" 2>/dev/null || echo "warning: codesign failed; continuing"

echo "==> Built $APP"
