<!--
The PR title becomes a Conventional Commit on merge (squash), because
scripts/changelog.sh turns commit subjects into the release notes:

    feat(chart): hover tooltip shows the delta
    fix: don't show a stale delta across a sensor gap
    docs: explain the token permissions

Types: feat, fix, perf, refactor, docs, build, ci, test, chore, style.
A `!` before the colon (or a BREAKING CHANGE trailer) triggers a major bump.
-->

## What changed

## Why

## How I verified it

<!-- SwiftUI views aren't unit-testable here, so UI changes need a real run. -->

- [ ] The tests pass (⌘U in Xcode, or `xcodebuild test`)
- [ ] `./build.sh` succeeds and I ran `Sugarglider.app`
- [ ] Checked the menu-bar item and the dropdown in **both** Light and Dark mode
      (if this touches drawing or colors)
- [ ] Numbers show and accept correctly in **both** mmol/L and mg/dL
      (if this touches values or the threshold fields)
- [ ] `shellcheck build.sh scripts/*.sh` and `actionlint` are clean
      (if this touches shell scripts or workflows)
- [ ] `scripts/make-readme-art.sh` and `scripts/make-readme-icon.sh` ran, and the
      changed pictures are committed (if this touches drawing)
