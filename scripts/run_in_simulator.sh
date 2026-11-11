#!/bin/bash
# run_in_simulator.sh — Build, install, launch, and screenshot Jimmy in the iOS Simulator
set -euo pipefail

SCHEME="Jimmy"
PROJECT="Jimmy.xcodeproj"
DESTINATION="platform=iOS Simulator,name=iPhone 17 Pro"
BUNDLE_ID="com.chenkahana.Jimmy"
SCREENSHOT_DIR="/tmp"
SIMULATOR_NAME="iPhone 17 Pro"
DERIVED_DATA="build/DerivedData"

print_preflight_failure() {
    local reason="$1"
    local details="${2:-}"

    echo "ERROR: $reason" >&2
    if [ -n "$details" ]; then
        echo "$details" >&2
    fi
    cat >&2 <<'EOF'

Recommended fixes:
  1. Run: xcodebuild -runFirstLaunch
  2. Open Xcode once and let it finish installing simulator components
  3. Re-run this script
EOF
    exit 1
}

run_preflight() {
    local xcode_output
    local simctl_output

    if ! xcode_output=$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -destination "$DESTINATION" -showBuildSettings 2>&1); then
        if [[ "$xcode_output" == *"runFirstLaunch"* ]] || [[ "$xcode_output" == *"IDESimulatorFoundation"* ]]; then
            print_preflight_failure \
                "Xcode is not ready to build for the simulator." \
                "$xcode_output"
        fi
        print_preflight_failure \
            "Xcode preflight failed before the build started." \
            "$xcode_output"
    fi

    if ! simctl_output=$(xcrun simctl list devices 2>&1); then
        print_preflight_failure \
            "CoreSimulator is not ready." \
            "$simctl_output"
    fi

    if ! grep -q "$SIMULATOR_NAME" <<<"$simctl_output"; then
        print_preflight_failure \
            "Required simulator '$SIMULATOR_NAME' is not installed." \
            "$simctl_output"
    fi
}

# Parse flags
SKIP_BUILD=false
for arg in "$@"; do
    case "$arg" in
        --skip-build) SKIP_BUILD=true ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

echo "==> Generating $PROJECT..."
make project

echo "==> Running Xcode/simulator preflight..."
run_preflight

# 1. Build
if [ "$SKIP_BUILD" = false ]; then
    echo "==> Building $SCHEME..."
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
        -derivedDataPath "$DERIVED_DATA" \
        -destination "$DESTINATION" build \
        2>&1 | tail -5
    echo "==> Build succeeded."
else
    echo "==> Skipping build (--skip-build)."
fi

# 2. Boot simulator if needed
BOOT_STATUS=$(xcrun simctl list devices booted | grep -c "Booted" || true)
if [ "$BOOT_STATUS" -eq 0 ]; then
    echo "==> Booting simulator..."
    xcrun simctl boot "$SIMULATOR_NAME" 2>/dev/null || true
    sleep 3
fi

# 3. Find the built .app
APP_PATH=$(find "$DERIVED_DATA/Build/Products/Debug-iphonesimulator" \
    -name "Jimmy.app" -maxdepth 1 2>/dev/null | head -1)
if [ -z "$APP_PATH" ]; then
    echo "ERROR: Could not find Jimmy.app in DerivedData. Did the build succeed?"
    exit 1
fi
echo "==> Found app: $APP_PATH"

# 4. Install
echo "==> Installing..."
xcrun simctl install booted "$APP_PATH"

# 5. Launch
echo "==> Launching..."
xcrun simctl launch booted "$BUNDLE_ID"

# 6. Wait for app to render
sleep 2

# 7. Screenshot
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
SCREENSHOT_PATH="${SCREENSHOT_DIR}/jimmy_${TIMESTAMP}.png"
xcrun simctl io booted screenshot "$SCREENSHOT_PATH"
echo ""
echo "==> Screenshot saved: $SCREENSHOT_PATH"
echo "    Use the Read tool to view it."
