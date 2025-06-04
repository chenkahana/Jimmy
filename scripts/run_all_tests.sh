#!/usr/bin/env bash
set -euo pipefail

# Run all tests. On macOS use xcodebuild if available, otherwise fall back to
# Swift Package Manager.
if command -v xcodebuild >/dev/null 2>&1; then
  xcodebuild \
    -project Jimmy.xcodeproj \
    -scheme Jimmy \
    -destination 'platform=iOS Simulator,name=iPhone 15,OS=latest' \
    -skipPackagePluginValidation \
    CODE_SIGNING_REQUIRED=NO \
    test | xcpretty
else
  swift test --enable-code-coverage
fi
