#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_DIR="$ROOT_DIR/build"
OUTPUT_BIN="$OUTPUT_DIR/MacDisplayAgent"

mkdir -p "$OUTPUT_DIR"

clang \
  -fobjc-arc \
  -fblocks \
  -framework Foundation \
  -framework AppKit \
  -framework CoreGraphics \
  "$ROOT_DIR/src/main.m" \
  -o "$OUTPUT_BIN"

echo "$OUTPUT_BIN"
