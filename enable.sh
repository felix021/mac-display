#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$ROOT_DIR/lib/common.sh"

require_install

if is_enabled; then
  echo "mac-display is already enabled"
  exit 0
fi

launchctl bootstrap "gui/$UID" "$PLIST_PATH"
launchctl kickstart -k "gui/$UID/$LABEL"

echo "Enabled $LABEL"
