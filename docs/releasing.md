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

The workflow runs the tests, builds a signed bundle, packages a `.zip`, a `.dmg`
and `checksums.txt`, generates the release notes from the commit log, publishes
the GitHub release and updates the Homebrew cask. The new `CHANGELOG.md` goes
out as a `docs/changelog-vX.Y.Z` pull request, because `main` is protected and
can't be pushed to. That PR merges itself once CI is green, provided a
`RELEASE_PAT` secret exists (see below). Without one it waits for you to close
and reopen it, which is what starts its checks.

It builds on the `macos-26` runner with Xcode 26.6, pinned in the workflow like
CI's toolchains, so the SDK a release links against only changes when someone
bumps it. If the cask update fails after the release is out, rerun just that
part with `gh workflow run cask.yml -f version=1.2.0` (no version means the
latest release).

Nothing releases on its own: landing a commit on `main` only runs CI. `bump=auto`
also refuses when nothing under `Sources/`, `Resources/` or `Sugarglider.xcodeproj` has
changed since the last tag, since a run of CI-only or docs-only commits would
otherwise ship a byte-identical app under a new number. Pass an explicit
`bump=patch` (or push a tag) when you want that anyway.

Everything it does is a script you can run locally, so a release is never a
black box:

```sh
scripts/version.sh next auto            # what would the next version be?
scripts/version.sh app-changed          # …and would the app actually differ?
scripts/release-notes.sh 1.2.0          # what would the notes say?
VERSION=1.2.0 ./build.sh                # the release bundle, ad-hoc signed
VERSION=1.2.0 scripts/make-dmg.sh
```

## Repository configuration

Everything below is optional. Without it releases still build and publish,
just ad-hoc signed and without the Homebrew cask.

| Secret / variable            | Type     | Effect when set                                         |
| ---------------------------- | -------- | ------------------------------------------------------- |
| `MACOS_CERTIFICATE_P12`      | secret   | Developer ID cert (base64 `.p12`); enables real signing |
| `MACOS_CERTIFICATE_PASSWORD` | secret   | Password for that `.p12`                                |
| `MACOS_SIGN_IDENTITY`        | secret   | e.g. `Developer ID Application: Name (TEAMID)`          |
| `MACOS_PROVISION_PROFILE`    | secret   | Developer ID profile (base64); no Keychain prompt       |
| `APPLE_ID`                   | secret   | Apple ID; enables notarization and stapling             |
| `APPLE_TEAM_ID`              | secret   | Team ID for notarization and the Keychain group         |
| `APPLE_APP_PASSWORD`         | secret   | App-specific password for notarization                  |
| `HOMEBREW_TAP_TOKEN`         | secret   | PAT with `contents:write` on the tap; updates the cask  |
| `HOMEBREW_TAP_REPO`          | variable | Tap repo, defaults to `<owner>/homebrew-tap`            |
| `RELEASE_PAT`                | secret   | PAT (contents + pull requests) here; self-merges the PR |

Base64-encode the certificate with `base64 -i cert.p12 | pbcopy`, and the
provisioning profile the same way. [signing.md](signing.md) covers what the
profile does and how to create one. Without it the app still keeps the access
token in the Keychain; it just has to ask for access once after each update.

All of these are set on this repository, so releases come out signed and
notarized and the release notes carry no Gatekeeper workaround. Without them
the workflow mostly degrades instead of failing: no certificate means an ad-hoc
build, no `APPLE_ID` means signed but not notarized, and the job warns either
way. One combination fails on purpose: an `APPLE_ID` without
`APPLE_TEAM_ID` or `APPLE_APP_PASSWORD` can't notarize, so the workflow stops at
that step rather than publishing something it can't verify. When it does
notarize, `scripts/verify-notarization.sh` checks the stapled tickets on
the app, on the copy inside the zip and on the DMG, plus Gatekeeper's verdict,
and fails the release before anything is published if one is missing.

`RELEASE_PAT` is a fine-grained token on this repository with **Contents:
read and write** and **Pull requests: read and write**. It exists because
nothing pushed or opened with the built-in `GITHUB_TOKEN` starts a workflow
run, so the changelog PR's required checks would never report and it could
never merge. It grants no extra power over `main`: that PR passes the same
ruleset as any other.
