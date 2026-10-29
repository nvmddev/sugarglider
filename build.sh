#!/bin/bash
# Archives Sugarglider with Xcode and copies the signed .app here.
#
# Optional environment:
#   VERSION            CFBundleShortVersionString. Default: newest tag without
#                      its "v", or 0.0.0-dev outside a tagged checkout.
#   BUILD_NUMBER       CFBundleVersion. Default: the commit count, which only
#                      grows, as macOS expects across updates.
#   SIGN_IDENTITY      Signing identity. Default "-", ad-hoc. A Developer ID
#                      also gets a secure timestamp, which notarization needs.
#   TEAM_ID            Adds the keychain-access-groups entitlement when a
#                      provisioning profile is present, see docs/signing.md.
#   PROVISION_PROFILE  That profile. Default: Resources/embedded.provisionprofile.
set -euo pipefail
cd "$(dirname "$0")"

APP="Sugarglider.app"
ARCHIVE=".build/Sugarglider.xcarchive"

VERSION="${VERSION:-$(git describe --tags --abbrev=0 --match 'v[0-9]*.[0-9]*.[0-9]*' 2>/dev/null | grep -v -- '-' | sed 's/^v//' || true)}"
VERSION="${VERSION:-0.0.0-dev}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

SETTINGS=(MARKETING_VERSION="${VERSION}" CURRENT_PROJECT_VERSION="${BUILD_NUMBER}")
if [[ "${SIGN_IDENTITY}" == "-" ]]; then
    echo "==> Signing ad-hoc"
else
    SETTINGS+=(CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="${SIGN_IDENTITY}" OTHER_CODE_SIGN_FLAGS=--timestamp)
    [[ -z "${TEAM_ID:-}" ]] || SETTINGS+=(DEVELOPMENT_TEAM="${TEAM_ID}")

    # keychain-access-groups is a restricted entitlement: without a profile
    # granting it, AMFI kills the app at launch.
    PROFILE="${PROVISION_PROFILE:-Resources/embedded.provisionprofile}"
    if [[ -n "${TEAM_ID:-}" && -f "${PROFILE}" ]]; then
        # xcodebuild only finds installed profiles, in the folder that opening
        # one in Finder puts it in.
        UUID="$(security cms -D -i "${PROFILE}" | plutil -extract UUID raw -o - -)"
        # A profile without keychain-access-groups yields an app that signs cleanly and
        # is then killed at launch by AMFI, so check before using it.
        security cms -D -i "${PROFILE}" \
            | plutil -extract Entitlements.keychain-access-groups xml1 -o - - > /dev/null || {
            echo "error: ${PROFILE} grants no keychain-access-groups" >&2
            exit 1
        }
        PROFILES="${HOME}/Library/Developer/Xcode/UserData/Provisioning Profiles"
        mkdir -p "${PROFILES}"
        cp "${PROFILE}" "${PROFILES}/${UUID}.provisionprofile"
        SETTINGS+=(PROVISIONING_PROFILE_SPECIFIER="${UUID}"
            CODE_SIGN_ENTITLEMENTS=Resources/Sugarglider.entitlements)
        echo "==> Signing with ${SIGN_IDENTITY} and profile ${UUID}"
    else
        echo "==> Signing with ${SIGN_IDENTITY}; no profile or TEAM_ID, so the token falls back to the login Keychain"
    fi
fi

echo "==> Archiving ${VERSION} (build ${BUILD_NUMBER})"
rm -rf "${ARCHIVE}"
xcodebuild archive -quiet \
    -project Sugarglider.xcodeproj -scheme Sugarglider -configuration Release \
    -destination "generic/platform=macOS" \
    -derivedDataPath .build/xcode -archivePath "${ARCHIVE}" \
    "${SETTINGS[@]}"

# Copied to a partial path and renamed: an interrupt or a crash mid-copy would
# otherwise leave a truncated app in place of the working one.
rm -rf "${APP}" "${APP}.partial"
ditto "${ARCHIVE}/Products/Applications/${APP}" "${APP}.partial"
mv "${APP}.partial" "${APP}"
codesign --verify --strict --verbose=2 "${APP}"

echo "Built ${APP} (${VERSION}, build ${BUILD_NUMBER})"
echo "  Run it:     open ${APP}"
echo "  Install:    cp -r ${APP} /Applications/"
