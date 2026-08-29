#!/bin/bash
# Renders the README pictures into docs/ from scripts/ReadmeArt.swift. Run it
# after changing the menu bar label, the dropdown or the chart, and commit what
# it writes.
#
# Not part of the release path: it needs a full Xcode (SwiftUI's ImageRenderer
# is fine, but swiftc has to build the whole app target), and the output is
# committed, the same arrangement as scripts/make-icon.sh.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -z "${DEVELOPER_DIR:-}" && ! -x "$(xcode-select -p 2>/dev/null)/usr/bin/swiftc" ]]; then
    for candidate in /Applications/Xcode*.app/Contents/Developer; do
        if [[ -d "${candidate}" ]]; then export DEVELOPER_DIR="${candidate}"; break; fi
    done
fi

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

# Only main.swift may carry top-level code, and SugargliderApp.swift owns @main.
cp scripts/ReadmeArt.swift "${WORK}/main.swift"
SOURCES=()
while IFS= read -r file; do SOURCES+=("${file}"); done \
    < <(find Sources/Sugarglider -name '*.swift' ! -name 'SugargliderApp.swift')

mkdir -p docs

echo "==> Compiling the renderer"
xcrun swiftc -swift-version 6 -O "${SOURCES[@]}" "${WORK}/main.swift" -o "${WORK}/readme-art"

echo "==> Rendering docs/"
"${WORK}/readme-art"
