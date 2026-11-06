#!/bin/bash
# Fails when a string in the app has no German translation.
#
# A plain xcodebuild build does not add new strings to the String Catalog; only Xcode's editor
# and a localization export do. So this script runs the export first. It writes new strings
# into the catalog, and the check then lists them. Run it locally after changing a string.
set -euo pipefail
cd "$(dirname "$0")/.."

CATALOG=Sources/Sugarglider/Localizable.xcstrings
LANGUAGE=de
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

xcodebuild -exportLocalizations -project Sugarglider.xcodeproj \
    -localizationPath "${WORK}" -exportLanguage "${LANGUAGE}" > "${WORK}/export.log" 2>&1 || {
    cat "${WORK}/export.log" >&2
    echo "error: the localization export failed" >&2
    exit 1
}

# A string is complete when every unit of its German entry, plural forms included, is translated.
untranslated="$(jq -r --arg language "${LANGUAGE}" '
    .strings | to_entries[]
    | select(.value.shouldTranslate != false and .value.extractionState != "stale")
    | select([.value.localizations[$language] | .. | objects | .stringUnit.state? // empty]
             | length == 0 or any(.[]; . != "translated"))
    | "  " + .key' "${CATALOG}")"
stale="$(jq -r '.strings | to_entries[] | select(.value.extractionState == "stale") | "  " + .key' "${CATALOG}")"

status=0
if [[ -n "${untranslated}" ]]; then
    echo "error: these strings have no German translation in ${CATALOG}:" >&2
    echo "${untranslated}" >&2
    status=1
fi
if [[ -n "${stale}" ]]; then
    echo "error: the app no longer uses these strings. Remove them from ${CATALOG}:" >&2
    echo "${stale}" >&2
    status=1
fi
if [[ "${status}" -eq 0 ]]; then
    echo "All strings have a German translation."
fi
exit "${status}"
