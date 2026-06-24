#!/bin/bash

LABEL="com.felix021.macdisplay"
PLIST_PATH="$HOME/Library/LaunchAgents/$LABEL.plist"
APP_SUPPORT_DIR="$HOME/Library/Application Support/MacDisplay"
INSTALLED_BINARY="$APP_SUPPORT_DIR/MacDisplayAgent"
LOG_PATH="$APP_SUPPORT_DIR/agent.log"

is_enabled() {
  launchctl print "gui/$UID/$LABEL" >/dev/null 2>&1
}

require_install() {
  if [ ! -f "$PLIST_PATH" ] || [ ! -x "$INSTALLED_BINARY" ]; then
    echo "mac-display is not installed. Run: bash install.sh" >&2
    exit 1
  fi
}
