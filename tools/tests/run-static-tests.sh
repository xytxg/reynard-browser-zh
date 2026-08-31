#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"

node "$SCRIPT_DIR/validate-localizations.js"
node "$SCRIPT_DIR/validate-project-safety.js"
python3 -m unittest discover -s "$ROOT_DIR/Tests" -p 'test_*.py' -v

if command -v xcrun >/dev/null 2>&1; then
    SWIFTC=(xcrun swiftc)
elif command -v swiftc >/dev/null 2>&1; then
    SWIFTC=(swiftc)
elif [[ "${REQUIRE_SWIFT:-0}" == "1" ]]; then
    echo "Swift compiler is required but was not found."
    exit 69
else
    echo "Swift compiler not found; skipping pure Swift tests."
    exit 0
fi

TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

"${SWIFTC[@]}" \
    "$ROOT_DIR/browser/Reynard/Client/Stores/DownloadSafety.swift" \
    "$ROOT_DIR/Tests/DownloadSafetyTests.swift" \
    -o "$TEST_DIR/DownloadSafetyTests"

"$TEST_DIR/DownloadSafetyTests"

"${SWIFTC[@]}" \
    "$ROOT_DIR/browser/Reynard/Client/Shared/URLUtils.swift" \
    "$ROOT_DIR/browser/Reynard/Client/Shared/IncomingBrowserURL.swift" \
    "$ROOT_DIR/Tests/IncomingBrowserURLTests.swift" \
    -o "$TEST_DIR/IncomingBrowserURLTests"

"$TEST_DIR/IncomingBrowserURLTests"

"${SWIFTC[@]}" \
    "$ROOT_DIR/browser/Reynard/Client/Startup/BrowserUpdatePolicy.swift" \
    "$ROOT_DIR/Tests/BrowserUpdatePolicyTests.swift" \
    -o "$TEST_DIR/BrowserUpdatePolicyTests"

"$TEST_DIR/BrowserUpdatePolicyTests"
