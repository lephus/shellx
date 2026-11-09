# ShellX for iPhone

The native ShellX iOS app (1.0.0, replacing the Flutter 1.0.0 app): Swift 6, SwiftUI, iOS 17+,
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

There is one app id, `com.shellx.prod`, in every configuration. Debug builds are "ShellX Dev": on
a phone they replace the App Store / TestFlight build "ShellX" and share its Keychain items, and an
App Store or TestFlight install replaces them in turn. Debug builds register sandbox APNs tokens,
App Store builds production ones.

## Building and testing: `scripts/dev.sh`

Always build through `scripts/dev.sh` (or, for App Store builds, `release/mobile/ios.sh`); never
call `xcodebuild` directly. Build output goes to `shellx-ios/.derived/` (ignored by git).

```sh
shellx-ios/scripts/dev.sh test core          # swift test for ShellXAppCore (no simulator)
shellx-ios/scripts/dev.sh test app           # ShellXTests on the "ShellX Dev" simulator
shellx-ios/scripts/dev.sh test release       # unsigned Release build + App Store checks (= build-release)
shellx-ios/scripts/dev.sh test all           # all three; every test command also runs the two checks
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
- **Release check.** `build-release` (run by `test release` and `test all`) builds Release for a
  generic iPhone without signing, so no Apple account is involved, then runs
  `release/mobile/ios.sh --check-app --unsigned` on it: bundle id `com.shellx.prod`, the version in
  `Config/Version.xcconfig`, no embedded framework, and no Debug-only code (the test fakes such as `FakeRelayAccount`, `FakeIdentityProvider` and `InMemorySecretStore`, anything from `ShellXAppTestSupport`, the `SHELLX_DEMO` switch) in any Mach-O
  file. A leak shows up there long before release day.
- **API server.** Release builds always use `https://relay.shellx.pro`. Debug builds take
  `SHELLX_API_BASE` (`sim --api <url>`) when it is `https`, or `http` to the loopback host, so a
  relay on the Mac is reachable from the simulator only. Anything else is ignored.

## Releasing

App Store builds are made on the maintainer's Mac with `release/mobile/ios.sh`; see
[release/mobile/README.md](../release/mobile/README.md) for the steps, the checks on the ipa and the
App Store Connect answers. The privacy manifest is `ShellX/PrivacyInfo.xcprivacy`.

## Demo mode

"Try without an account" (sign-in screen) and "Try with a sample Mac" (first-Mac screen) open the demo in every build, App Store builds included: a fake account paired with "Mac giả", a Mac running inside the app (`Packages/ShellXAppCore/Sources/ShellXDemo`), with pending requests, agent sessions and chat. A "Demo · Exit" banner stays on top. The demo never calls the relay or the Keychain and keeps its history in `Application Support/ShellXDemo`. `dev.sh sim --demo` (or `device --demo`) launches a Debug build straight into it with `SHELLX_DEMO=1`, without the banner.

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

`GoogleG` is Google's official "G", cropped unchanged (20 × 20 pt) from the Light, no-text, Square iOS icons of Google's sign-in bundle (https://developers.google.com/static/identity/images/signin-assets.zip, linked from https://developers.google.com/identity/branding-guidelines). `Fonts/GoogleSans-Medium.ttf` is Google Sans Medium, the static face from Google Fonts' official download (SIL OFL 1.1, `Fonts/GoogleSans-OFL.txt`); it is a byte copy of `Resources/Fonts/GoogleSans-Medium.ttf`, which `scripts/shellx/fetch-google-branding.sh` fetched for the Mac and Windows apps. Both serve only the Continue with Google button, which follows that page. Never replace them with a Google logo from `ios/`, `Packages/` or `Sources/`, or with a drawn one.
