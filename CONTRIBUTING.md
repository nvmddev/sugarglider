# Contributing to Sugarglider

Thanks for taking a look. [Issues](https://github.com/nvmddev/sugarglider/issues/new/choose),
pull requests and translations are all welcome.

Sugarglider is a small native app. It is written in Swift and SwiftUI and has
no third-party dependencies. It only talks to the Nightscout site that the user
sets up. Changes that keep it this way are the easiest to merge. For a bigger
change, please open an issue first, so we can agree on the approach.

Please follow the [code of conduct](CODE_OF_CONDUCT.md). Report security
problems privately, as [SECURITY.md](SECURITY.md) describes.

## Development setup

You need a Mac with Apple silicon, macOS 26 or later, and Xcode 26 or later.
The Command Line Tools alone are not enough.

```sh
git clone https://github.com/nvmddev/sugarglider.git
cd sugarglider
open Sugarglider.xcodeproj   # run with ⌘R, test with ⌘U
```

`./build.sh` builds the release version and puts `Sugarglider.app` into the
project folder. The environment variables it reads, like the signing identity,
are listed at the top of the script. Quit the running app before you start a
new build:

```sh
osascript -e 'quit app "Sugarglider"' ; ./build.sh && open Sugarglider.app
```

## Tests

Run the tests the way CI runs them:

```sh
scripts/test.sh
```

The script lists the tests that failed. Extra options go to `xcodebuild`. This
runs a single test:

```sh
scripts/test.sh '-only-testing:SugargliderTests/SugargliderTests/<name>()'
```

The tests always run in English, whatever language your Mac uses.

## How the code fits together

The app uses the SwiftUI app lifecycle, with a `MenuBarExtra` and a `Settings`
scene. It has no app delegate.

- `AppSettings` holds the saved settings.
- `ReadingStore` holds the live state and polls the site.
- `Nightscout` is a stateless API client.
- `KeychainTokenStore` keeps the access token in the Keychain.
- `ChartMath` and the pump models in `PumpData.swift` are pure logic. Most
  other files are views.

Views can't be unit tested. So logic belongs in the types above, or in static
helpers next to a view, where the tests can reach it. Keep view code thin.

These rules apply across files:

- Each setting is a stored property, and its `didSet` writes the value to
  `UserDefaults`. Observation only tracks stored properties, so a computed
  property would never update the screen. The access token is the exception.
  It goes to the Keychain ([docs/signing.md](docs/signing.md)).
- Glucose is always stored in mg/dL. The display unit only applies when a value
  is shown.
- Numbers, dates and durations follow the user's region. Format them with a
  `FormatStyle`, never with `String(format:)`.
- All text that users see is localizable. Views take a `LocalizedStringKey`,
  and models use `String(localized:)`.
- The app target runs on the main actor by default. macOS 26 is the minimum, so
  there are no `#available` checks.

Code that looks more complicated than needed often has a comment that explains
why. Read it before you simplify the code.

## Adding a language

Sugarglider is in English and German. All text is in one String Catalog,
`Sources/Sugarglider/Localizable.xcstrings`. To add a language:

1. Open the catalog in Xcode.
2. Click **+** below the list of languages and choose yours.
3. Translate every string. Strings marked *Don't Translate*, like names and
   units, stay as they are.
4. Check the app in your language. In Xcode, choose **Product → Scheme → Edit
   Scheme → Run → Options → App Language**. Leave this change to the scheme out
   of your pull request.
5. Open a pull request.

If you are not sure about a term, ask in the pull request.

## Commit messages

The changelog and the version number are made from commit subjects. That's why
this project uses [Conventional Commits](https://www.conventionalcommits.org/):

```text
feat(chart): show the delta in the hover tooltip
fix: don't render a stale delta across a sensor gap
docs: explain which Nightscout token role is needed
```

| Type             | Shows up as   | Version bump |
| ---------------- | ------------- | ------------ |
| `feat`           | Features      | minor        |
| `fix`            | Bug fixes     | patch        |
| `perf`           | Performance   | patch        |
| `refactor`       | Refactoring   | patch        |
| `docs`           | Documentation | patch        |
| `build`, `ci`    | Build & CI    | patch        |
| `test`           | Tests         | patch        |
| `chore`, `style` | Chores        | patch        |
| anything else    | Other changes | patch        |

For a major version, add `!` before the colon (`feat!:`) or a
`BREAKING CHANGE:` trailer. These commits get their own "Breaking changes"
section.

Pull requests are squash-merged. The PR title becomes the commit subject, so
write it like one. A PR with only one commit uses that commit's subject. A
`BREAKING CHANGE:` trailer in any commit of a PR makes the release a major one.

Every change goes through a pull request, even from maintainers. CI must pass
before a merge.

## Before you open a pull request

- The tests pass.
- `./build.sh` works, and you ran the app.
- Changes to drawing or colors look right in light and dark mode. Changes to
  values work in both mmol/L and mg/dL.
- New or changed text has a German translation.
  `scripts/check-localization.sh` adds new strings to the catalog and lists the
  ones without German. If you don't speak German, say so in the pull request,
  and a maintainer adds it.
- Shell scripts pass `shellcheck build.sh scripts/*.sh`, and workflows pass
  `actionlint`.
- If you changed the menu bar item, the dropdown or the chart, run
  `scripts/make-readme-art.sh` and commit the new pictures in `docs/`. The
  script draws them from the app's own views with made-up data. Never add real
  screenshots.
- If you changed the icon in `Resources/AppIcon.icon`, run
  `scripts/make-readme-icon.sh` and commit the new pictures.

CI runs the same checks. It builds and tests with two Xcode versions: 26.0.1,
the oldest one the project supports, and the newest stable one. The two
compilers don't accept exactly the same code. So a change can build on your Mac
and still fail in CI.

## Health data

Sugarglider shows medical data. Two rules follow from that.

**Keep personal data out.** Tests and fixtures may contain real glucose
readings, insulin amounts, reservoir levels and their times. These numbers
alone don't identify anyone. Never commit site URLs, access tokens, names,
email addresses, device names or serial numbers. Keep them out of screenshots
and issues too. An uploader's `device` field often contains the owner's name.
Remove all of these from a captured response before you use it as a fixture.
Tests never talk to a real site. A `URLProtocol` stub answers them.

**Show nothing rather than a wrong value.** A wrong or old number on screen is
worse than a missing one. That's why old readings get a ⚠, why the chart line
breaks at sensor gaps, and why the change since the last reading hides when
that reading is too old. Keep it that way.

## Releasing

Only maintainers release. See [docs/releasing.md](docs/releasing.md). Signing
and the Keychain are covered in [docs/signing.md](docs/signing.md).
