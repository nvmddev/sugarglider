# Releasing Sugarglider

Maintainers only. Two ways in, both landing in the same
[release workflow](../.github/workflows/release.yml):

```sh
# Let the workflow pick the version from the Conventional Commits since the
# last tag, then tag, build and publish:
gh workflow run release.yml -f bump=auto

# …or force a level, or rehearse without publishing anything:
gh workflow run release.yml -f bump=minor
gh workflow run release.yml -f bump=auto -f dry_run=true

# …or just push a tag yourself:
git tag v1.2.0 && git push origin v1.2.0
```

The workflow runs the tests, builds a universal signed bundle, packages a `.zip`,
a `.dmg` and `checksums.txt`, generates the release notes from the commit log,
publishes the GitHub release, and opens a `docs/changelog-vX.Y.Z` pull request
with the updated `CHANGELOG.md` — `main` is protected, so it can't push there
directly. That PR merges itself once CI is green, provided a `RELEASE_PAT`
secret exists (see below); without one it waits for you to close and reopen it,
which is what starts its checks.

Nothing releases on its own: landing a commit on `main` only runs CI. `bump=auto`
additionally refuses when nothing under `Sources/`, `Resources/` or
`Package.swift` has changed since the last tag — a run of CI-only or docs-only
commits would otherwise ship a byte-identical app under a new number. Pass an
explicit `bump=patch` (or push a tag) when you want that anyway.

Everything it does is a script you can run locally, which is the point — a
release should never be a black box:

```sh
scripts/version.sh next auto            # what would the next version be?
scripts/version.sh app-changed          # …and would the app actually differ?
scripts/release-notes.sh 1.2.0          # what would the notes say?
VERSION=1.2.0 UNIVERSAL=1 ./build.sh    # the exact bundle CI produces
VERSION=1.2.0 scripts/make-dmg.sh
```

### Optional repository configuration

Everything below is optional — without it releases still build and publish,
just ad-hoc signed and without the Homebrew cask.

| Secret / variable            | Type     | Effect when set                                         |
| ---------------------------- | -------- | ------------------------------------------------------- |
| `MACOS_CERTIFICATE_P12`      | secret   | Developer ID cert (base64 `.p12`); enables real signing |
| `MACOS_CERTIFICATE_PASSWORD` | secret   | Password for that `.p12`                                |
| `MACOS_SIGN_IDENTITY`        | secret   | e.g. `Developer ID Application: Name (TEAMID)`          |
| `APPLE_ID`                   | secret   | Apple ID; enables notarization and stapling             |
| `APPLE_TEAM_ID`              | secret   | Team ID for notarization                                |
| `APPLE_APP_PASSWORD`         | secret   | App-specific password for notarization                  |
| `HOMEBREW_TAP_TOKEN`         | secret   | PAT with `contents:write` on the tap; updates the cask  |
| `HOMEBREW_TAP_REPO`          | variable | Tap repo, defaults to `<owner>/homebrew-tap`            |
| `RELEASE_PAT`                | secret   | PAT (contents + pull requests) here; self-merges the PR |

Base64-encode the certificate with `base64 -i cert.p12 | pbcopy`. All of these
are set on this repository, so the workflow signs and notarizes on its own and
the release notes carry no Gatekeeper workaround. Without them it degrades
instead of failing — no certificate means an ad-hoc build, no `APPLE_ID` means
signed but unnotarized — which is why `scripts/verify-notarization.sh` runs on
the notarizing path and fails the release rather than letting a quarantined
download ship under green checks.

`RELEASE_PAT` is a fine-grained token on this repository with **Contents:
read and write** and **Pull requests: read and write**. It exists because
nothing pushed or opened with the built-in `GITHUB_TOKEN` starts a workflow
run: the changelog PR's required checks would never report and it could never
merge. It grants no extra power over `main` — that PR passes the same ruleset
as any other.
