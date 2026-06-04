#!/usr/bin/env bash
set -euo pipefail

xcodebuild \
  -project CodexShot.xcodeproj \
  -scheme CodexShot \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO \
  build

