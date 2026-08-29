#!/bin/bash
# Assert that a release's artifacts really are notarized and carry a stapled
# ticket, before anything is published.
#
#   scripts/verify-notarization.sh <zip> <dmg>
#
# Signing degrades on purpose (no certificate -> ad-hoc, no Apple ID -> signed
# but unnotarized), so every green release run proves nothing about Gatekeeper
# on its own. This is the step that does: run it only on the notarizing path.
#
# The zip is checked by unpacking it rather than by trusting the app in the
# working tree: it is what Homebrew installs, and it is rebuilt after the staple,
# so a wrong order there is exactly the mistake worth catching.
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

# spctl is the only check that speaks for Gatekeeper itself; the wording is
# stable and distinguishes notarized from merely Developer ID-signed.
assessment="$(spctl -a -vvv -t exec "${APP}" 2>&1)" || fail "Gatekeeper rejected ${APP}: ${assessment}"
grep -q "source=Notarized Developer ID" <<<"${assessment}" \
    || fail "Gatekeeper accepted ${APP}, but not as notarized: ${assessment}"
printf '%s\n' "${assessment}"

echo "==> Verifying $(basename "${ZIP}")"
ditto -x -k "${ZIP}" "${STAGING}"
[[ -d "${STAGING}/${APP}" ]] || fail "${ZIP} does not contain ${APP}."
xcrun stapler validate "${STAGING}/${APP}" \
    || fail "The app inside ${ZIP} has no ticket — it was zipped before stapling."

echo "==> Verifying $(basename "${DMG}")"
xcrun stapler validate "${DMG}" || fail "${DMG} carries no stapled notarization ticket."
codesign --verify --strict "${DMG}" || fail "${DMG} is not validly signed."

echo "All artifacts are signed, notarized and stapled."
