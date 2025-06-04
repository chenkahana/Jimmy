#!/usr/bin/env bash
set -euo pipefail

# Remove user-specific Xcode workspace state files from version control
if git ls-files --error-unmatch 'Jimmy.xcodeproj/project.xcworkspace/xcuserdata/*/UserInterfaceState.xcuserstate' >/dev/null 2>&1; then
  git rm --cached 'Jimmy.xcodeproj/project.xcworkspace/xcuserdata/*/UserInterfaceState.xcuserstate'
fi

# Ensure ignore rules are present
if ! grep -qx 'xcuserdata/' .gitignore; then
  echo 'xcuserdata/' >> .gitignore
fi
if ! grep -qx '\*.xcuserstate' .gitignore; then
  echo '*.xcuserstate' >> .gitignore
fi

echo "Xcode user state files removed from git tracking and ignore rules applied."
