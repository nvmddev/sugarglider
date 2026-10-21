#!/bin/bash
# Composes a GitHub release body: the generated changelog plus install notes.
#
#   scripts/release-notes.sh <version> [from-ref] [to-ref]
#
# NOTARIZED=true leaves out the Gatekeeper workaround.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-}"
FROM="${2:-}"
TO="${3:-HEAD}"
NOTARIZED="${NOTARIZED:-false}"

[[ -n "${VERSION}" ]] || { echo "usage: release-notes.sh <version> [from-ref] [to-ref]" >&2; exit 2; }

scripts/changelog.sh notes "${VERSION}" "${FROM}" "${TO}"

cat <<EOF

## Install

Download \`Sugarglider-${VERSION}.dmg\` (or the \`.zip\`) below, drag
**Sugarglider.app** into \`/Applications\`, and launch it. Needs a Mac with
Apple silicon and macOS 26 (Tahoe) or newer. Intel Macs are no longer supported.
EOF

if [[ "${NOTARIZED}" != "true" ]]; then
    cat <<'EOF'

> [!IMPORTANT]
> This build is **not notarized** by Apple, so macOS blocks it on first launch.
> Either allow it under **System Settings → Privacy & Security → Open Anyway**, or
> clear the quarantine flag yourself:
>
> ```sh
> xattr -dr com.apple.quarantine /Applications/Sugarglider.app
> ```
EOF
fi

cat <<'EOF'

Verify the download against `checksums.txt`:

```sh
shasum -a 256 -c checksums.txt
```

---

Sugarglider is **not a medical device**. It only displays data your Nightscout
site already holds, can show stale or incorrect values, and must not be used for
treatment decisions.
EOF
