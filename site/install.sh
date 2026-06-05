#!/usr/bin/env bash
set -euo pipefail

APP_NAME="cmd+cmd Relay.app"
INSTALL_DIR="${INSTALL_DIR:-$HOME/Applications}"
APP_PATH="$INSTALL_DIR/$APP_NAME"
RELEASE_BASE_URL="${CMDCMD_RELAY_RELEASE_URL:-https://cmd.avmil.xyz/dl}"
ARCHIVE_NAME="CmdCmdRelay-macOS.zip"
SCRIPT_SOURCE="${BASH_SOURCE[0]:-}"
if [[ -n "$SCRIPT_SOURCE" && "$SCRIPT_SOURCE" != bash ]]; then
  ROOT_DIR="$(cd "$(dirname "$SCRIPT_SOURCE")/.." && pwd)"
else
  ROOT_DIR="$(pwd)"
fi
LOCAL_ARCHIVE="$ROOT_DIR/dist/cmdcmd-relay/$ARCHIVE_NAME"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

usage() {
  cat <<'USAGE'
Usage: scripts/install-macos.sh [--start-at-login] [--no-open]

Installs cmd+cmd Relay.app into ~/Applications by default.

Environment:
  INSTALL_DIR                 Override destination app directory.
  CMDCMD_RELAY_RELEASE_URL    Override release download base URL.
USAGE
}

START_AT_LOGIN=0
NO_OPEN=0
for arg in "$@"; do
  case "$arg" in
    --start-at-login)
      START_AT_LOGIN=1
      ;;
    --no-open)
      NO_OPEN=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      usage
      exit 64
      ;;
  esac
done

download_archive() {
  local archive="$TMP_DIR/$ARCHIVE_NAME"
  local checksum="$TMP_DIR/$ARCHIVE_NAME.sha256"

  if [[ -f "$LOCAL_ARCHIVE" ]]; then
    cp "$LOCAL_ARCHIVE" "$archive"
    if [[ -f "$LOCAL_ARCHIVE.sha256" ]]; then
      cp "$LOCAL_ARCHIVE.sha256" "$checksum"
    fi
  else
    curl -fsSL "$RELEASE_BASE_URL/$ARCHIVE_NAME" -o "$archive"
    curl -fsSL "$RELEASE_BASE_URL/$ARCHIVE_NAME.sha256" -o "$checksum" || true
  fi

  if [[ -f "$checksum" ]]; then
    local expected
    local actual
    expected="$(awk '{print $1}' "$checksum")"
    actual="$(shasum -a 256 "$archive" | awk '{print $1}')"
    if [[ "$expected" != "$actual" ]]; then
      echo "Checksum mismatch for $ARCHIVE_NAME" >&2
      exit 1
    fi
  fi

  echo "$archive"
}

install_launch_agent() {
  local plist="$HOME/Library/LaunchAgents/app.cmdcmd.relay.plist"
  mkdir -p "$(dirname "$plist")"
  cat > "$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>app.cmdcmd.relay</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/open</string>
    <string>-a</string>
    <string>$APP_PATH</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
</dict>
</plist>
PLIST
  launchctl unload "$plist" >/dev/null 2>&1 || true
  launchctl load "$plist"
}

ARCHIVE="$(download_archive)"
ditto -x -k "$ARCHIVE" "$TMP_DIR/unpacked"

FOUND_APP="$(find "$TMP_DIR/unpacked" -maxdepth 2 -name "$APP_NAME" -type d | head -n 1)"
if [[ -z "$FOUND_APP" ]]; then
  echo "Could not find $APP_NAME in archive." >&2
  exit 1
fi

mkdir -p "$INSTALL_DIR"
rm -rf "$APP_PATH"
ditto "$FOUND_APP" "$APP_PATH"

if codesign --verify --deep --strict "$APP_PATH" >/dev/null 2>&1; then
  echo "Signature verified."
else
  echo "Installed app is not signed or signature verification failed." >&2
fi

if [[ "$START_AT_LOGIN" == "1" ]]; then
  install_launch_agent
fi

if [[ "$NO_OPEN" == "0" ]]; then
  open "$APP_PATH"
fi

cat <<EOF
Installed: $APP_PATH

Next:
1. Grant Accessibility permission when macOS asks.
2. Enable private-network mode in cmd+cmd Relay if pairing a physical iPhone.
3. Scan the pairing code from the iPhone app.
EOF
