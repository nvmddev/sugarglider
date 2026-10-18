#!/bin/bash
# Wraps Sugarglider.app in a drag-to-Applications disk image.
#
#   VERSION        names the image and its volume. Default: the app's
#                  CFBundleShortVersionString.
#   SIGN_IDENTITY  codesign identity for the image ("-" = skip). A DMG carrying
#                  a Developer ID app needs its own signature, or Gatekeeper
#                  evaluates the container as unsigned.
#
# No Finder window styling: scripting Finder over Apple Events is unreliable on
# a headless CI runner, and a plain UDZO image installs the same.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="Sugarglider.app"
[[ -d "${APP}" ]] || { echo "error: ${APP} not found — run ./build.sh first" >&2; exit 1; }

VERSION="${VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${APP}/Contents/Info.plist")}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
OUT="dist/Sugarglider-${VERSION}.dmg"

STAGING="$(mktemp -d)"
trap 'rm -rf "${STAGING}"' EXIT

echo "==> Staging disk image contents"
# ditto, not cp -R: it preserves the code signature and extended attributes.
ditto "${APP}" "${STAGING}/${APP}"
ln -s /Applications "${STAGING}/Applications"

mkdir -p dist
rm -f "${OUT}"

echo "==> Creating ${OUT}"
hdiutil create \
    -volname "Sugarglider ${VERSION}" \
    -srcfolder "${STAGING}" \
    -fs HFS+ \
    -format UDZO \
    -ov \
    -quiet \
    "${OUT}"

if [[ "${SIGN_IDENTITY}" != "-" ]]; then
    echo "==> Signing ${OUT}"
    codesign --force --timestamp --sign "${SIGN_IDENTITY}" "${OUT}"
fi

echo "Built ${OUT}"
