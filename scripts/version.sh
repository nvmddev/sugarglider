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

all_tags() {
    git tag --list 'v[0-9]*' --sort=-v:refname
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
    if prev="$(git describe --tags --abbrev=0 --match 'v[0-9]*' "${exclude}^" 2>/dev/null)"; then
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
    local range="$1" bump="patch" record subject body
    while IFS= read -r -d $'\x1e' record; do
        record="${record#$'\n'}"
        subject="${record%%$'\x1f'*}"
        body="${record#*$'\x1f'}"
        if [[ "${subject}" =~ ^[a-zA-Z]+(\([^\)]*\))?! ]] || [[ "${body}" == *"BREAKING CHANGE"* ]]; then
            printf 'major'
            return 0
        fi
        [[ "${subject}" =~ ^feat(\([^\)]*\))?: ]] && bump="minor"
    done < <(git log --no-merges --format='%s%x1f%b%x1e' "${range}")
    printf '%s' "${bump}"
}

# Everything the shipped bundle is built from.
APP_PATHS=(Sources Resources Package.swift)

case "${1:-}" in
app-changed)
    tag="${2:-$(latest_tag)}"
    if [[ -z "${tag}" ]]; then
        echo "changed (no release tag yet)"
        exit 0
    fi
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
