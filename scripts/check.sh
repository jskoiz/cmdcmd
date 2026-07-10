#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 [--fast]" >&2
}

fast=false
case "${1:-}" in
  "") ;;
  --fast) fast=true ;;
  *) usage; exit 2 ;;
esac
if (( $# > 1 )); then
  usage
  exit 2
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

echo "== shell syntax =="
bash -n scripts/*.sh site/install.sh

echo "== node tests =="
npm --prefix relay test

echo "== swift tests =="
swift test --package-path macos/CmdCmdRelay

if [[ "$fast" == false ]]; then
  echo "== iOS build =="
  derived_data="${CMDCMD_DERIVED_DATA:-/tmp/codex-xcode-derived-data/cmdcmd}"
  xcodebuild \
    -project CmdCmd.xcodeproj \
    -scheme CmdCmd \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "$derived_data" \
    CODE_SIGNING_ALLOWED=NO \
    build
fi
