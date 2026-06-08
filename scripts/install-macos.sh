#!/usr/bin/env bash
set -euo pipefail

# Installs the cmd+cmd Relay from the latest GitHub release.
#
# This is a thin wrapper over site/install.sh (the canonical installer served at
# https://cmd.avmil.xyz/install.sh). It only swaps in the GitHub-release download
# defaults; all install logic, flags, and environment overrides live there.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export CMDCMD_RELAY_RELEASE_URL="${CMDCMD_RELAY_RELEASE_URL:-https://github.com/jskoiz/cmdcmd/releases/latest/download}"
export CMDCMD_RELAY_ARCHIVE_NAME="${CMDCMD_RELAY_ARCHIVE_NAME:-CmdCmdRelay-macOS.zip}"

exec "$HERE/../site/install.sh" "$@"
