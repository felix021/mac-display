#!/bin/bash
set -euo pipefail

APP_SUPPORT_DIR="$HOME/Library/Application Support/MacDisplay"
PLIST_PATH="$HOME/Library/LaunchAgents/com.felix021.macdisplay.plist"
LABEL="com.felix021.macdisplay"
LEGACY_APP_SUPPORT_DIR="$HOME/Library/Application Support/InternalDisplayAutoDim"
LEGACY_PLIST_PATH="$HOME/Library/LaunchAgents/com.codex.internaldisplayautodim.plist"
LEGACY_LABEL="com.codex.internaldisplayautodim"

launchctl bootout "gui/$UID" "$PLIST_PATH" >/dev/null 2>&1 || true
rm -f "$PLIST_PATH"
rm -rf "$APP_SUPPORT_DIR"
launchctl bootout "gui/$UID" "$LEGACY_PLIST_PATH" >/dev/null 2>&1 || true
rm -f "$LEGACY_PLIST_PATH"
rm -rf "$LEGACY_APP_SUPPORT_DIR"

echo "Removed $LABEL"
echo "Removed legacy label $LEGACY_LABEL if present"
