#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_DIR="$ROOT_DIR/macos/CmdCmdRelay"
DIST_DIR="$ROOT_DIR/dist/cmdcmd-relay"
APP_NAME="cmd+cmd Relay.app"
APP_DIR="$DIST_DIR/$APP_NAME"
ARCHIVE_NAME="CmdCmdRelay-macOS.zip"
ZIP_PATH="$DIST_DIR/$ARCHIVE_NAME"
EXECUTABLE="$PACKAGE_DIR/.build/release/CmdCmdRelayApp"
INFO_PLIST="$PACKAGE_DIR/Packaging/Info.plist"
ICON_SOURCE="$ROOT_DIR/CmdCmd/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"

rm -rf "$DIST_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

swift build --package-path "$PACKAGE_DIR" -c release

cp "$EXECUTABLE" "$APP_DIR/Contents/MacOS/CmdCmdRelayApp"
cp "$INFO_PLIST" "$APP_DIR/Contents/Info.plist"

if [[ -f "$ICON_SOURCE" ]]; then
  ICONSET="$DIST_DIR/AppIcon.iconset"
  mkdir -p "$ICONSET"
  for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$ICON_SOURCE" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z "$((size * 2))" "$((size * 2))" "$ICON_SOURCE" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP_DIR/Contents/Resources/AppIcon.icns"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP_DIR/Contents/Info.plist" >/dev/null 2>&1 ||
    /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon" "$APP_DIR/Contents/Info.plist"
fi

if [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
  codesign --force --deep --options runtime --sign "$DEVELOPER_ID_APPLICATION" "$APP_DIR"
  codesign --verify --deep --strict "$APP_DIR"
fi

ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"
(
  cd "$DIST_DIR"
  shasum -a 256 "$ARCHIVE_NAME" > "$ARCHIVE_NAME.sha256"
)

echo "Packaged $APP_DIR"
echo "Archive  $ZIP_PATH"
echo "SHA-256  $(awk '{print $1}' "$ZIP_PATH.sha256")"
