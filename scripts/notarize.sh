#!/bin/bash
# Submits a file to Apple's notary service and waits for the verdict.
#
#   scripts/notarize.sh <file> [--staple]
#
# Needs APPLE_ID, APPLE_TEAM_ID and APPLE_APP_PASSWORD (an app-specific password,
# not the account password). A .dmg can be stapled, a .zip can't: callers staple
# the app inside it and zip it again.
set -euo pipefail

FILE="${1:-}"
STAPLE="${2:-}"
[[ -n "${FILE}" && -e "${FILE}" ]] || { echo "usage: notarize.sh <file> [--staple]" >&2; exit 2; }

: "${APPLE_ID:?APPLE_ID is required}"
: "${APPLE_TEAM_ID:?APPLE_TEAM_ID is required}"
: "${APPLE_APP_PASSWORD:?APPLE_APP_PASSWORD is required}"

echo "==> Notarizing ${FILE}"
# Captured, not streamed: on failure the submission id is needed to fetch the log.
if output="$(xcrun notarytool submit "${FILE}" \
    --apple-id "${APPLE_ID}" \
    --team-id "${APPLE_TEAM_ID}" \
    --password "${APPLE_APP_PASSWORD}" \
    --wait \
    --timeout 30m 2>&1)"; then
    printf '%s\n' "${output}"
else
    printf '%s\n' "${output}" >&2
    submission="$(printf '%s\n' "${output}" | awk '/^ *id: /{print $2; exit}')"
    if [[ -n "${submission}" ]]; then
        echo "==> Notarization failed; fetching log for ${submission}" >&2
        xcrun notarytool log "${submission}" \
            --apple-id "${APPLE_ID}" \
            --team-id "${APPLE_TEAM_ID}" \
            --password "${APPLE_APP_PASSWORD}" >&2 || true
    fi
    exit 1
fi

if [[ "${STAPLE}" == "--staple" ]]; then
    echo "==> Stapling ${FILE}"
    xcrun stapler staple "${FILE}"
    xcrun stapler validate "${FILE}"
fi
