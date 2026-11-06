#!/bin/bash
# Prints the Developer folder of the newest stable Xcode in a folder.
#
#   scripts/newest-xcode.sh [folder]    (default: /Applications)
#
# GitHub's macOS images install several Xcode versions side by side. CI selects
# one with: echo "DEVELOPER_DIR=$(scripts/newest-xcode.sh)" >> "$GITHUB_ENV"
#
# Stable means: a real folder named Xcode.app or Xcode_<version>.app whose license
# is not a beta license. A release candidate also has a GM license, so only its
# folder name tells it apart: the image installs it as
# Xcode_27.2_Release_Candidate.app and links Xcode_27.2.app to it. For this
# reason, the script skips symbolic links.
set -euo pipefail

FOLDER="${1:-/Applications}"
NAME_PATTERN='^Xcode(_[0-9]+(\.[0-9]+)*)?\.app$'

candidates=""
for app in "${FOLDER}"/Xcode.app "${FOLDER}"/Xcode_*.app; do
    [[ -d "${app}" && ! -L "${app}" ]] || continue
    [[ "$(basename "${app}")" =~ ${NAME_PATTERN} ]] || continue
    license="$(plutil -extract licenseType raw -o - "${app}/Contents/Resources/LicenseInfo.plist" 2>/dev/null || true)"
    [[ -n "${license}" && "$(tr '[:upper:]' '[:lower:]' <<<"${license}")" != *beta* ]] || continue
    version="$(plutil -extract CFBundleShortVersionString raw -o - "${app}/Contents/Info.plist")"
    candidates+="${version}"$'\t'"${app}"$'\n'
done

newest="$(printf '%s' "${candidates}" | sort -t $'\t' -k 1,1V | tail -n 1)"
[[ -n "${newest}" ]] || { echo "error: no stable Xcode in ${FOLDER}" >&2; exit 1; }

echo "Xcode ${newest%%$'\t'*} at ${newest#*$'\t'}" >&2
echo "${newest#*$'\t'}/Contents/Developer"
