#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$ROOT_DIR/lib/common.sh"

if [ ! -f "$PLIST_PATH" ] || [ ! -x "$INSTALLED_BINARY" ]; then
  echo "not installed"
  exit 0
fi

if is_enabled; then
  echo "enabled"
else
  echo "disabled"
fi
