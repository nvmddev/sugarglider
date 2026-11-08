# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). Entries are generated
from [Conventional Commits](https://www.conventionalcommits.org/) by
`scripts/changelog.sh`, so edit commit messages, not this file.

## [1.0.0](https://github.com/nvmddev/sugarglider/releases/tag/v1.0.0) (2026-11-08)

### ⚠️ Breaking changes

- require macOS 26 with the Liquid Glass design ([`0ce9dc3`](https://github.com/nvmddev/sugarglider/commit/0ce9dc340b2810ea13fc3514ea6bd1c0fcdc6c97))

### Features

- show the time in range as a ring beside the reading ([`0b8eced`](https://github.com/nvmddev/sugarglider/commit/0b8eced857726aca90552effa9ca5c43967d1fe7))
- show the cannula and sensor ages ([`9306e25`](https://github.com/nvmddev/sugarglider/commit/9306e25cacd30782addb71cffa257590c33594c1))
- translate the app into German ([`837c782`](https://github.com/nvmddev/sugarglider/commit/837c7827a8207e9e2205101b27801c74ae2ec0d7))
- describe the chart and the trend to VoiceOver ([`fe2d37e`](https://github.com/nvmddev/sugarglider/commit/fe2d37e6a61e7481dc15d17d313cb208c4330c97))
- offer a switch for each extra pump value the site sends ([`d159041`](https://github.com/nvmddev/sugarglider/commit/d159041fe85f25f8d2575e74a8899c56aa1e7c1a))
- run in the App Sandbox ([`fe9d348`](https://github.com/nvmddev/sugarglider/commit/fe9d348e2411a59091af1cd8d91baa02184e057b))
- follow the system's light or dark appearance ([`77a105d`](https://github.com/nvmddev/sugarglider/commit/77a105d0cc795998c90a178399ba0e0c3f961cbc))
- **settings:** add an Open at Login switch ([`50dd299`](https://github.com/nvmddev/sugarglider/commit/50dd29981ac228030932ee7d31a28d3ea82b1293))
- follow the region's formats and the system's text styles ([`825a0c0`](https://github.com/nvmddev/sugarglider/commit/825a0c0057b394a04a9220ebb79d75a138bbd767))
- offer a solid dropdown background besides glass ([`711953c`](https://github.com/nvmddev/sugarglider/commit/711953c6bd8c5a4bec55563c69dca35daa2bd12a))
- show readings beyond the sensor's range as LOW and HIGH ([`57c4f77`](https://github.com/nvmddev/sugarglider/commit/57c4f77bfb8cb8fb28f509101870f1a43a731c62))
- show pump data from Nightscout in the dropdown and the chart ([`311afa1`](https://github.com/nvmddev/sugarglider/commit/311afa158fb6a1cb585a1ce051f2ebcfbcb3a747))

### Bug fixes

- keep a reading on a threshold in the zone nearer the target ([`ce84ce8`](https://github.com/nvmddev/sugarglider/commit/ce84ce8ab97cbc3e70063f9cd2516db099d060c7))
- **security:** keep the access token out of the URL ([`6e1f1f6`](https://github.com/nvmddev/sugarglider/commit/6e1f1f6eb98d1d2c506f9ecf961c952424ec7605))
- keep sensor error codes off the chart, follow Open at Login changes ([`e5bdd0d`](https://github.com/nvmddev/sugarglider/commit/e5bdd0d6914a652388b9b395a2ad3582ce1ee772))
- steadier polling after sleep and safer token handling ([`c5bc57a`](https://github.com/nvmddev/sugarglider/commit/c5bc57ab0d582199c3f0ff45d80e0714d3413732))
- read each uploader's pump records the way it sends them ([`dad1a26`](https://github.com/nvmddev/sugarglider/commit/dad1a2659a26dc27fc525616a898cd716ff46431))
- **menubar:** keep the reading's age current while polls fail ([`eac1809`](https://github.com/nvmddev/sugarglider/commit/eac1809b2f1eef0a6638580cf42a383a174a20e3))

### Performance

- redraw only the chart's hover layer while the pointer moves ([`6375216`](https://github.com/nvmddev/sugarglider/commit/6375216e41e6973f56f83f7a882f3278f3b5c417))

### Refactoring

- native SwiftUI and Swift Charts throughout ([`c163eb0`](https://github.com/nvmddev/sugarglider/commit/c163eb056be6a083d22eea2073ed6815fb31d930))

### Documentation

- simplify CONTRIBUTING.md and explain how to add a language ([`eb72811`](https://github.com/nvmddev/sugarglider/commit/eb72811b2b0b86f0f52980297e89d547db0500f5))
- show light and dark mode in the README ([`86d5fbb`](https://github.com/nvmddev/sugarglider/commit/86d5fbb54f810da9544fc21392398d29ab8baf2c))
- rewrite the README in short, plain sentences ([`00a1944`](https://github.com/nvmddev/sugarglider/commit/00a19444dbb3ffc268c43fb2f26ca81a0efa01b2))
- show the 1.0 features in the README ([`e447745`](https://github.com/nvmddev/sugarglider/commit/e44774552378963ef612bcd6f4e1956fdf9aa4bf))

### Build & CI

- test and release with the newest stable Xcode ([`00bce85`](https://github.com/nvmddev/sugarglider/commit/00bce8520483c22b050e950126a4ddd80475e918))
- build with an Xcode project instead of SwiftPM ([`8a473b9`](https://github.com/nvmddev/sugarglider/commit/8a473b9560b9b0121acf5dfc0c243571d3829592))

**Full changelog**: https://github.com/nvmddev/sugarglider/compare/v0.5.0...v1.0.0

## [0.5.0](https://github.com/nvmddev/sugarglider/releases/tag/v0.5.0) (2026-08-30)

### Features

- **security:** keep the Nightscout token in the Keychain (#11) ([`30d968b`](https://github.com/nvmddev/sugarglider/commit/30d968b928ea552293fbf4e19053fcafb3aa9c20))
- **release:** ship Developer ID-signed, notarized downloads (#10) ([`92ca539`](https://github.com/nvmddev/sugarglider/commit/92ca53979bb3c4ebb6d1b679034a19b127e0be28))

### Documentation

- changelog for v0.4.0 [skip ci] ([`73c5074`](https://github.com/nvmddev/sugarglider/commit/73c5074b2ed1d74f741820e4ed6c9cce29e8f57d))

### Build & CI

- **release:** open the changelog as a PR instead of pushing to main (#8) ([`24c94b3`](https://github.com/nvmddev/sugarglider/commit/24c94b3c30ba241d693df0d0fb6e109a7d0c28e4))

### Chores

- point the repository references at nvmddev (#9) ([`8e35f58`](https://github.com/nvmddev/sugarglider/commit/8e35f58a461581da72cb9df8af23d4f166427442))

**Full changelog**: https://github.com/nvmddev/sugarglider/compare/v0.4.0...v0.5.0

## [0.4.0](https://github.com/nvmddev/sugarglider/releases/tag/v0.4.0) (2026-08-06)

### Features

- **settings:** make the Colors preview slider set the preview's range ([`2f27985`](https://github.com/nvmddev/sugarglider/commit/2f2798555c27390df1937da7e7f6e8f98add771d))

### Documentation

- changelog for v0.3.0 [skip ci] ([`f2ed165`](https://github.com/nvmddev/sugarglider/commit/f2ed165bf7b54713c750e9e63f73e813bd0942b8))

**Full changelog**: https://github.com/nvmddev/sugarglider/compare/v0.3.0...v0.4.0

## [0.3.0](https://github.com/nvmddev/sugarglider/releases/tag/v0.3.0) (2026-08-03)

### Features

- **icon:** ship the new artwork with a light and a dark variant ([`f067ef5`](https://github.com/nvmddev/sugarglider/commit/f067ef5eddc48dc0b7e633b1e315cdd619a254ee))
- **settings:** add an About tab with version, links and license ([`45f0020`](https://github.com/nvmddev/sugarglider/commit/45f0020dfa949c99da3b61a0df5725d3f63b0fe5))

### Bug fixes

- **ci:** authenticate the cask push and make it runnable on its own ([`60325d7`](https://github.com/nvmddev/sugarglider/commit/60325d7044281c7571d81ab56e5a8bd1de226a11))

### Documentation

- changelog for v0.2.0 [skip ci] ([`e5f35bf`](https://github.com/nvmddev/sugarglider/commit/e5f35bfa7264ddf34e3f7954c67add68f39f29db))

### Build & CI

- fail when the committed icon artifacts go stale ([`36fc2ca`](https://github.com/nvmddev/sugarglider/commit/36fc2ca8aad7d8668c8890b6e03a2575e7dc3d99))

### Chores

- **scripts:** match the repo's case and continuation indentation ([`b8d5cf8`](https://github.com/nvmddev/sugarglider/commit/b8d5cf8fb517643088b3dda145086200eed7429c))

**Full changelog**: https://github.com/nvmddev/sugarglider/compare/v0.2.0...v0.3.0

## [0.2.0](https://github.com/nvmddev/sugarglider/releases/tag/v0.2.0) (2026-07-31)

### Features

- **settings:** configurable stale delay, full-look presets, dotted numbers ([`3140a8e`](https://github.com/nvmddev/sugarglider/commit/3140a8e567eefb329acf707b057caf53a1b62e97))
- **chart:** extend the range to 3 days and fetch history incrementally ([`65477df`](https://github.com/nvmddev/sugarglider/commit/65477dfa1e334d4d540ca6661df2ea19147736e1))
- **dropdown:** make the chart range typeable next to the slider ([`a185bef`](https://github.com/nvmddev/sugarglider/commit/a185bef2f6254a96615a635d47157afcaf4db6f3))
- **dropdown:** show the action buttons as icons and move Quit to the right ([`4a0e539`](https://github.com/nvmddev/sugarglider/commit/4a0e53983a46c5b386d478d30fb7a00f43e3619a))
- **chart:** make the slider, line shading, and latest-reading dot configurable ([`1fe6946`](https://github.com/nvmddev/sugarglider/commit/1fe694609649f519110340a07b5baabc101dedb6))
- **ci:** refuse an auto release when the built app wouldn't change ([`a15d1f2`](https://github.com/nvmddev/sugarglider/commit/a15d1f268929e4845325b1b2b46da2641a92761a))

### Bug fixes

- **chart:** name the weekday once the window spans a day or more ([`981f900`](https://github.com/nvmddev/sugarglider/commit/981f9006563e32ac1b75b52b09e84e6aa410fdd5))
- **dropdown:** only edit the chart range when the field is clicked ([`fde7846`](https://github.com/nvmddev/sugarglider/commit/fde784622b6e4fbbb82e3e6905e3f3841a898753))
- **ci:** use the non-deprecated depends_on form in the cask template ([`a0166d2`](https://github.com/nvmddev/sugarglider/commit/a0166d23fa2420ab74839901372443d98f2afa56))
- **ci:** stage the cask before checking whether it changed ([`04f359e`](https://github.com/nvmddev/sugarglider/commit/04f359effce57c2c3a7a2e5c1458fd0609f605ba))

### Refactoring

- **chart:** map readings through Layout and split draw per layer ([`1b19ce0`](https://github.com/nvmddev/sugarglider/commit/1b19ce0072fead442fbe88563f6bf8fd5e149214))
- **api:** decode Nightscout entries with Codable ([`fca8e3b`](https://github.com/nvmddev/sugarglider/commit/fca8e3b578417bbdada724190bf21df8b17c03bb))

### Documentation

- drop the removed --no-quarantine flag from install instructions ([`02814cf`](https://github.com/nvmddev/sugarglider/commit/02814cfc489ebc80061091d64b4b251a091d4e04))
- changelog for v0.1.0 [skip ci] ([`ba71640`](https://github.com/nvmddev/sugarglider/commit/ba71640233036b99c4400de5391cdf9213220069))

### Build & CI

- adopt the ExistentialAny and MemberImportVisibility features ([`7741a18`](https://github.com/nvmddev/sugarglider/commit/7741a18fe383d94f99e67200a5f0b1cb0e14614a))

**Full changelog**: https://github.com/nvmddev/sugarglider/compare/v0.1.0...v0.2.0

## [0.1.0](https://github.com/nvmddev/sugarglider/releases/tag/v0.1.0) (2026-07-31)

### Features

- make polling interval configurable ([`1cfa834`](https://github.com/nvmddev/sugarglider/commit/1cfa83435f9a47bef084f8d34a49d5262ab0eff1))

### Documentation

- add changelog, contributing guide, security policy and templates ([`bae498f`](https://github.com/nvmddev/sugarglider/commit/bae498f3ac354f51b4ec7aa3f549da44a538c5e9))

### Build & CI

- bump the actions group with 2 updates (#1) ([`1e183c2`](https://github.com/nvmddev/sugarglider/commit/1e183c2351511d8fdcc2fa3c7878e4b6ae85d049))
- add CI and tag-driven release pipeline ([`024932a`](https://github.com/nvmddev/sugarglider/commit/024932a3337d399f8cafa7976de200d3ba5a941f))
- make build.sh configurable for release automation ([`d14b898`](https://github.com/nvmddev/sugarglider/commit/d14b898971e4eaa45e62a4198a7798d51540768e))

### Other changes

- Add live color preview to Settings, fix theme and preset overwrite ([`ecef23e`](https://github.com/nvmddev/sugarglider/commit/ecef23ef485fb26cc1519c989e54924e047f6270))
- Initial commit ([`23ef5dc`](https://github.com/nvmddev/sugarglider/commit/23ef5dcf096ac8fd2e6352236ba5e6011fef340b))
