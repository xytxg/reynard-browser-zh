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

"${SWIFTC[@]}" \
    "$ROOT_DIR/browser/Reynard/Client/Interface/Addons/AddonPackageSafety.swift" \
    "$ROOT_DIR/Tests/AddonPackageSafetyTests.swift" \
    -o "$TEST_DIR/AddonPackageSafetyTests"

"$TEST_DIR/AddonPackageSafetyTests"

"$TEST_DIR/BrowserUpdatePolicyTests"

# ZIP limits on top of ZIPFoundation (reynard-browser-zh). SwiftPM resolves the
# same exact ZIPFoundation version as the Xcode project, which also verifies
# that CI can fetch it.
if command -v xcrun >/dev/null 2>&1; then
    SWIFT=(xcrun swift)
else
    SWIFT=(swift)
fi
ZIP_TEST_DIR="$TEST_DIR/BoundedZipArchiveTests"
mkdir -p "$ZIP_TEST_DIR/Sources/BoundedZipArchiveTests"
cp "$ROOT_DIR/Tests/BoundedZipArchiveTests/Package.swift" "$ZIP_TEST_DIR/Package.swift"
cp "$ROOT_DIR/browser/Reynard/Client/Utilities/BoundedZipArchive.swift" \
    "$ROOT_DIR/Tests/BoundedZipArchiveTests/main.swift" \
    "$ZIP_TEST_DIR/Sources/BoundedZipArchiveTests/"
python3 "$ROOT_DIR/Tests/BoundedZipArchiveTests/make_fixtures.py" "$ZIP_TEST_DIR/fixtures"
"${SWIFT[@]}" build --package-path "$ZIP_TEST_DIR" --configuration debug
"$ZIP_TEST_DIR/.build/debug/BoundedZipArchiveTests" "$ZIP_TEST_DIR/fixtures"
