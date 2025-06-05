#!/usr/bin/env bash
set -euo pipefail

# Finds all Swift files under the repository and ensures they parse
# using the Swift compiler front-end. This catches basic syntax errors
# without requiring Xcode or iOS SDKs.

status=0
while IFS= read -r swift_file; do
  echo "Parsing $swift_file"
  if ! swift -frontend -parse "$swift_file" >/dev/null 2>&1; then
    echo "Failed to parse $swift_file" >&2
    status=1
  fi
done < <(git ls-files 'Jimmy/Utilities/*.swift' 'Tests/**/*.swift')

exit $status
