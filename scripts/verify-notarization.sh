#!/bin/bash
# Asserts that a release's artifacts are notarized and stapled, before anything
# is published.
#
#   scripts/verify-notarization.sh <zip> <dmg>
#
# Run it on the notarizing path only. Signing degrades silently (no certificate
# means ad-hoc, no Apple ID means unnotarized), so a green release run proves
# nothing about Gatekeeper by itself.
#
# The zip is unpacked instead of trusting the app in the working tree: it is what
# Homebrew installs, and it is rebuilt after stapling, which is easy to get wrong.
set -euo pipefail
cd "$(dirname "$0")/.."

ZIP="${1:-}"
DMG="${2:-}"
[[ -f "${ZIP}" && -f "${DMG}" ]] || { echo "usage: verify-notarization.sh <zip> <dmg>" >&2; exit 2; }

APP="Sugarglider.app"
STAGING="$(mktemp -d)"
trap 'rm -rf "${STAGING}"' EXIT

fail() { echo "::error::$*"; exit 1; }

echo "==> Verifying ${APP}"
xcrun stapler validate "${APP}" || fail "${APP} carries no stapled notarization ticket."

# spctl speaks for Gatekeeper itself, and its source= line tells notarized apart
# from merely Developer ID-signed.
assessment="$(spctl -a -vvv -t exec "${APP}" 2>&1)" || fail "Gatekeeper rejected ${APP}: ${assessment}"
grep -q "source=Notarized Developer ID" <<<"${assessment}" \
    || fail "Gatekeeper accepted ${APP}, but not as notarized: ${assessment}"
printf '%s\n' "${assessment}"

echo "==> Verifying $(basename "${ZIP}")"
ditto -x -k "${ZIP}" "${STAGING}"
[[ -d "${STAGING}/${APP}" ]] || fail "${ZIP} does not contain ${APP}."
xcrun stapler validate "${STAGING}/${APP}" \
    || fail "The app inside ${ZIP} has no ticket. It was zipped before stapling."

echo "==> Verifying $(basename "${DMG}")"
xcrun stapler validate "${DMG}" || fail "${DMG} carries no stapled notarization ticket."
codesign --verify --strict "${DMG}" || fail "${DMG} is not validly signed."

echo "All artifacts are signed, notarized and stapled."
