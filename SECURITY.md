# Security policy

## Supported versions

Only the latest release gets fixes. Please reproduce on the newest version
before reporting.

## Reporting a vulnerability

Report it privately through GitHub's
[security advisory form](https://github.com/nvmddev/sugarglider/security/advisories/new),
**not** in a public issue. Include what you did, what happened, and the app and
macOS versions you saw it on. Expect a first response within a week.

Please don't include a real Nightscout URL or access token in the report. A
redacted description, or a token you've already revoked, is enough.

## What's in scope

Sugarglider keeps your Nightscout **URL** in its preferences and your **access
token** in the Keychain, and sends the token to that one site only. There is no
telemetry, no analytics and no other network traffic. Worth reporting:

- The token leaking anywhere it shouldn't: logs, crash reports, or error
  messages shown in the app.
- Any request to a host other than the configured Nightscout site.
- Another app or process reading the token from the Keychain without macOS
  asking you first.
- Tampering with a release download, the Homebrew cask, or the release
  pipeline itself.

## Known and accepted

- **The token is a read credential.** Sugarglider sends it in the `api-secret`
  request header, not in the URL, so it stays out of your site's access logs.
  Anything that can read the request itself can still see it. Give it the
  `readable` role only, never your `API_SECRET`.
- **The site URL isn't treated as a secret.** It sits in the preferences file,
  readable by anything running as your user. If your site allows reads without
  a token, that URL is all anyone needs to see your data.

## Verifying a download

Releases from this repository are signed with a Developer ID and notarized by
Apple; a build that ships without the signing secrets is ad-hoc signed and says
so in its release notes. Every release publishes a `checksums.txt` with the
SHA-256 of its downloads. From 1.0.0 on, each release also carries a build
provenance attestation, which ties its downloads to this repository's release
workflow and the tagged commit:

```sh
shasum -a 256 Sugarglider-1.0.0.dmg          # compare with checksums.txt
gh attestation verify Sugarglider-1.0.0.dmg --repo nvmddev/sugarglider
spctl -a -vv /Applications/Sugarglider.app   # source=Notarized Developer ID
```

If a release ever ships without notarization, its release notes say so.

## Not a medical device

Sugarglider only displays data your Nightscout site already holds. It can show
stale or incorrect values and must not be used for treatment decisions. Bugs
that make it show a wrong or misleadingly stale value are taken seriously.
Please report them as normal issues and say so clearly in the title.
