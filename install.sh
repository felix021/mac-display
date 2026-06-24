#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_SUPPORT_DIR="$HOME/Library/Application Support/MacDisplay"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
APPLICATIONS_DIR="$HOME/Applications"
PLIST_PATH="$LAUNCH_AGENTS_DIR/com.felix021.macdisplay.plist"
BINARY_NAME="MacDisplayAgent"
INSTALLED_BINARY="$APP_SUPPORT_DIR/$BINARY_NAME"
UI_APP_NAME="MacDisplayControl.app"
INSTALLED_UI_APP="$APPLICATIONS_DIR/$UI_APP_NAME"
LOG_PATH="$APP_SUPPORT_DIR/agent.log"
LABEL="com.felix021.macdisplay"
LEGACY_LABEL="com.codex.internaldisplayautodim"
LEGACY_PLIST_PATH="$LAUNCH_AGENTS_DIR/$LEGACY_LABEL.plist"

mkdir -p "$APP_SUPPORT_DIR" "$LAUNCH_AGENTS_DIR" "$APPLICATIONS_DIR"

bash "$ROOT_DIR/build.sh" >/dev/null
cp "$ROOT_DIR/build/$BINARY_NAME" "$INSTALLED_BINARY"
chmod +x "$INSTALLED_BINARY"
rm -rf "$INSTALLED_UI_APP"
cp -R "$ROOT_DIR/build/$UI_APP_NAME" "$INSTALLED_UI_APP"

cat >"$PLIST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$INSTALLED_BINARY</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>$LOG_PATH</string>
  <key>StandardErrorPath</key>
  <string>$LOG_PATH</string>
  <key>ProcessType</key>
  <string>Interactive</string>
</dict>
</plist>
PLIST

launchctl bootout "gui/$UID" "$LEGACY_PLIST_PATH" >/dev/null 2>&1 || true
rm -f "$LEGACY_PLIST_PATH"
launchctl bootout "gui/$UID" "$PLIST_PATH" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$UID" "$PLIST_PATH"
launchctl kickstart -k "gui/$UID/$LABEL"

echo "Installed $LABEL"
echo "Binary: $INSTALLED_BINARY"
echo "UI app: $INSTALLED_UI_APP"
echo "LaunchAgent: $PLIST_PATH"
echo "Log: $LOG_PATH"

open -gj "$INSTALLED_UI_APP" >/dev/null 2>&1 || true
