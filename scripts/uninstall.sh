#!/usr/bin/env bash
# Removes the app, its widget, the CLI and the widget snapshot. Your Claude logins are not touched.
set -euo pipefail

APP="$HOME/Applications/ClaudeProfileUsage.app"
pkill -x ClaudeProfileUsage 2>/dev/null || true
pluginkit -r "$APP/Contents/PlugIns/ClaudeProfileUsageWidget.appex" 2>/dev/null || true
rm -rf "$APP" "$HOME/.local/bin/claude-usage" "$HOME/Library/Application Support/ClaudeProfileUsage"
echo "Uninstalled Claude Profile Usage"
