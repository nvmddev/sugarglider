#!/bin/bash
# Builds Sugarglider and assembles a signed menu-bar .app bundle.
#
# Optional environment:
#   VERSION            CFBundleShortVersionString. Default: newest tag without
#                      its "v", or 0.0.0-dev outside a tagged checkout.
#   BUILD_NUMBER       CFBundleVersion. Default: the commit count, which only
#                      grows, as macOS expects across updates.
#   SIGN_IDENTITY      codesign identity. Default "-", ad-hoc. A Developer ID
#                      also enables the hardened runtime and a secure timestamp,
#                      both required for notarization.
#   TEAM_ID            Adds the keychain-access-groups entitlement when a
#                      provisioning profile is present, see docs/signing.md.
#   PROVISION_PROFILE  That profile. Default: Resources/embedded.provisionprofile.
set -euo pipefail
cd "$(dirname "$0")"

APP="Sugarglider.app"
BIN="Sugarglider"
BUNDLE_ID="dev.nevermind.sugarglider"
MIN_MACOS="$(swift package describe --type json | plutil -extract platforms.0.version raw -o - -)"

VERSION="${VERSION:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)}"
VERSION="${VERSION:-0.0.0-dev}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
SDK_VERSION="$(xcrun --show-sdk-version)"

# The triple is explicit so an Intel host can't produce an x86_64 build. The
# linker flag records the real SDK version, which SwiftPM 6.4 replaces with the
# deployment target, and macOS gives an app its current design (Liquid Glass)
# only when the binary says it was linked against a current SDK.
SWIFT_BUILD=(swift build -c release --triple "arm64-apple-macosx${MIN_MACOS}"
    -Xlinker -platform_version -Xlinker macos -Xlinker "${MIN_MACOS}" -Xlinker "${SDK_VERSION}")

echo "==> Compiling (release, ${VERSION} build ${BUILD_NUMBER}, macOS SDK ${SDK_VERSION})"
"${SWIFT_BUILD[@]}"
BIN_PATH="$("${SWIFT_BUILD[@]}" --show-bin-path)/${BIN}"

RECORDED_SDK="$(vtool -show-build "${BIN_PATH}" | awk '$1 == "sdk" { print $2 }')"
if [[ "${RECORDED_SDK}" != "${SDK_VERSION}" ]]; then
    echo "error: ${BIN} records macOS SDK ${RECORDED_SDK:-none} instead of ${SDK_VERSION}" >&2
    exit 1
fi

echo "==> Assembling ${APP}"
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
cp "${BIN_PATH}" "${APP}/Contents/MacOS/${BIN}"
# Why there are two icon artifacts: see scripts/make-icon.sh.
cp "Resources/Assets.car" "Resources/AppIcon.icns" "${APP}/Contents/Resources/"

echo "==> Stripping symbols"
strip -x "${APP}/Contents/MacOS/${BIN}"

cat > "${APP}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${BIN}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon.icns</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>Sugarglider</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.healthcare-fitness</string>
    <key>LSMinimumSystemVersion</key>
    <string>${MIN_MACOS}</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>© 2026 nevermind.dev</string>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
</dict>
</plist>
PLIST

if [[ "${SIGN_IDENTITY}" == "-" ]]; then
    echo "==> Ad-hoc signing"
    codesign --force --sign - "${APP}" >/dev/null 2>&1 || echo "    (codesign skipped)"
else
    # keychain-access-groups is a restricted entitlement: without an embedded
    # profile granting it, AMFI kills the app at launch.
    SIGN_ARGS=(--force --options runtime --timestamp)
    PROFILE="${PROVISION_PROFILE:-Resources/embedded.provisionprofile}"
    if [[ -n "${TEAM_ID:-}" && -f "${PROFILE}" ]]; then
        cp "${PROFILE}" "${APP}/Contents/embedded.provisionprofile"
        ENTITLEMENTS=".build/Sugarglider.entitlements"
        cat > "${ENTITLEMENTS}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>keychain-access-groups</key>
    <array>
        <string>${TEAM_ID}.${BUNDLE_ID}</string>
    </array>
</dict>
</plist>
PLIST
        SIGN_ARGS+=(--entitlements "${ENTITLEMENTS}")
        echo "==> Embedding provisioning profile (keychain group ${TEAM_ID}.${BUNDLE_ID})"
    else
        echo "==> No profile or TEAM_ID, so the token falls back to the login Keychain"
    fi

    echo "==> Signing with ${SIGN_IDENTITY}"
    codesign "${SIGN_ARGS[@]}" --sign "${SIGN_IDENTITY}" "${APP}"
    codesign --verify --strict --verbose=2 "${APP}"
fi

echo "Built ${APP} (${VERSION}, build ${BUILD_NUMBER})"
echo "  Run it:     open ${APP}"
echo "  Install:    cp -r ${APP} /Applications/"
echo "  Login item: System Settings > General > Login Items & Extensions > Open at Login"
