#!/usr/bin/env bash
# Builds dist/ClaudeProfileUsage.app and dist/claude-usage (release, ad-hoc signed).
set -euo pipefail

cd "$(dirname "$0")/.."
APP=dist/ClaudeProfileUsage.app
mkdir -p dist && touch dist/.metadata_never_index

swift build -c release --product ClaudeProfileUsage
swift build -c release --product claude-usage
swift build -c release --product ClaudeProfileUsageWidget
BIN=$(swift build -c release --show-bin-path)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/ClaudeProfileUsage" "$APP/Contents/MacOS/ClaudeProfileUsage"
cp "$BIN/claude-usage" dist/claude-usage

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>io.github.shamsbd71.claude-profile-usage</string>
    <key>CFBundleName</key><string>ClaudeProfileUsage</string>
    <key>CFBundleDisplayName</key><string>Claude Profile Usage</string>
    <key>CFBundleExecutable</key><string>ClaudeProfileUsage</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Widget extension: must be sandboxed, and signed before the app that contains it.
APPEX="$APP/Contents/PlugIns/ClaudeProfileUsageWidget.appex"
mkdir -p "$APPEX/Contents/MacOS"
cp "$BIN/ClaudeProfileUsageWidget" "$APPEX/Contents/MacOS/ClaudeProfileUsageWidget"
cp scripts/widget/Info.plist "$APPEX/Contents/Info.plist"
codesign --force --sign - --entitlements scripts/widget/widget.entitlements "$APPEX"

codesign --force --sign - "$APP"
codesign --force --sign - dist/claude-usage
echo "Built $APP and dist/claude-usage"
