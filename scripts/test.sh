#!/bin/bash
# Runs the test suite and names the tests that failed.
#
#   scripts/test.sh [xcodebuild option ...]
#
# Extra options go to xcodebuild. For a single test:
#   scripts/test.sh '-only-testing:SugargliderTests/SugargliderTests/<name>()'
#
# CI and the release run the same command.
set -euo pipefail
cd "$(dirname "$0")/.."

RESULTS=".build/TestResults.xcresult"
# xcodebuild refuses to write over an existing result bundle.
rm -rf "${RESULTS}"

# -quiet hides which tests failed, so the result bundle names them.
if ! xcodebuild test -quiet \
    -project Sugarglider.xcodeproj -scheme Sugarglider \
    -destination platform=macOS,arch=arm64 \
    -derivedDataPath .build/xcode -resultBundlePath "${RESULTS}" "$@"; then
    if [[ -d "${RESULTS}" ]]; then
        echo "Failed tests:" >&2
        xcrun xcresulttool get test-results summary --path "${RESULTS}" \
            | jq -r '.testFailures[]? | "  \(.testIdentifierString // .testName): \(.failureText)"' >&2
    fi
    exit 1
fi
