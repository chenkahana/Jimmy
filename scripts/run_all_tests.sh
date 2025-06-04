#!/usr/bin/env bash
set -euo pipefail

# Run the Swift Package Manager tests
swift test --enable-code-coverage
