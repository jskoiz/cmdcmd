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

package_archive_name="$(sed -n 's/^ARCHIVE_NAME="\([^"]*\)"$/\1/p' scripts/package_macos.sh)"
local_install_archive_name="$(sed -n 's/^LOCAL_ARCHIVE_NAME="\([^"]*\)"$/\1/p' site/install.sh)"
if [[ -z "$package_archive_name" || "$package_archive_name" != "$local_install_archive_name" ]]; then
  echo "Local package/install archive names do not match." >&2
  exit 1
fi

if grep -Eq 'executablePath|"accessibility":"granted"' site/install.sh; then
  echo "site/install.sh still depends on removed health diagnostics." >&2
  exit 1
fi

echo "== native relay tests =="
swift test --package-path macos/CmdCmdRelay

if [[ "$fast" == true ]]; then
  exit 0
fi

derived_data="${CMDCMD_DERIVED_DATA:-/tmp/codex-xcode-derived-data/cmdcmd-modernization}"
mkdir -p "$derived_data"

test_destination="${CMDCMD_TEST_DESTINATION:-}"
if [[ -z "$test_destination" ]]; then
  simulator_id="$(
    xcrun simctl list devices available | awk '
      /^-- iOS / { in_ios = 1; next }
      /^-- / { if (in_ios) exit; next }
      in_ios && match($0, /\([0-9A-Fa-f-][0-9A-Fa-f-]*\) \((Booted|Shutdown)\)/) {
        id = substr($0, RSTART + 1, RLENGTH - 1)
        sub(/\).*/, "", id)
        print id
        exit
      }
    '
  )"
  if [[ -z "$simulator_id" ]]; then
    echo "No available iOS Simulator was found." >&2
    exit 1
  fi
  test_destination="platform=iOS Simulator,id=$simulator_id"
fi

echo "== iOS test destination: $test_destination =="
echo "== iOS tests =="
xcodebuild \
  -project CmdCmd.xcodeproj \
  -scheme CmdCmd \
  -configuration Debug \
  -destination "$test_destination" \
  -derivedDataPath "$derived_data" \
  CODE_SIGNING_ALLOWED=NO \
  test

echo "== generic iOS app build =="
xcodebuild \
  -project CmdCmd.xcodeproj \
  -scheme CmdCmd \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$derived_data" \
  CODE_SIGNING_ALLOWED=NO \
  build

echo "== generic Share Extension build =="
xcodebuild \
  -project CmdCmd.xcodeproj \
  -scheme CmdCmdShareExtension \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$derived_data" \
  CODE_SIGNING_ALLOWED=NO \
  build
