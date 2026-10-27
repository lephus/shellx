# ShellX for iPhone

The native ShellX iOS app (2.0.0, replacing the Flutter 1.0.0 app): Swift 6, SwiftUI, iOS 17+,
iPhone only. It pairs with a Mac running ShellX over ShellX Link.

## Licence boundary

`shellx-ios/` is closed source ("All rights reserved", see [LICENSE](LICENSE)) and ships on the App
Store, so it must not contain or link GPL code. It may use only:

- its own code (`ShellX/`, `ShellXTests/`, `Packages/`);
- the MIT package [`shellx-link/`](../shellx-link) (`ShellXLinkCore`, `ShellXLinkRelay`,
  `ShellXLinkSession`, `ShellXLinkAccount`);
- Apple frameworks.

Nothing is copied, linked or imported from `ios/`, `Packages/`, `Sources/`, `cmux-tui/` or
`shellx-core/`, and no package is downloaded from the network. Reading the cmux iOS app for
reference is fine; copying from it is not.

`scripts/shellx/check-ios-license.sh` enforces this. It fails on a network package (in a
package manifest or in `project.pbxproj`), on a manifest `path:` that is not a plain string
literal, on a path that leaves `shellx-ios/` and `shellx-link/`, on any symlink, on an `import`
of a module outside its allowlist, on the name of the upstream cmux company (so this README avoids
writing it), and when
`scripts/shellx/check-link-license.sh` fails. The import check is an allowlist on purpose: adding a
new module means adding it to the script, in review.

## Layout

| Path | What |
| --- | --- |
| `ShellX.xcodeproj` | Thin project. `ShellX/` and `ShellXTests/` are synchronized folders, so adding a Swift file never touches `project.pbxproj`. |
| `Config/` | All build settings (`*.xcconfig`), `Info.plist` and entitlements. `Version.xcconfig` holds the version. |
| `ShellX/` | App target: SwiftUI, platform glue, composition root. String catalogs and assets. |
| `ShellXTests/` | Tests that need the simulator (rendering, Keychain). `Support/SnapshotWriter.swift` renders views in light and dark. |
| `Packages/ShellXAppCore` | The app's logic, tested with `swift test` on the Mac. |
| `scripts/` | `dev.sh`, `check-strings.py`, `strings-identity.txt`. |

Debug builds are "ShellX Dev" (`com.shellx.dev`) and install next to the App Store / TestFlight
build "ShellX" (`com.shellx.prod`), each with its own Keychain.

## Building and testing: `scripts/dev.sh`

Always build through `scripts/dev.sh` (or, for App Store builds, `release/mobile/ios.sh`); never
call `xcodebuild` directly. Build output goes to `shellx-ios/.derived/` (ignored by git).

```sh
shellx-ios/scripts/dev.sh test core          # swift test for ShellXAppCore (no simulator)
shellx-ios/scripts/dev.sh test app           # ShellXTests on the "ShellX Dev" simulator
shellx-ios/scripts/dev.sh test all           # both; every test command also runs the two checks
shellx-ios/scripts/dev.sh sim                # build, install and open on "ShellX Dev"
shellx-ios/scripts/dev.sh sim --api http://127.0.0.1:8787   # Debug app talks to a local relay
shellx-ios/scripts/dev.sh device --device-id <iPhone UDID>  # build, install and open on an iPhone
shellx-ios/scripts/dev.sh screenshots /tmp/shots            # *RenderTests in en and vi -> PNGs
shellx-ios/scripts/dev.sh clean              # delete the private simulator and .derived/
```

- **Simulator.** `dev.sh` only ever uses its own simulator, "ShellX Dev", created on first use with
  the newest installed iOS runtime (an iPhone 16, the size the render tests draw at). `--runtime
  <ver>` uses "ShellX Dev (iOS <ver>)" instead. At most one ShellX simulator is booted at a time.
  `sim --headless` skips bringing up the Simulator window.
- **iPhone.** `device` builds Debug with automatic signing for team W4RF3W4VTZ, then installs and
  opens the app with `xcrun devicectl`. The device id comes from `--device-id`, then
  `$SHELLX_IPHONE_DEVICE_ID`, then `~/.config/shellx/iphone-device-id` (any id `xcrun devicectl`
  accepts: the UDID, or the identifier `xcrun devicectl list devices` prints). `--build-only` stops
  after the build. The app arrives signed out; sign in on the phone. `dev.sh` never takes a password.
- **API server.** Release builds always use `https://relay.shellx.pro`. Debug builds take
  `SHELLX_API_BASE` (`sim --api <url>`) when it is `https`, or `http` to the loopback host, so a
  relay on the Mac is reachable from the simulator only. Anything else is ignored.

## Releasing

App Store builds are made on the maintainer's Mac with `release/mobile/ios.sh`; see
[release/mobile/README.md](../release/mobile/README.md) for the steps, the checks on the ipa and the
App Store Connect answers. The privacy manifest is `ShellX/PrivacyInfo.xcprivacy`.

## Demo mode

`dev.sh sim --demo` (or `device --demo`) launches a Debug build with `SHELLX_DEMO=1`: the app skips
sign-in and is paired with a fake Mac running inside the app, with pending requests, agent sessions
and chat, so the UI can be worked on without a real Mac. Release builds contain none of it. The fake Mac
arrives with the account and link work; until then the flag is passed through and has no effect.

## Strings

Every visible string lives in `ShellX/Localizable.xcstrings` (or `InfoPlist.xcstrings` for
`Info.plist` keys) with English and Vietnamese. Use a key through `String(localized: "key")` or
`LocalizedStringResource("key")`; `Text("...")`, `Button("...")`, `Label("...")`,
`.navigationTitle("...")` and `.alert("...")` with a bare literal are refused, and `Text(verbatim:)`
is for text that is never translated. `scripts/check-strings.py` checks all of this; a key whose
Vietnamese text is meant to equal the English (a product name) goes in `scripts/strings-identity.txt`.

## Assets

`AppIcon` is `design/shellx-logo.svg` rendered full-bleed at 1024 x 1024 with `rsvg-convert` (iOS
rounds the corners itself), with the alpha channel removed because App Store Connect refuses it.
`Logo` is the same SVG as a 96 pt vector PDF, used by the launch screen and the first screen. The
colour sets (`AccentColor`, `AccentText`, `Status*`) have a darker variant for the light appearance.
