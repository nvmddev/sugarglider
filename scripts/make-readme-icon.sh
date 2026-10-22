#!/bin/bash
# Renders the README's pictures of the app icon, docs/icon-{light,dark}.png,
# from Resources/AppIcon.icon with Icon Composer's ictool. Run it after changing
# the artwork and commit what it writes; Xcode compiles the app's own icon.
set -euo pipefail
cd "$(dirname "$0")/.."

ICTOOL="Applications/Icon Composer.app/Contents/Executables/ictool"
DEVELOPER="${DEVELOPER_DIR:-$(xcode-select -p)}"
if [[ ! -x "${DEVELOPER}/../${ICTOOL}" ]]; then
    for candidate in /Applications/Xcode*.app/Contents/Developer; do
        if [[ -x "${candidate}/../${ICTOOL}" ]]; then DEVELOPER="${candidate}"; break; fi
    done
fi
[[ -x "${DEVELOPER}/../${ICTOOL}" ]] || {
    echo "error: ictool not found. It ships with Icon Composer in Xcode 26 or newer." >&2
    exit 1
}

for pair in Default:light Dark:dark; do
    output="docs/icon-${pair#*:}.png"
    "${DEVELOPER}/../${ICTOOL}" Resources/AppIcon.icon --export-image --output-file "${output}" \
        --platform macOS --rendition "${pair%:*}" --width 128 --height 128 --scale 2 >/dev/null
    echo "    ${output}"
done
