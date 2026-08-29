#!/bin/bash
# Build Sugarglider and assemble a menu-bar .app bundle.
#
# All of these are optional; a bare `./build.sh` does the right thing locally.
#
#   VERSION        CFBundleShortVersionString. Default: newest git tag without
#                  its leading "v", or 0.0.0-dev outside a tagged checkout.
#   BUILD_NUMBER   CFBundleVersion. Default: commit count on HEAD, which grows
#                  monotonically, as macOS compares this across updates.
#   SIGN_IDENTITY  codesign identity. Default "-" = ad-hoc. A real Developer ID
#                  also enables hardened runtime and a secure timestamp, both of
#                  which notarization rejects the app without.
#   UNIVERSAL      1 = arm64 + x86_64 fat binary (what releases ship), 0 = host
#                  arch only, for fast local iteration. Default 0.
#   TEAM_ID        Apple Developer Team ID. With a provisioning profile it adds
#                  the keychain-access-groups entitlement, see the signing block
#                  below and docs/signing.md.
#   PROVISION_PROFILE  Path to that profile. Default
#                  Resources/embedded.provisionprofile (gitignored, optional).
set -euo pipefail
cd "$(dirname "$0")"

APP="Sugarglider.app"
BIN="Sugarglider"
BUNDLE_ID="dev.nevermind.sugarglider"

VERSION="${VERSION:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)}"
VERSION="${VERSION:-0.0.0-dev}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
UNIVERSAL="${UNIVERSAL:-0}"

if [[ "${UNIVERSAL}" == "1" ]]; then
    # Two per-arch builds merged with lipo, not `swift build --arch a --arch b`:
    # that form routes through xcbuild and needs a full Xcode, while --triple
    # works on a Command Line Tools-only machine too.
    ARCHS=(arm64 x86_64)
    SLICES=()
    for arch in "${ARCHS[@]}"; do
        echo "==> Compiling ${arch} (release, ${VERSION} build ${BUILD_NUMBER})"
        swift build -c release --triple "${arch}-apple-macosx14.0"
        SLICES+=("$(swift build -c release --triple "${arch}-apple-macosx14.0" --show-bin-path)/${BIN}")
    done
    BIN_PATH=".build/${BIN}-universal"
    echo "==> Merging slices into a universal binary"
    lipo -create -output "${BIN_PATH}" "${SLICES[@]}"
else
    echo "==> Compiling (release, ${VERSION} build ${BUILD_NUMBER})"
    swift build -c release
    BIN_PATH="$(swift build -c release --show-bin-path)/${BIN}"
fi

echo "==> Assembling ${APP}"
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
cp "${BIN_PATH}" "${APP}/Contents/MacOS/${BIN}"
# Three icon artifacts, three consumers, see scripts/make-icon.sh: Assets.car
# holds the appearance-aware stack macOS renders the app icon from, AppIcon.icns
# is the single-appearance fallback, and the two PNGs are there because the
# catalog's variants are reachable only through the system icon services, so the
# About tab has to pick its artwork by hand.
cp "Resources/Assets.car" "Resources/AppIcon.icns" \
    "Resources/AppIcon-Light.png" "Resources/AppIcon-Dark.png" \
    "${APP}/Contents/Resources/"

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
    <string>14.0</string>
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
    # keychain-access-groups moves the token to the data-protection Keychain,
    # which never prompts. It is a restricted entitlement, so AMFI kills the app
    # at launch unless an embedded profile grants it. See docs/signing.md.
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
echo "  Login item: System Settings > General > Login Items > +"
