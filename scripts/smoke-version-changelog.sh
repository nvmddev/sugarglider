#!/bin/bash
# Exercises scripts/version.sh and scripts/changelog.sh on a throwaway repository
# with crafted Conventional Commits subjects. A broken version or changelog script
# must fail here, not mid-release: the release workflow reads `previous` first and
# `prepend` writes the shipped CHANGELOG.md.
#
# Run it from the repository root; it copies the scripts, never edits them.
# Works on the release interpreter, macOS' bash 3.2, so keep it 3.2-clean.
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

expect() {
    local want="$1" got="$2" what="$3"
    if [[ "${got}" != "${want}" ]]; then
        echo "::error::smoke: ${what}: wanted '${want}', got '${got}'"
        exit 1
    fi
    echo "ok: ${what} -> ${got}"
}

expect_exit() {
    local want="$1" what="$2" status=0
    shift 2
    if "$@" >/dev/null 2>&1; then status=0; else status=$?; fi
    if [[ "${status}" -ne "${want}" ]]; then
        echo "::error::smoke: ${what}: wanted exit ${want}, got ${status} ($*)"
        exit 1
    fi
    echo "ok: ${what} -> exit ${status}"
}

expect_fail() {
    local what="$1" status=0
    shift
    if "$@" >/dev/null 2>&1; then
        echo "::error::smoke: ${what}: wanted a non-zero exit ($*)"
        exit 1
    else
        status=$?
    fi
    echo "ok: ${what} -> exit ${status}"
}

expect_not() {
    local pattern="$1" haystack="$2" what="$3"
    if grep -q "${pattern}" <<<"${haystack}"; then
        echo "::error::smoke: ${what}: unwanted match for '${pattern}'"
        exit 1
    fi
    echo "ok: ${what} -> no match"
}

echo "==> Building a crafted history in ${WORK}"
git init -q -b main "${WORK}/repo"
cd "${WORK}/repo"
git config user.email "smoke@example.com"
git config user.name "smoke"
# An origin makes changelog.sh render linked headers and commit links, the shape
# CI also produces through GITHUB_SERVER_URL and GITHUB_REPOSITORY.
git remote add origin "git@github.com:example/t8test.git"
mkdir -p Sources Resources Sugarglider.xcodeproj
touch Sources/App.swift
mkdir -p scripts
cp "${HERE}/scripts/version.sh" "${HERE}/scripts/changelog.sh" scripts/

commit() { # subject [body line ...]
    local subject="$1"; shift
    local -a args=(-m "${subject}")
    local body
    for body in "$@"; do args+=(-m "${body}"); done
    git commit -q --allow-empty "${args[@]}"
}

commit "feat: first feature"
commit "fix: a fix"
git tag v0.1.0
commit "docs: note that this is not a BREAKING CHANGE"
commit "feat(pump): pump data"
git tag v0.2.0-rc.1   # a prerelease between two releases: previous must skip it
commit "Feat: case insensitive feature"
commit "feat!stuff"
commit "feat:"
git tag v0.2.0
commit "fix!: break the api"
commit "fix: another fix" "BREAKING CHANGE: the protocol changed"
commit "chore: rebuild" "BREAKING-CHANGE: the payload changed"
git tag v1.0.0

expect "v1.0.0" "$(scripts/version.sh latest)" "latest"
expect "v0.2.0" "$(scripts/version.sh previous v1.0.0)" "previous v1.0.0"
expect "v0.1.0" "$(scripts/version.sh previous v0.2.0)" "previous v0.2.0"

# An experiment tag on a side branch must not drive the version: latest keeps
# the newest tag on this branch, and next auto reads its range from there.
git branch side main
git checkout -q side
commit "chore: experiment on a side branch"
git tag v9.9.9
git checkout -q main
expect "v1.0.0" "$(scripts/version.sh latest)" "latest ignores a side-branch tag"
expect "1.0.1" "$(scripts/version.sh next auto)" "next auto ignores a side-branch tag"
expect "1.0.1" "$(scripts/version.sh next patch)" "next patch"
expect "1.1.0" "$(scripts/version.sh next minor)" "next minor"
expect "2.0.0" "$(scripts/version.sh next major)" "next major"
expect "1.0.1" "$(scripts/version.sh next auto)" "next auto on an empty range"

commit "docs: mention an upcoming BREAKING CHANGE"
commit "Feat: another case insensitive feature"
commit "feat:"
commit "feat!stuff again"

# No breaking record in the range: the capitalized feat is a minor bump, and the
# prose, the description-less subject and the colon-less bang change nothing.
expect "1.1.0" "$(scripts/version.sh next auto)" "next auto without a breaking record"

commit "fix!: break it again"
commit "fix: more" "BREAKING CHANGE: api gone"
commit "chore: more" "BREAKING-CHANGE: api gone"

expect "2.0.0" "$(scripts/version.sh next auto)" "next auto over bang and both footers"
expect "1.1.0" "$(scripts/version.sh next minor)" "next minor is unaffected"
expect_exit 1 "app-changed rejects an unknown tag" scripts/version.sh app-changed v8.8.8

notes="$(scripts/changelog.sh notes 1.1.0 v1.0.0 "$(git rev-parse HEAD~3)")"
expect_not "Breaking changes" "${notes}" "prose mention is not breaking"
grep -q "another case insensitive feature" <<<"${notes}" || {
    echo "::error::smoke: capitalized feat not under Features"; exit 1; }
grep -q "^- feat: " <<<"${notes}" || {
    echo "::error::smoke: description-less feat not under Other changes"; exit 1; }
echo "ok: capitalized feat -> Features, description-less feat -> Other changes"

notes="$(scripts/changelog.sh notes 2.0.0 v1.0.0 HEAD)"
grep -q "Breaking changes" <<<"${notes}" || {
    echo "::error::smoke: breaking section missing"; exit 1; }
breaking="$(awk '/Breaking changes/{in_breaking=1; next} in_breaking && /^### /{in_breaking=0}
    in_breaking{print}' <<<"${notes}")"
count="$(grep -c '^- ' <<<"${breaking}" || true)"
expect "3" "${count}" "breaking entries"
expect_not "mention an upcoming" "${breaking}" "prose mention not in the breaking section"
grep -q "break it again" <<<"${breaking}" || {
    echo "::error::smoke: bang entry missing from the changelog"; exit 1; }

scripts/changelog.sh prepend 2.0.0 v1.0.0 HEAD >/dev/null
scripts/changelog.sh prepend 2.0.0 v1.0.0 HEAD | grep -q "already has 2.0.0" || {
    echo "::error::smoke: a second prepend is not idempotent"; exit 1; }
git diff --quiet -- CHANGELOG.md || {
    echo "::error::smoke: a second prepend changed CHANGELOG.md"; exit 1; }
echo "ok: prepend is idempotent"

expect_fail "a bogus range fails loudly" scripts/changelog.sh notes 9.9.9 v9.9.9.9 HEAD

git tag v9.9.9-beta.1
expect "v1.0.0" "$(scripts/version.sh latest)" "a prerelease tag is not latest"
expect "2.0.0" "$(scripts/version.sh next auto)" "next auto ignores the prerelease tag"

echo "// smoke" >> Sources/App.swift
git add Sources/App.swift
commit "feat: touch the app"
expect_exit 0 "app-changed after an app change" scripts/version.sh app-changed
expect_exit 1 "app-changed with no app change" scripts/version.sh app-changed HEAD

echo "==> Smoke-test version and changelog passed"
