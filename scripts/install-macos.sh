#!/usr/bin/env bash
set -euo pipefail

APP_NAME="cmd+cmd Relay.app"
INSTALL_DIR="${INSTALL_DIR:-$HOME/Library/Application Support/cmdcmd-relay}"
APP_PATH="$INSTALL_DIR/$APP_NAME"
RELAY_EXECUTABLE="$APP_PATH/Contents/MacOS/CmdCmdRelayApp"
LAUNCH_AGENT_LABEL="app.cmdcmd.relay"
LAUNCH_AGENT_PLIST="$HOME/Library/LaunchAgents/$LAUNCH_AGENT_LABEL.plist"
LOG_DIR="$HOME/Library/Logs"
OUT_LOG="$LOG_DIR/cmdcmd-relay.log"
ERR_LOG="$LOG_DIR/cmdcmd-relay.err.log"
RELEASE_BASE_URL="${CMDCMD_RELAY_RELEASE_URL:-https://github.com/jskoiz/cmdcmd/releases/latest/download}"
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
Usage: scripts/install-macos.sh

Installs the cmd+cmd Relay bundle, starts the private background relay, waits
until it is ready, and prints a QR code for the iOS app to scan.

Environment:
  INSTALL_DIR                 Override destination bundle directory.
  CMDCMD_RELAY_RELEASE_URL    Override release download base URL.
USAGE
}

for arg in "$@"; do
  case "$arg" in
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

stop_existing_relay() {
  local pids
  launchctl bootout "gui/$(id -u)" "$LAUNCH_AGENT_PLIST" >/dev/null 2>&1 || true
  pids="$(pgrep -f "cmd\\+cmd Relay\\.app/Contents/MacOS/CmdCmdRelayApp" || true)"
  if [[ -n "$pids" ]]; then
    kill $pids >/dev/null 2>&1 || true
  fi
}

prepare_pairing() {
  if [[ ! -x "$RELAY_EXECUTABLE" ]]; then
    echo "Could not find relay executable." >&2
    exit 1
  fi

  "$RELAY_EXECUTABLE" --prepare-pairing
}

install_launch_agent() {
  mkdir -p "$(dirname "$LAUNCH_AGENT_PLIST")" "$LOG_DIR"
  cat > "$LAUNCH_AGENT_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LAUNCH_AGENT_LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$RELAY_EXECUTABLE</string>
    <string>--serve</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>ProcessType</key>
  <string>Background</string>
  <key>StandardOutPath</key>
  <string>$OUT_LOG</string>
  <key>StandardErrorPath</key>
  <string>$ERR_LOG</string>
</dict>
</plist>
PLIST

  launchctl bootout "gui/$(id -u)" "$LAUNCH_AGENT_PLIST" >/dev/null 2>&1 || true
  launchctl bootstrap "gui/$(id -u)" "$LAUNCH_AGENT_PLIST"
  launchctl kickstart -k "gui/$(id -u)/$LAUNCH_AGENT_LABEL" >/dev/null 2>&1 || true
}

wait_for_relay() {
  for _ in {1..40}; do
    if curl -fsS "http://127.0.0.1:8787/healthz" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.25
  done

  echo "Relay did not become reachable on http://127.0.0.1:8787/healthz." >&2
  echo "Recent relay log:" >&2
  if [[ -f "$ERR_LOG" ]]; then
    tail -n 20 "$ERR_LOG" >&2 || true
  else
    echo "No error log yet at $ERR_LOG" >&2
  fi
  exit 1
}

request_accessibility() {
  if "$RELAY_EXECUTABLE" --accessibility-status >/dev/null 2>&1; then
    echo "Accessibility permission already granted."
    return
  fi

  echo "Requesting Accessibility permission for screenshot delivery..."
  "$RELAY_EXECUTABLE" --request-accessibility || true
}

print_pairing_qr() {
  if [[ ! -x "$RELAY_EXECUTABLE" ]]; then
    echo "Could not find relay executable for pairing QR." >&2
    exit 1
  fi

  "$RELAY_EXECUTABLE" --print-pairing-qr
}

ARCHIVE="$(download_archive)"
ditto -x -k "$ARCHIVE" "$TMP_DIR/unpacked"

FOUND_APP="$(find "$TMP_DIR/unpacked" -maxdepth 2 -name "$APP_NAME" -type d | head -n 1)"
if [[ -z "$FOUND_APP" ]]; then
  echo "Could not find relay bundle in archive." >&2
  exit 1
fi

stop_existing_relay

mkdir -p "$INSTALL_DIR"
rm -rf "$APP_PATH"
ditto "$FOUND_APP" "$APP_PATH"

if codesign --verify --deep --strict "$APP_PATH" >/dev/null 2>&1; then
  echo "Signature verified."
else
  echo "Installed bundle is not signed or signature verification failed." >&2
fi

prepare_pairing
install_launch_agent
wait_for_relay
request_accessibility
print_pairing_qr

cat <<EOF
Installed: $APP_PATH
Background service: $LAUNCH_AGENT_LABEL
Logs: $ERR_LOG

Next:
1. Open cmd+cmd on iPhone, go to Settings, and tap Scan Desktop QR.
2. Scan the QR printed above.
3. Send screenshots into the active Codex Desktop chat.
EOF
