#!/usr/bin/env bash
set -euo pipefail

xcodebuild \
  -project CmdCmd.xcodeproj \
  -scheme CmdCmd \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO \
  build

