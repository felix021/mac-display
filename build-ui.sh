#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT_DIR/build"
APP_NAME="MacDisplayControl"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
EXECUTABLE="$MACOS_DIR/$APP_NAME"
ICONSET_DIR="$BUILD_DIR/MacDisplay.iconset"
ICON_FILE="$RESOURCES_DIR/MacDisplay.icns"
SOURCE_ENABLED_IMAGE="$ROOT_DIR/assets/MacDisplayEnabled.png"
SOURCE_DISABLED_IMAGE="$ROOT_DIR/assets/MacDisplayDisabled.png"
SOURCE_TRAY_ENABLED_IMAGE="$ROOT_DIR/assets/MacDisplayTrayEnabled.png"
SOURCE_TRAY_DISABLED_IMAGE="$ROOT_DIR/assets/MacDisplayTrayDisabled.png"
ENABLED_IMAGE="$RESOURCES_DIR/MacDisplayEnabled.png"
DISABLED_IMAGE="$RESOURCES_DIR/MacDisplayDisabled.png"
TRAY_ENABLED_IMAGE="$RESOURCES_DIR/MacDisplayTrayEnabled.png"
TRAY_DISABLED_IMAGE="$RESOURCES_DIR/MacDisplayTrayDisabled.png"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

if [ ! -f "$SOURCE_ENABLED_IMAGE" ]; then
  echo "Missing icon source: $SOURCE_ENABLED_IMAGE" >&2
  exit 1
fi

if [ ! -f "$SOURCE_DISABLED_IMAGE" ]; then
  echo "Missing icon source: $SOURCE_DISABLED_IMAGE" >&2
  exit 1
fi

if [ ! -f "$SOURCE_TRAY_ENABLED_IMAGE" ]; then
  echo "Missing tray icon source: $SOURCE_TRAY_ENABLED_IMAGE" >&2
  exit 1
fi

if [ ! -f "$SOURCE_TRAY_DISABLED_IMAGE" ]; then
  echo "Missing tray icon source: $SOURCE_TRAY_DISABLED_IMAGE" >&2
  exit 1
fi

clang \
  -fobjc-arc \
  -fblocks \
  -framework Foundation \
  -framework AppKit \
  "$ROOT_DIR/ui/main.m" \
  -o "$EXECUTABLE"

cp "$SOURCE_ENABLED_IMAGE" "$ENABLED_IMAGE"
cp "$SOURCE_DISABLED_IMAGE" "$DISABLED_IMAGE"
cp "$SOURCE_TRAY_ENABLED_IMAGE" "$TRAY_ENABLED_IMAGE"
cp "$SOURCE_TRAY_DISABLED_IMAGE" "$TRAY_DISABLED_IMAGE"

rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"
sips -z 16 16 "$ENABLED_IMAGE" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -z 32 32 "$ENABLED_IMAGE" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$ENABLED_IMAGE" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -z 64 64 "$ENABLED_IMAGE" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$ENABLED_IMAGE" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 256 256 "$ENABLED_IMAGE" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$ENABLED_IMAGE" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 512 512 "$ENABLED_IMAGE" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$ENABLED_IMAGE" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$ENABLED_IMAGE" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null
iconutil -c icns "$ICONSET_DIR" -o "$ICON_FILE"

cat >"$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>com.felix021.macdisplay.control</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>MacDisplay</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>11.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

echo "$APP_DIR"
