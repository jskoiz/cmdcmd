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
RELAY_HEALTH_URL="http://127.0.0.1:8787/healthz"
RELEASE_BASE_URL="${CMDCMD_RELAY_RELEASE_URL:-https://www.cmdcmd.click/dl}"
ARCHIVE_NAME="${CMDCMD_RELAY_ARCHIVE_NAME:-CmdCmdRelay-macOS-20260611-2.zip}"
LOCAL_ARCHIVE_NAME="CmdCmdRelay-macOS.zip"
EXPECTED_TEAM_IDENTIFIER="H8PYU9TN9X"
REVIEW_MODE="0"
SCRIPT_SOURCE="${BASH_SOURCE[0]:-}"
if [[ -n "$SCRIPT_SOURCE" && "$SCRIPT_SOURCE" != bash ]]; then
  ROOT_DIR="$(cd "$(dirname "$SCRIPT_SOURCE")/.." && pwd)"
else
  ROOT_DIR="$(pwd)"
fi
LOCAL_ARCHIVE="$ROOT_DIR/dist/cmdcmd-relay/$LOCAL_ARCHIVE_NAME"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

usage() {
  cat <<'USAGE'
Usage: install.sh [--review-mode]

Installs the cmd+cmd Relay bundle, starts the private background relay, waits
until it is ready, and prints a QR code for the iOS app to scan.

Options:
  --review-mode               Save screenshots to a local Review Inbox instead
                              of sending them to Codex Desktop.

Environment:
  INSTALL_DIR                 Override destination bundle directory.
  CMDCMD_RELAY_RELEASE_URL    Override release download base URL.
  CMDCMD_RELAY_REVIEW_MODE    Set to 1 to enable review mode.
USAGE
}

case "${CMDCMD_RELAY_REVIEW_MODE:-0}" in
  1|true|TRUE|yes|YES)
    REVIEW_MODE="1"
    ;;
esac

for arg in "$@"; do
  case "$arg" in
    -h|--help)
      usage
      exit 0
      ;;
    --review-mode)
      REVIEW_MODE="1"
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
    if [[ ! -f "$LOCAL_ARCHIVE.sha256" ]]; then
      echo "Missing checksum for local archive: $LOCAL_ARCHIVE.sha256" >&2
      exit 1
    fi
    cp "$LOCAL_ARCHIVE.sha256" "$checksum"
  else
    curl -fsSL "$RELEASE_BASE_URL/$ARCHIVE_NAME" -o "$archive"
    curl -fsSL "$RELEASE_BASE_URL/$ARCHIVE_NAME.sha256" -o "$checksum"
  fi

  local expected
  local actual
  expected="$(awk 'NF {print $1; exit}' "$checksum")"
  if [[ ${#expected} -ne 64 || "$expected" == *[!0-9A-Fa-f]* ]]; then
    echo "Invalid checksum for $ARCHIVE_NAME" >&2
    exit 1
  fi
  actual="$(shasum -a 256 "$archive" | awk '{print $1}')"
  if [[ "$expected" != "$actual" ]]; then
    echo "Checksum mismatch for $ARCHIVE_NAME" >&2
    exit 1
  fi

  echo "$archive"
}

stop_existing_relay() {
  launchctl bootout "gui/$(id -u)" "$LAUNCH_AGENT_PLIST" >/dev/null 2>&1 || true
  pkill -f "cmd\\+cmd Relay\\.app/Contents/MacOS/CmdCmdRelayApp" >/dev/null 2>&1 || true
  pkill -f "CmdCmdRelayApp --serve" >/dev/null 2>&1 || true
}

wait_for_existing_relay_to_stop() {
  for _ in {1..40}; do
    if ! pgrep -f "CmdCmdRelayApp --serve" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.25
  done

  echo "Existing cmd+cmd Relay process did not stop." >&2
  pgrep -af "CmdCmdRelayApp --serve" >&2 || true
  exit 1
}

prepare_pairing() {
  if [[ ! -x "$RELAY_EXECUTABLE" ]]; then
    echo "Could not find relay executable." >&2
    exit 1
  fi

  if [[ "$REVIEW_MODE" == "1" ]]; then
    "$RELAY_EXECUTABLE" --prepare-review-pairing
  else
    "$RELAY_EXECUTABLE" --prepare-pairing
  fi
  RELAY_HEALTH_URL="$("$RELAY_EXECUTABLE" --print-health-url)"
}

start_background_relay() {
  mkdir -p "$LOG_DIR"
  "$RELAY_EXECUTABLE" --serve-detached >>"$OUT_LOG" 2>>"$ERR_LOG"
}

wait_for_relay() {
  for _ in {1..40}; do
    if curl -fsS "$RELAY_HEALTH_URL" 2>/dev/null | grep -q '"relay":"cmdcmd-native"'; then
      return 0
    fi
    sleep 0.25
  done

  echo "Relay did not become reachable on $RELAY_HEALTH_URL." >&2
  echo "Recent relay log:" >&2
  if [[ -f "$ERR_LOG" ]]; then
    tail -n 20 "$ERR_LOG" >&2 || true
  else
    echo "No error log yet at $ERR_LOG" >&2
  fi
  exit 1
}

wait_for_relay_accessibility() {
  if [[ "$REVIEW_MODE" == "1" ]]; then
    return 0
  fi

  for _ in {1..60}; do
    if "$RELAY_EXECUTABLE" --accessibility-status >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.5
  done

  echo "Accessibility is still not available to cmd+cmd Relay." >&2
  echo "If the row is already enabled in System Settings, remove cmd+cmd Relay with the minus button, rerun this installer, and approve it again." >&2
  echo "Installed relay: $APP_PATH" >&2
  exit 1
}

request_accessibility() {
  if [[ "$REVIEW_MODE" == "1" ]]; then
    echo "Review mode enabled. Codex Desktop and Accessibility are not required."
    return
  fi

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
wait_for_existing_relay_to_stop

mkdir -p "$INSTALL_DIR"
rm -rf "$APP_PATH"
ditto "$FOUND_APP" "$APP_PATH"

if codesign --verify --deep --strict "$APP_PATH" >/dev/null 2>&1; then
  echo "Signature verified."
else
  echo "Installed bundle signature verification failed." >&2
  exit 1
fi

SIGNING_INFO="$(codesign -dv --verbose=4 "$APP_PATH" 2>&1)"
TEAM_IDENTIFIER="$(awk -F= '/^TeamIdentifier=/ {print $2; exit}' <<<"$SIGNING_INFO")"
if [[ "$TEAM_IDENTIFIER" != "$EXPECTED_TEAM_IDENTIFIER" ]]; then
  echo "Installed bundle is not signed by the expected developer team." >&2
  exit 1
fi
echo "Developer team verified."

prepare_pairing
request_accessibility
start_background_relay
wait_for_relay
wait_for_relay_accessibility
print_pairing_qr

if [[ "$REVIEW_MODE" == "1" ]]; then
  cat <<EOF
Installed: $APP_PATH
Background process: CmdCmdRelayApp
Logs: $ERR_LOG

Next:
1. Open cmd+cmd on iPhone.
2. In Settings, tap Scan Desktop QR and scan the QR above.
3. Send a screenshot. This Mac opens the local Review Inbox.
EOF
else
  cat <<EOF
Installed: $APP_PATH
Background process: CmdCmdRelayApp
Logs: $ERR_LOG

Next:
1. Open cmd+cmd on iPhone.
2. In Settings, tap Scan Desktop QR and scan the QR above.
3. Send screenshots to Codex Desktop.
EOF
fi
