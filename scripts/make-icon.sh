#!/bin/bash
# Compiles Resources/AppIcon.icon (an Icon Composer document) into the icon
# artifacts committed next to it, plus the README's pictures of it:
#
#   Resources/Assets.car           the icon macOS shows, with Aqua, DarkAqua
#                                  and tintable renditions (CFBundleIconName)
#   Resources/AppIcon.icns         single-appearance fallback (CFBundleIconFile)
#   docs/icon-{light,dark}.png     the README header, one per color scheme
#
#   make-icon.sh [compile]   recompile and record the source hash (Xcode 26+)
#   make-icon.sh verify      check the recorded hash, no Xcode needed
#
# The artifacts are committed because actool ships only with a full Xcode, while
# build.sh has to work with the Command Line Tools alone. CI runs verify, which
# catches artwork edited without a recompile.
set -euo pipefail
cd "$(dirname "$0")/.."

ICON="Resources/AppIcon.icon"
CHECKSUM_FILE="Resources/AppIcon.icon.sha256"
MODE="${1:-compile}"

[[ -d "${ICON}" ]] || { echo "error: ${ICON} not found" >&2; exit 1; }

# Covers paths as well as contents. .DS_Store is skipped: Finder adds one as soon
# as the package is opened, and it's gitignored, so CI would hash differently.
icon_checksum() {
    find "${ICON}" -type f ! -name .DS_Store -print0 \
        | LC_ALL=C sort -z \
        | xargs -0 shasum -a 256 \
        | shasum -a 256 \
        | cut -d' ' -f1
}

case "${MODE}" in
compile) ;;
verify)
    [[ -f "${CHECKSUM_FILE}" ]] || {
        echo "error: ${CHECKSUM_FILE} is missing — run ./scripts/make-icon.sh" >&2
        exit 1
    }
    recorded="$(cat "${CHECKSUM_FILE}")"
    actual="$(icon_checksum)"
    [[ "${recorded}" == "${actual}" ]] || {
        echo "error: the committed icon artifacts are stale." >&2
        echo "       ${ICON} hashes to ${actual}," >&2
        echo "       but ${CHECKSUM_FILE} records ${recorded}." >&2
        echo "       Run ./scripts/make-icon.sh on a machine with Xcode 26+" >&2
        echo "       and commit what it regenerates." >&2
        exit 1
    }
    echo "Icon artifacts match ${ICON} (${actual})"
    exit 0
    ;;
*)
    echo "usage: $0 [compile|verify]" >&2
    exit 2
    ;;
esac

# xcrun finds actool only when a full Xcode is selected; an installed one is enough.
ACTOOL="$(xcrun --find actool 2>/dev/null || true)"
if [[ -z "${ACTOOL}" ]]; then
    for candidate in /Applications/Xcode*.app; do
        [[ -x "${candidate}/Contents/Developer/usr/bin/actool" ]] || continue
        ACTOOL="${candidate}/Contents/Developer/usr/bin/actool"
        export DEVELOPER_DIR="${candidate}/Contents/Developer"
        break
    done
fi
[[ -n "${ACTOOL}" ]] || {
    echo "error: actool not found. Compiling an Icon Composer document needs a" >&2
    echo "       full Xcode 26 or newer; the Command Line Tools don't ship it." >&2
    exit 1
}
MIN_MACOS="$(swift package describe --type json | plutil -extract platforms.0.version raw -o - -)"

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

compile_icon() {
    local document="$1" output="$2"
    # actool won't create the output directory, and it fails with "no such file"
    # on a relative .icon path, however valid.
    mkdir -p "${output}"
    [[ "${document}" == /* ]] || document="${PWD}/${document}"
    "${ACTOOL}" "${document}" \
        --compile "${output}" \
        --app-icon AppIcon \
        --platform macosx \
        --minimum-deployment-target "${MIN_MACOS}" \
        --output-partial-info-plist "${output}/partial.plist" \
        --errors --warnings >/dev/null
    [[ -f "${output}/Assets.car" && -f "${output}/AppIcon.icns" ]] \
        || { echo "error: actool produced no usable output for $1" >&2; exit 1; }
}

echo "==> Compiling ${ICON} with ${ACTOOL}"
compile_icon "${ICON}" "${TMP}/light"
cp "${TMP}/light/Assets.car" "${TMP}/light/AppIcon.icns" Resources/

# The PNGs come out of actool too: Icon Composer's export panel emits flat,
# full-bleed iOS artwork, since macOS adds the squircle, padding and shadow at
# render time. actool has no flag for the dark appearance, so the dark pass
# compiles a copy with its dark specializations promoted to defaults.
echo "==> Compiling a dark-appearance pass"
cp -R "${ICON}" "${TMP}/AppIcon.icon"
python3 - "${TMP}/AppIcon.icon/icon.json" <<'PY'
import json, sys

def promote(node):
    """Replace every fill-specializations list with its dark entry alone."""
    if isinstance(node, dict):
        for key, value in node.items():
            if key == "fill-specializations" and isinstance(value, list):
                dark = [s for s in value if isinstance(s, dict) and s.get("appearance") == "dark"]
                if dark:
                    promoted = dict(dark[0])
                    promoted.pop("appearance", None)
                    node[key] = [promoted]
            else:
                promote(value)
    elif isinstance(node, list):
        for value in node:
            promote(value)

path = sys.argv[1]
document = json.load(open(path))
promote(document)
json.dump(document, open(path, "w"), indent=2)
PY
compile_icon "${TMP}/AppIcon.icon" "${TMP}/dark"

# 128@2x (256 px) is the largest size actool puts in the fallback .icns.
for pass in light dark; do
    iconutil -c iconset "${TMP}/${pass}/AppIcon.icns" -o "${TMP}/${pass}.iconset"
    cp "${TMP}/${pass}.iconset/icon_128x128@2x.png" "docs/icon-${pass}.png"
done

# Last, so a run that dies halfway doesn't record the new source as compiled.
icon_checksum > "${CHECKSUM_FILE}"

for artifact in Resources/Assets.car Resources/AppIcon.icns docs/icon-light.png docs/icon-dark.png; do
    echo "    ${artifact} ($(du -h "${artifact}" | cut -f1))"
done
echo "    ${CHECKSUM_FILE} ($(cat "${CHECKSUM_FILE}"))"

echo
echo "Info.plist keys build.sh writes for these (kept in sync by hand):"
sed -n 's/^\t*//p' "${TMP}/light/partial.plist" | grep -A1 'CFBundleIcon' || true
