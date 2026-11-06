#!/bin/bash
# Imports the Developer ID certificate into a new keychain and prints the
# signing identity.
#
#   CERT_P12=<base64 .p12> CERT_PASSWORD=<password> [IDENTITY=<name>] \
#       scripts/import-signing-certificate.sh
#
# Without IDENTITY, it uses the first "Developer ID Application" identity in
# the certificate. For CI runners only: it replaces the user's keychain search
# list with the new keychain.
set -euo pipefail

[[ "${GITHUB_ACTIONS:-}" == "true" ]] || {
    echo "error: for CI runners only. It replaces your keychain search list." >&2
    exit 2
}
: "${CERT_P12:?CERT_P12 is required}"
: "${CERT_PASSWORD:?CERT_PASSWORD is required}"
: "${RUNNER_TEMP:?RUNNER_TEMP is required}"
IDENTITY="${IDENTITY:-}"

# Stdout carries only the identity. security writes progress there, so
# everything else goes to stderr.
exec 3>&1 1>&2

KEYCHAIN="${RUNNER_TEMP}/signing.keychain-db"
KEYCHAIN_PASSWORD="$(uuidgen)"
P12="${RUNNER_TEMP}/cert.p12"
trap 'rm -f "${P12}"' EXIT

security create-keychain -p "${KEYCHAIN_PASSWORD}" "${KEYCHAIN}"
security set-keychain-settings -lut 3600 "${KEYCHAIN}"
security unlock-keychain -p "${KEYCHAIN_PASSWORD}" "${KEYCHAIN}"

printf '%s' "${CERT_P12}" | base64 --decode > "${P12}"
security import "${P12}" -k "${KEYCHAIN}" -P "${CERT_PASSWORD}" \
    -T /usr/bin/codesign -T /usr/bin/security
rm -f "${P12}"
# Without this, codesign blocks on an interactive keychain prompt.
security set-key-partition-list -S apple-tool:,apple:,codesign: \
    -s -k "${KEYCHAIN_PASSWORD}" "${KEYCHAIN}" > /dev/null
# Only this keychain: nothing else in the job needs the login keychain,
# and naming it portably is fiddlier than it looks.
security list-keychain -d user -s "${KEYCHAIN}"

if [[ -z "${IDENTITY}" ]]; then
    IDENTITY="$(security find-identity -v -p codesigning "${KEYCHAIN}" \
        | awk -F'"' '/Developer ID Application/{print $2; exit}')"
fi
if [[ -z "${IDENTITY}" ]]; then
    echo "::error::Imported the certificate but found no 'Developer ID Application' identity in it."
    exit 1
fi

echo "${IDENTITY}" >&3
