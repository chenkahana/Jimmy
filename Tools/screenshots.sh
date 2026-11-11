#!/bin/bash
# Tools/screenshots.sh — build Jimmy, seed its `-demoLibrary` demo data, and capture every main
# screen through its jimmy:// deep links, in light and dark, into docs/screenshots/.
#
# Usage: ./Tools/screenshots.sh [--skip-build]
set -euo pipefail

PROJECT="Jimmy.xcodeproj"
SCHEME="Jimmy"
BUNDLE_ID="com.chenkahana.Jimmy"
DERIVED_DATA="build/DerivedData"
OUT_DIR="docs/screenshots"
# Planet Money's podcast id — FeedIDs.generatePodcastID(from:) is a deterministic SHA-256-based
# UUID of the feed URL (Packages/JimmyKit/Sources/JimmyKit/Feed/FeedIDs.swift), reproduced here so
# the script never has to ask the running app for it.
PLANET_MONEY_FEED_URL="https://feeds.npr.org/510289/podcast.xml"
PLANET_MONEY_PODCAST_ID=$(python3 -I -c "
import hashlib, sys
h = hashlib.sha256(sys.argv[1].encode('utf-8')).digest()[:16]
print('-'.join([h[:4].hex(), h[4:6].hex(), h[6:8].hex(), h[8:10].hex(), h[10:16].hex()]).upper())
" "$PLANET_MONEY_FEED_URL")

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

SKIP_BUILD=false
for arg in "$@"; do
    case "$arg" in
        --skip-build) SKIP_BUILD=true ;;
    esac
done

# --- 1. Pick a simulator: override with SIM="..."; otherwise the first iOS 27 simulator whose
#        device type is an iPhone (a plain iPhone, or an iPhone Duo — every iOS 27.1 simulator in
#        this environment is one of those, under whatever name a lane gave it). ---
pick_simulator() {
    python3 -I -c '
import json
import subprocess
import sys

listing = subprocess.run(
    ["xcrun", "simctl", "list", "devices", "available", "--json"],
    capture_output=True, text=True, check=True,
).stdout
devices_by_runtime = json.loads(listing)["devices"]

for runtime, devices in devices_by_runtime.items():
    if "iOS-27" not in runtime:
        continue
    for device in devices:
        if "iphone" in device.get("deviceTypeIdentifier", "").lower():
            print(device["name"])
            sys.exit(0)
sys.exit(1)
'
}

SIM_NAME="${SIM:-}"
if [ -z "$SIM_NAME" ]; then
    SIM_NAME=$(pick_simulator) || {
        echo "ERROR: no iOS 27 iPhone-type simulator is installed, and no SIM=\"...\" override was given." >&2
        exit 1
    }
fi
echo "==> Using simulator: $SIM_NAME"

# --- 2. Build (unless skipped) and boot. ---
if [ "$SKIP_BUILD" = false ]; then
    echo "==> Generating $PROJECT..."
    make project

    echo "==> Building $SCHEME for $SIM_NAME..."
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
        -derivedDataPath "$DERIVED_DATA" -quiet \
        -destination "platform=iOS Simulator,name=$SIM_NAME" \
        CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
else
    echo "==> Skipping build (--skip-build), reusing $DERIVED_DATA"
fi

SIM_UDID=$(xcrun simctl list devices available 2>/dev/null | grep -F "$SIM_NAME (" | grep -oE '[0-9A-F-]{36}' | head -1)
if [ -z "$SIM_UDID" ]; then
    echo "ERROR: could not resolve a UDID for simulator '$SIM_NAME'." >&2
    exit 1
fi

if ! xcrun simctl list devices | grep -F "$SIM_UDID" | grep -q "Booted"; then
    echo "==> Booting $SIM_NAME..."
    xcrun simctl boot "$SIM_UDID"
    xcrun simctl bootstatus "$SIM_UDID" -b
fi

APP_PATH=$(find "$DERIVED_DATA/Build/Products/Debug-iphonesimulator" -name "Jimmy.app" -maxdepth 1 2>/dev/null | head -1)
if [ -z "$APP_PATH" ]; then
    echo "ERROR: could not find Jimmy.app in $DERIVED_DATA. Did the build succeed?" >&2
    exit 1
fi

echo "==> Installing..."
xcrun simctl install "$SIM_UDID" "$APP_PATH"

