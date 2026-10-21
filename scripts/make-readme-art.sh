#!/bin/bash
# Renders the README pictures into docs/ through the app's own views
# (scripts/ReadmeArt.swift). Run it after changing the menu bar label, the
# dropdown or the chart, and commit what it writes. Needs a full Xcode.
set -euo pipefail
cd "$(dirname "$0")/.."

# Only a full Xcode has xcodebuild, and the Command Line Tools can't build the
# app's SwiftUI macros.
if [[ -z "${DEVELOPER_DIR:-}" && ! -x "$(xcode-select -p 2>/dev/null)/usr/bin/xcodebuild" ]]; then
    for candidate in /Applications/Xcode*.app/Contents/Developer; do
        if [[ -d "${candidate}" ]]; then export DEVELOPER_DIR="${candidate}"; break; fi
    done
fi

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

# Only main.swift may hold top-level code, and SugargliderApp.swift owns @main.
cp scripts/ReadmeArt.swift "${WORK}/main.swift"
SOURCES=()
while IFS= read -r file; do SOURCES+=("${file}"); done \
    < <(find Sources/Sugarglider -name '*.swift' ! -name 'SugargliderApp.swift')

# The app target's settings in Package.swift; keep them in sync.
SWIFT_FLAGS=(
    -swift-version 6
    -target arm64-apple-macos26.0
    -default-isolation MainActor
    -enable-upcoming-feature ExistentialAny
    -enable-upcoming-feature MemberImportVisibility
    -enable-upcoming-feature NonisolatedNonsendingByDefault
    -enable-upcoming-feature InferIsolatedConformances
)

mkdir -p docs

echo "==> Compiling the renderer"
xcrun swiftc "${SWIFT_FLAGS[@]}" -O "${SOURCES[@]}" "${WORK}/main.swift" -o "${WORK}/readme-art"

echo "==> Rendering docs/"
"${WORK}/readme-art"
