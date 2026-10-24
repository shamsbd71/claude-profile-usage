#!/usr/bin/env bash
# Builds and installs "Claude Profile Usage" into ~/Applications and `claude-usage` into ~/.local/bin.
# The built bundle is moved (not copied), so exactly one copy of the app exists on disk.
set -euo pipefail

cd "$(dirname "$0")/.."
./scripts/bundle.sh

APP_NAME=ClaudeProfileUsage.app
DEST="$HOME/Applications/$APP_NAME"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

pkill -x ClaudeProfileUsage 2>/dev/null || true
mkdir -p "$HOME/Applications" "$HOME/.local/bin"
rm -rf "$DEST"
mv "dist/$APP_NAME" "$DEST"
mv dist/claude-usage "$HOME/.local/bin/claude-usage"
"$LSREGISTER" -u "$PWD/dist/$APP_NAME" 2>/dev/null || true

# Register the widget extension so it shows up in the widget gallery.
pluginkit -a "$DEST/Contents/PlugIns/ClaudeProfileUsageWidget.appex" || true
open "$DEST"
echo "Installed $DEST and ~/.local/bin/claude-usage"
