#!/usr/bin/env bash
# Regenerates scripts/AppIcon.icns from the icon drawn in ScreenshotRenderer.renderIcon.
set -euo pipefail

cd "$(dirname "$0")/.."
swift build --product ClaudeProfileUsage
TMP=$(mktemp -d)
CPU_RENDER_ICON="$TMP/icon.png" "$(swift build --show-bin-path)/ClaudeProfileUsage"
[ -s "$TMP/icon.png" ] || { echo "icon render failed" >&2; exit 1; }
mkdir "$TMP/AppIcon.iconset"
for size in 16 32 128 256 512; do
    sips -z $size $size "$TMP/icon.png" --out "$TMP/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) "$TMP/icon.png" --out "$TMP/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$TMP/AppIcon.iconset" -o scripts/AppIcon.icns
rm -rf "$TMP"
echo "Wrote scripts/AppIcon.icns"
