#!/bin/bash
# Renders Conventional Commits as changelog markdown.
#
#   scripts/changelog.sh notes   <version> [from-ref] [to-ref]  markdown on stdout
#   scripts/changelog.sh prepend <version> [from-ref] [to-ref]  insert into CHANGELOG.md
#
# from-ref defaults to the tag released before v<version>, to-ref to HEAD.
set -euo pipefail
cd "$(dirname "$0")/.."

MODE="${1:-}"
VERSION="${2:-}"
FROM="${3:-}"
TO="${4:-HEAD}"

[[ -n "${MODE}" && -n "${VERSION}" ]] || {
    echo "usage: changelog.sh {notes|prepend} <version> [from-ref] [to-ref]" >&2
    exit 2
}

if [[ -z "${FROM}" ]]; then
    FROM="$(scripts/version.sh previous "v${VERSION}")"
fi

if [[ -n "${FROM}" ]]; then
    RANGE="${FROM}..${TO}"
else
    RANGE="${TO}" # first release: everything down to the root commit
fi

if [[ -n "${GITHUB_SERVER_URL:-}" && -n "${GITHUB_REPOSITORY:-}" ]]; then
    REPO_URL="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}"
else
    REPO_URL="$(git remote get-url origin 2>/dev/null || echo '')"
    REPO_URL="${REPO_URL%.git}"
    REPO_URL="$(printf '%s' "${REPO_URL}" | sed \
        -e 's|^git@github\.com:|https://github.com/|' \
        -e 's|^ssh://git@github\.com/|https://github.com/|')"
fi

DATE="$(git log -1 --format=%cd --date=short "${TO}" 2>/dev/null || date -u +%Y-%m-%d)"

SECTIONS=(breaking feat fix perf refactor docs build test chore other) # output order
title_for() {
    case "$1" in
    breaking) echo "⚠️ Breaking changes" ;;
    feat)     echo "Features" ;;
    fix)      echo "Bug fixes" ;;
    perf)     echo "Performance" ;;
    refactor) echo "Refactoring" ;;
    docs)     echo "Documentation" ;;
    build)    echo "Build & CI" ;;
    test)     echo "Tests" ;;
    chore)    echo "Chores" ;;
    *)        echo "Other changes" ;;
    esac
}

section_for() {
    case "$1" in
    feat)            echo feat ;;
    fix)             echo fix ;;
    perf)            echo perf ;;
    refactor)        echo refactor ;;
    docs)            echo docs ;;
    build|ci)        echo build ;;
    test)            echo test ;;
    chore|style)     echo chore ;;
    *)               echo other ;;
    esac
}

# One file of entries per section: macOS ships bash 3.2, which has no
# associative arrays.
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

# Written through a file, not a process substitution: `set -e` doesn't see a
# failing command inside `< <(...)`, and a silent empty log would pass for
# "no changes" while prepend replaces the changelog.
git log --no-merges --format='%H%x1f%s%x1f%b%x1e' "${RANGE}" > "${WORK}/records"

count=0
while IFS= read -r -d $'\x1e' record; do
    record="${record#$'\n'}"
    sha="${record%%$'\x1f'*}"
    rest="${record#*$'\x1f'}"
    subject="${rest%%$'\x1f'*}"
    body="${rest#*$'\x1f'}"
    [[ -n "${sha}" ]] || continue

    if [[ "${subject}" =~ ^([a-zA-Z]+)(\(([^\)]+)\))?(!)?:[[:space:]]*(.+)$ ]]; then
        type="$(printf '%s' "${BASH_REMATCH[1]}" | tr '[:upper:]' '[:lower:]')"
        scope="${BASH_REMATCH[3]}"
        bang="${BASH_REMATCH[4]}"
        desc="${BASH_REMATCH[5]}"
    else
        type="other"
        scope=""
        bang=""
        desc="${subject}"
    fi

    # The footer tokens, at line starts only: prose that merely mentions the
    # phrase must not break. BREAKING-CHANGE is the spec's synonym.
    if [[ -n "${bang}" ]] || grep -qE '^BREAKING CHANGE: |^BREAKING-CHANGE: ' <<<"${body}"; then
        section="breaking"
    else
        section="$(section_for "${type}")"
    fi

    entry="- "
    [[ -n "${scope}" ]] && entry+="**${scope}:** "
    entry+="${desc}"
    [[ -n "${REPO_URL}" ]] && entry+=" ([\`${sha:0:7}\`](${REPO_URL}/commit/${sha}))"

    printf '%s\n' "${entry}" >> "${WORK}/${section}"
    count=$((count + 1))
done < "${WORK}/records"

render() {
    local section
    if [[ -n "${REPO_URL}" ]]; then
        printf '## [%s](%s) (%s)\n' "${VERSION}" "${REPO_URL}/releases/tag/v${VERSION}" "${DATE}"
    else
        printf '## %s (%s)\n' "${VERSION}" "${DATE}"
    fi

    if [[ "${count}" -eq 0 ]]; then
        printf '\nNo code changes since %s.\n' "${FROM:-the initial commit}"
    else
        for section in "${SECTIONS[@]}"; do
            [[ -s "${WORK}/${section}" ]] || continue
            printf '\n### %s\n\n' "$(title_for "${section}")"
            cat "${WORK}/${section}"
        done
    fi

    if [[ -n "${FROM}" && -n "${REPO_URL}" ]]; then
        printf '\n**Full changelog**: %s/compare/%s...v%s\n' "${REPO_URL}" "${FROM}" "${VERSION}"
    fi
}

case "${MODE}" in
notes)
    render
    ;;
prepend)
    NEW="${WORK}/CHANGELOG.md"
    cat > "${NEW}" <<'HEADER'
# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). Entries are generated
from [Conventional Commits](https://www.conventionalcommits.org/) by
`scripts/changelog.sh`, so edit commit messages, not this file.

HEADER
    render >> "${NEW}"

    if [[ -f CHANGELOG.md ]]; then
        first_release="$(grep -n '^## ' CHANGELOG.md | head -n1 | cut -d: -f1 || true)"
        # Already at this version: the workflow re-runs prepend on a branch that may carry it,
        # and its diff guard relies on a second run changing nothing. The section line renders
        # with or without a link, depending on whether an origin remote is known.
        if [[ -n "${first_release}" ]] \
            && sed -n "${first_release}p" CHANGELOG.md | grep -qE "^## \[${VERSION}\]|^## ${VERSION} "; then
            echo "CHANGELOG.md already has ${VERSION}."
            exit 0
        fi
        if [[ -n "${first_release}" ]]; then
            printf '\n' >> "${NEW}"
            tail -n "+${first_release}" CHANGELOG.md >> "${NEW}"
        else
            # No section header: not a generated changelog. Keep its content rather
            # than replacing it with just the new release.
            printf '\n' >> "${NEW}"
            cat CHANGELOG.md >> "${NEW}"
        fi
    fi

    mv "${NEW}" CHANGELOG.md
    echo "Wrote CHANGELOG.md (${VERSION}, ${count} commits)"
    ;;
*)
    echo "usage: changelog.sh {notes|prepend} <version> [from-ref] [to-ref]" >&2
    exit 2
    ;;
esac
