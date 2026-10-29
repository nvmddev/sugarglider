#!/bin/bash
# Version helper driven by git tags and Conventional Commits.
#
#   scripts/version.sh latest             newest release tag ("v1.2.0"), empty if none
#   scripts/version.sh previous <tag>     the tag released before <tag>, empty if none
#   scripts/version.sh next [auto|patch|minor|major]
#                                         next version, without the "v"
#   scripts/version.sh app-changed [tag]  exit 0 if the app would differ from <tag>
#                                         (default: the newest), else 1
#
# auto bumps major for a "!" or a BREAKING CHANGE trailer, minor for any feat,
# patch otherwise.
set -euo pipefail
cd "$(dirname "$0")/.."

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

all_tags() {
    # Plain releases only: the two-dot glob alone still matches v1.2.3-beta.1, and a
    # prerelease as `latest` would fail every `next` call until the tag is deleted.
    git tag --list 'v[0-9]*.[0-9]*.[0-9]*' --sort=-v:refname | grep -v -- '-' || true
}

# No `| head -n1`: under pipefail, git dying of SIGPIPE would fail the script.
latest_tag() {
    local tags
    tags="$(all_tags)"
    printf '%s' "${tags%%$'\n'*}"
}

# The nearest tag reachable from <exclude>'s parent, so a higher version tagged
# on a side branch doesn't win. On the workflow_dispatch path <exclude> isn't a
# commit yet, hence the fallback to the newest other tag.
previous_tag() {
    local exclude="$1" tag prev
    # Prereleases are excluded here, not matched and rejected: the fallback below
    # takes the newest plain tag anywhere, which a side-branch tag would win.
    if prev="$(git describe --tags --abbrev=0 --match 'v[0-9]*.[0-9]*.[0-9]*' --exclude '*-*' "${exclude}^" 2>/dev/null)"; then
        printf '%s' "${prev}"
        return 0
    fi
    while IFS= read -r tag; do
        [[ -z "${tag}" || "${tag}" == "${exclude}" ]] && continue
        printf '%s' "${tag}"
        return 0
    done <<< "$(all_tags)"
}

detect_bump() {
    local range="$1" bump="patch" record subject body type bang
    # Written through a file: `set -e` doesn't see a failing git log inside a process
    # substitution, and a silent empty log would pass for "no changes".
    git log --no-merges --format='%s%x1f%b%x1e' "${range}" > "${WORK}/records"
    while IFS= read -r -d $'\x1e' record; do
        record="${record#$'\n'}"
        subject="${record%%$'\x1f'*}"
        body="${record#*$'\x1f'}"
        # The exact shape changelog.sh parses: types are not case-sensitive, the ! sits
        # right before the colon, and a description must follow. The nested scope group
        # matters: bash drops unmatched trailing groups from BASH_REMATCH, and without
        # it the bang slot would hold the description for a scope-less subject.
        if [[ "${subject}" =~ ^([a-zA-Z]+)(\(([^\)]+)\))?(!)?:[[:space:]]*(.+)$ ]]; then
            type="$(printf '%s' "${BASH_REMATCH[1]}" | tr '[:upper:]' '[:lower:]')"
            bang="${BASH_REMATCH[4]}"
        else
            type="other"
            bang=""
        fi
        # The footer tokens, at line starts only: prose that merely mentions the phrase
        # must not break. BREAKING-CHANGE is the spec's synonym.
        if [[ -n "${bang}" ]] || grep -qE '^BREAKING CHANGE: |^BREAKING-CHANGE: ' <<<"${body}"; then
            printf 'major'
            return 0
        fi
        [[ "${type}" == "feat" ]] && bump="minor"
    done < "${WORK}/records"
    printf '%s' "${bump}"
}

# Everything the shipped bundle is built from.
APP_PATHS=(Sources Resources Sugarglider.xcodeproj)

case "${1:-}" in
app-changed)
    tag="${2:-$(latest_tag)}"
    if [[ -z "${tag}" ]]; then
        echo "changed (no release tag yet)"
        exit 0
    fi
    # Without this, a mistyped tag answers "changed" and exits 0: git diff's 128
    # would read as a difference.
    git rev-parse -q --verify "${tag}^{commit}" >/dev/null || {
        echo "error: '${tag}' is not a commit" >&2
        exit 1
    }
    if git diff --quiet "${tag}" HEAD -- "${APP_PATHS[@]}"; then
        echo "unchanged since ${tag}"
        exit 1
    fi
    echo "changed since ${tag}"
    exit 0
    ;;
latest)
    latest_tag
    echo
    ;;
previous)
    [[ -n "${2:-}" ]] || { echo "usage: version.sh previous <tag>" >&2; exit 2; }
    previous_tag "$2"
    echo
    ;;
next)
    bump="${2:-auto}"
    tag="$(latest_tag)"
    if [[ -z "${tag}" ]]; then
        echo "0.1.0"
        exit 0
    fi

    current="${tag#v}"
    if [[ ! "${current}" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
        echo "error: newest tag '${tag}' is not a plain MAJOR.MINOR.PATCH version" >&2
        exit 1
    fi
    major="${BASH_REMATCH[1]}"
    minor="${BASH_REMATCH[2]}"
    patch="${BASH_REMATCH[3]}"

    [[ "${bump}" == "auto" ]] && bump="$(detect_bump "${tag}..HEAD")"

    case "${bump}" in
    major) major=$((major + 1)); minor=0; patch=0 ;;
    minor) minor=$((minor + 1)); patch=0 ;;
    patch) patch=$((patch + 1)) ;;
    *) echo "error: unknown bump '${bump}'" >&2; exit 2 ;;
    esac
    echo "${major}.${minor}.${patch}"
    ;;
*)
    echo "usage: version.sh {latest|previous <tag>|next [auto|patch|minor|major]|app-changed [tag]}" >&2
    exit 2
    ;;
esac
