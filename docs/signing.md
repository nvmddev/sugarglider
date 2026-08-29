# Signing and the Keychain

The Nightscout access token lives in the Keychain, and macOS decides *which*
Keychain an app may use from its code signature. That turns signing into a
user-visible thing here rather than a release detail:

| Signed with                            | Keychain used             | Access prompts                                      |
| -------------------------------------- | ------------------------- | --------------------------------------------------- |
| Ad-hoc (`./build.sh` with no identity)  | file-based login Keychain | on every rebuild — the signature changes each time   |
| Developer ID                            | file-based login Keychain | once, then "Always Allow" sticks                     |
| Developer ID + provisioning profile     | data-protection Keychain  | none                                                 |

Nothing in the app hardcodes which one it gets. `TokenStore.swift` probes once
whether the data-protection Keychain accepts a write, uses that answer for every
call afterwards, and reads the *other* Keychain as a fallback — so a release that
starts (or stops) shipping the profile migrates the item across instead of
looking at an empty Keychain and appearing to have lost the token. Improving the
signature is a build-time change only, and it is reversible.

## What the profile is for

`keychain-access-groups` is the entitlement that lets the app own its Keychain
item outright. Signing with it is not enough: it is a *restricted* entitlement,
so AMFI kills the app at launch unless an embedded provisioning profile
authorises it — the failure looks like `Launch failed … Code=163`, or an
immediate exit 137 when the binary is started directly. Three one-time steps:

1. An **Identifier** (App ID) for `dev.nevermind.sugarglider`, at
   [developer.apple.com → Identifiers](https://developer.apple.com/account/resources/identifiers/list)
   → `+` → App IDs → App. The description is free text; the Bundle ID must match
   exactly and be **Explicit**, not a wildcard. Nothing under Capabilities needs
   ticking — the access group `TEAMID.dev.nevermind.sugarglider` follows from the
   App ID itself, and Keychain Sharing is an Xcode-side switch rather than a
   portal capability.
2. A **Developer ID provisioning profile** for that App ID: Profiles → `+` →
   Distribution → **Developer ID** → pick the App ID → pick the *Developer ID
   Application* certificate → download.
3. The downloaded file saved as `Resources/embedded.provisionprofile`
   (gitignored), and `TEAM_ID` set when building:

   ```sh
   TEAM_ID=3CNF2FUWG7 \
   SIGN_IDENTITY="Developer ID Application: Josua Bryner (3CNF2FUWG7)" \
   ./build.sh
   ```

Apple grants the profile `keychain-access-groups` as the team wildcard
`TEAMID.*`, which covers the concrete group `build.sh` writes into the
entitlements. Worth checking before building, because a profile that lacks it
yields an app that signs cleanly and then refuses to launch:

```sh
security cms -D -i Resources/embedded.provisionprofile | plutil -p -
```

With no profile (or no `TEAM_ID`) `build.sh` says so and signs without
entitlements, which is what forks, CI and every ad-hoc local build get.

## In CI

Add the profile as the `MACOS_PROVISION_PROFILE` secret:

```sh
base64 -i Resources/embedded.provisionprofile \
  | gh secret set MACOS_PROVISION_PROFILE
```

`release.yml` writes it back out, checks that it really grants
`keychain-access-groups`, and hands `build.sh` the `TEAM_ID` it already has from
`APPLE_TEAM_ID`. Without the secret the release still builds, signs and
notarizes; the app just falls back to the login Keychain and asks for access once
after each update.

## Not the same prompt

`codesign` may itself ask for permission to use the signing key the first time.
That one is about your login keychain, not the app's, and is settled with
"Always Allow" — or permanently:

```sh
security set-key-partition-list -S apple-tool:,apple:,codesign: \
  -s -k "$LOGIN_KEYCHAIN_PASSWORD" ~/Library/Keychains/login.keychain-db
```

## Current state

Both halves are in place: `MACOS_PROVISION_PROFILE` is set on the repository, and
the profile ("Sugarglider Developer ID", valid to 2044) sits at
`Resources/embedded.provisionprofile` on the maintainer's machine. It is
gitignored, so a fresh clone builds without it — download it again from the
Apple portal, since a repository secret cannot be read back.

Two things confirm the entitled path actually works, both worth repeating if the
signing setup changes, because a broken one looks fine until launch:

```sh
codesign -d --entitlements - Sugarglider.app       # keychain-access-groups present
open Sugarglider.app                               # AMFI kills it instantly if not
```

And the giveaway that the *data-protection* Keychain is really in use: after the
app has stored a token, `security find-generic-password -s dev.nevermind.sugarglider`
finds nothing. The `security` tool only sees the file-based Keychain.