# --- 3. A clean, reproducible status bar (9:41, full battery and signal). ---
xcrun simctl status_bar "$SIM_UDID" override \
    --time "9:41" \
    --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode active --cellularBars 4 \
    --batteryState charged --batteryLevel 100

# --- 4. Launch with -demoLibrary, routed in-process to one screen per launch. ---
#
# `xcrun simctl openurl` right after a launch can trigger iOS's one-time "Open in 'Jimmy'?"
# confirmation (a SpringBoard sheet, not the app's own UI) — observed intermittently even on a
# freshly erased simulator, not just after a relaunch. Once shown, it stays up over everything
# until a human taps it, which a script run from the command line has no way to do. So navigation
# here never uses `openurl`: each screen is instead requested as a `JIMMY_SCREENSHOT_ROUTE`
# environment variable (passed via simctl's documented `SIMCTL_CHILD_` prefix) that
# `DemoLibrary.navigateToScreenshotRouteIfRequested()` reads at launch and acts on entirely
# in-process, through the same `DeepLinkRouter` a real deep link uses — never through
# `UIApplication.open(_:)`, so the confirmation can't be triggered at all.
#
# `JIMMY_DEMO_DB_ID` keeps every one of this run's relaunches on the same demo database, so
# `DemoLibrary.seed(into:)` only subscribes to the demo feeds over the network on the first of
# them; every later launch just navigates.
DEMO_DB_ID=$(uuidgen)
SEED_WAIT_SECONDS=25
NAV_WAIT_SECONDS=4
FIRST_LAUNCH=true

launch_and_navigate() {
    local route="$1"
    SIMCTL_CHILD_JIMMY_DEMO_DB_ID="$DEMO_DB_ID" \
        SIMCTL_CHILD_JIMMY_SCREENSHOT_ROUTE="$route" \
        xcrun simctl launch --terminate-running-process "$SIM_UDID" "$BUNDLE_ID" -demoLibrary

    if [ "$FIRST_LAUNCH" = true ]; then
        echo "==> Waiting ${SEED_WAIT_SECONDS}s for the demo library to seed..."
        sleep "$SEED_WAIT_SECONDS"
        FIRST_LAUNCH=false
    else
        sleep "$NAV_WAIT_SECONDS"
    fi

    # Discover's charts load over the network, separately from the demo library's own seeding;
    # give it longer than an already-seeded, local screen needs.
    if [ "$route" = "jimmy://discover" ]; then
        sleep 5
    fi
}

mkdir -p "$OUT_DIR"

# screen-name:deep-link-url
SCREENS=(
    "queue:jimmy://queue"
    "library:jimmy://library"
    "discover:jimmy://discover"
    "settings:jimmy://settings"
    "podcast:jimmy://podcast/$PLANET_MONEY_PODCAST_ID"
    "nowplaying:jimmy://nowplaying"
)

capture() {
    local name="$1" appearance="$2"
    local path="$OUT_DIR/${name}-${appearance}.png"
    local err_file
    err_file=$(mktemp)

    if ! xcrun simctl io "$SIM_UDID" screenshot "$path" 2>"$err_file"; then
        # A foldable device (e.g. Folio Duo, or any "Jimmy Lane N" built on the same iPhone Duo
        # device type) has more than one display and refuses to pick one on its own; its
        # single-pane "phone" view is display 1 — see `xcrun simctl io <udid> enumerate`.
        if grep -q "Cannot choose between" "$err_file"; then
            xcrun simctl io "$SIM_UDID" screenshot --display=1 "$path"
        else
            cat "$err_file" >&2
            rm -f "$err_file"
            return 1
        fi
    fi
    rm -f "$err_file"
    echo "    saved $path"
}

for mode in light dark; do
    echo "==> Switching to $mode mode..."
    xcrun simctl ui "$SIM_UDID" appearance "$mode"
    sleep 1

    for entry in "${SCREENS[@]}"; do
        name="${entry%%:*}"
        url="${entry#*:}"
        echo "==> $name ($mode)"
        launch_and_navigate "$url"
        capture "$name" "$mode"
    done
done

xcrun simctl status_bar "$SIM_UDID" clear
xcrun simctl terminate "$SIM_UDID" "$BUNDLE_ID" 2>/dev/null || true

echo "==> Done. Screenshots are in $OUT_DIR/"
