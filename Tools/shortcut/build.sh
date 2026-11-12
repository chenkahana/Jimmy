#!/bin/bash
# Tools/shortcut/build.sh — writes and signs the "Move Podcasts to Jimmy" shortcut that the
# Apple Podcasts import offers, into Jimmy/Resources/. Needs macOS with Shortcuts, signed in to iCloud.
set -euo pipefail
cd "$(dirname "$0")/../.."
NAME="Move Podcasts to Jimmy"
TMP=$(mktemp -d)
python3 -I Tools/shortcut/make_shortcut.py "$TMP/$NAME.unsigned.shortcut"
mkdir -p Jimmy/Resources
shortcuts sign --mode anyone --input "$TMP/$NAME.unsigned.shortcut" --output "Jimmy/Resources/$NAME.shortcut"
rm -rf "$TMP"
echo "Signed: Jimmy/Resources/$NAME.shortcut"
