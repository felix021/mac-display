#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$ROOT_DIR/lib/common.sh"

require_install

if is_enabled; then
  bash "$ROOT_DIR/disable.sh"
else
  bash "$ROOT_DIR/enable.sh"
fi
