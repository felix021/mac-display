#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$ROOT_DIR/lib/common.sh"

require_install

if ! is_enabled; then
  echo "mac-display is already disabled"
  exit 0
fi

"$INSTALLED_BINARY" --restore --once >/dev/null 2>&1 || true
launchctl bootout "gui/$UID" "$PLIST_PATH"

echo "Disabled $LABEL"
