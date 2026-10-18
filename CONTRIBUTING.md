# Contributing to Sugarglider

Thanks for taking a look. Issues and pull requests are both welcome.

Sugarglider intentionally stays small: a native menu-bar app in pure Swift and
SwiftUI, **zero third-party dependencies**, talking to nothing but the
Nightscout site the user configures. Changes that keep it that way are the
easiest ones to merge.

## Getting set up

```sh
git clone https://github.com/nvmddev/sugarglider.git
cd sugarglider
swift build              # debug build
swift test               # test suite (Swift Testing)
./build.sh               # release build, assembled into Sugarglider.app
open Sugarglider.app
```

You need a Mac with **Apple silicon** running **macOS 26** or newer, and
**Xcode 26 or newer** (Swift 6.2). The Command Line Tools alone won't do: they
can't run the tests, because the Swift Testing macros only ship with Xcode, and
with the macOS 27 SDK they can't build the app either, since SwiftUI's `@State`
is a macro there too.

`build.sh` passes the linker the version of the SDK it builds with and fails if
the binary doesn't record exactly that. macOS gives an app its current design,
Liquid Glass, only when the binary says it was linked against a current SDK, and
SwiftPM 6.4 writes the deployment target there unless told otherwise. The
environment variables the script reads are listed at its top.

To relaunch after a rebuild, quit the running copy first:

```sh
osascript -e 'quit app "Sugarglider"' ; ./build.sh && open Sugarglider.app
```

## How the code fits together

SwiftUI app lifecycle (`MenuBarExtra` and `Settings` scenes), no app delegate.
`AppSettings` holds the persisted settings, `ReadingStore` the live state,
`Nightscout` is a stateless API client and `KeychainTokenStore` keeps the
access token in the Keychain. `ChartMath` and the pump models in
`PumpData.swift` are pure logic, and the rest are views. View bodies can't be
unit-tested, so logic lives in those types or in static helpers next to a view,
where the tests can reach it. Keep view code thin and declarative.

A few conventions span several files:

- Every setting is a stored property whose `didSet` writes it through to
  `UserDefaults`. Observation only tracks stored properties, so a computed
  property over `UserDefaults` would never redraw anything. The access token is
  the one exception and goes to the Keychain ([docs/signing.md](docs/signing.md)).
- Glucose is stored in mg/dL everywhere. The display unit only applies when a
  value is shown.
- Numbers show a dot and no grouping in every region: `String(format:)`, or a
  `FormatStyle` pinned to `AppSettings.numberLocale`, never a bare `.number`.
- The app target is isolated to the main actor by default, and macOS 26 is the
  floor, so there are no `#available` checks.

Anything else that isn't obvious has a comment where it happens, often about a
platform quirk that was measured. Read it before simplifying code that looks
more complicated than it needs to be.

## Commit messages

The changelog and the version number are both generated from commit subjects, so
this repo uses [Conventional Commits](https://www.conventionalcommits.org/):

```text
feat(chart): show the delta in the hover tooltip
fix: don't render a stale delta across a sensor gap
docs: explain which Nightscout token role is needed
```

| Type                  | Shows up as    | Version bump |
| --------------------- | -------------- | ------------ |
| `feat`                | Features       | minor        |
| `fix`                 | Bug fixes      | patch        |
| `perf`                | Performance    | patch        |
| `refactor`            | Refactoring    | patch        |
| `docs`                | Documentation  | patch        |
| `build`, `ci`         | Build & CI     | patch        |
| `test`                | Tests          | patch        |
| `chore`, `style`      | Chores         | patch        |
| anything else         | Other changes  | patch        |

Append `!` before the colon (`feat!:`) or add a `BREAKING CHANGE:` trailer for a
major bump. Those commits get a "Breaking changes" section of their own. Commits
that don't match the pattern still appear in the release notes under "Other
changes", so nothing gets dropped. They just count as a patch.

Pull requests are squash-merged, so each one lands as a single commit whose
subject is what the changelog shows: the PR title, or for a one-commit PR that
commit's own subject. Make it count. The squash commit's body collects the PR's
commit messages, so a `BREAKING CHANGE:` trailer in any of them makes the whole
PR a major release.

Everything goes through a PR, maintainers included: `main` is protected by a
repository ruleset, so no direct pushes, no force-pushes, no deletion, and CI
has to be green before a merge. Approvals aren't required, so a solo change is
still one merge click.

## Before you open a PR

- `swift test` passes.
- `./build.sh` succeeds and you've actually run the app.
- Anything touching drawing or colors was checked in **both** Light and Dark
  mode, and with both mmol/L and mg/dL if it touches values.
- Shell scripts pass `shellcheck build.sh scripts/*.sh`, and workflows pass
  `actionlint`.
- If you changed the menu bar label, the dropdown or the chart, re-run
  `scripts/make-readme-art.sh` and commit the pictures it writes into `docs/`.
  They are rendered from the app's own views with invented readings, never
  captured from the screen.
- If you changed the icon artwork in `Resources/AppIcon.icon`, re-run
  `scripts/make-icon.sh` and commit what it regenerates. CI fails otherwise.

CI repeats the automated checks. Its required **Build & test** job runs on
macOS 26 with Xcode 26.0.1, the oldest toolchain the project supports.
**Build & test (newest Xcode)** repeats the build and tests with the newest
Xcode, because the two compilers don't accept the same code. That one isn't a
required check yet.

## A note on health data

This app displays medical data. Two things follow from that:

- **Real numbers are fine, personal data never.** Glucose readings, insulin
  amounts, reservoir levels and their timestamps may go into tests and fixtures
  exactly as a real site returned them: on their own they identify nobody.
  Everything around them stays out of commits, screenshots and issue reports:
  site URLs, access tokens, names, email addresses, device names and serial
  numbers (an uploader's `device` field often carries its owner's name). Strip
  those from a captured response before it becomes a fixture. Tests never talk
  to a real site; they run against a loopback HTTP server.
- **Correctness beats cleverness.** A wrong or silently stale number on screen is
  worse than a visibly missing one. This is why stale readings get a `⚠`, why
  sensor gaps break the chart line instead of interpolating across them, and why
  the delta hides itself when the previous reading is too old. Keep that bias.

## Releasing

Maintainers only, see [docs/releasing.md](docs/releasing.md). Signing and the
Keychain are covered in [docs/signing.md](docs/signing.md).
