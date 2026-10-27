# Mobile release (iPhone)

The native iPhone app [`shellx-ios/`](../../shellx-ios) (`com.shellx.prod`, "ShellX") is built
and signed on the maintainer's Mac, not in CI. There is no Android app; the Flutter app and its
`android.sh` are gone.

| Command | Does | Output |
|---|---|---|
| `release/mobile/ios.sh` | Release archive, App Store export, checks | `build/release/ios/ShellX-<version>-<build>.ipa` and `.xcarchive` |
| `release/mobile/ios.sh --upload` | The same, then uploads that archive to App Store Connect | TestFlight build |
| `release/mobile/ios.sh --check-app <path.app>` | Only the checks, on a built app | |

Run them from the repo root. Full `xcodebuild` logs go to `build/release/ios/logs/`. Keep the
`.xcarchive` of every uploaded build: it holds the dSYMs for crash reports.

## Every release

1. Raise `CURRENT_PROJECT_VERSION` in `shellx-ios/Config/Version.xcconfig` before **every** upload,
   even a rebuild of the same version: App Store Connect refuses a build number it has already
   seen. `MARKETING_VERSION` is the store version (2.0.0 for P3). Commit the change.
2. `release/mobile/ios.sh`. It archives the `ShellX` scheme in Release for a generic iPhone with
   automatic signing (`-allowProvisioningUpdates`), exports it with `ExportOptions.plist`, and
   refuses the ipa when:
   - it is not signed by team `W4RF3W4VTZ`;
   - its bundle id is not `com.shellx.prod`;
   - its version or build differs from `Version.xcconfig`;
   - `get-task-allow` is true (a development signature);
   - it has `aps-environment` with a value other than `production`;
   - it embeds a `.framework` in `Frameworks/` (P3 links everything statically);
   - it contains Debug-only code: the demo (`SHELLX_DEMO`), `FakeMac`, `FakeRelayAccount`,
     `InMemorySecretStore` or anything from `ShellXAppTestSupport`. `Release.xcconfig` leaves
     `ShellXAppTestSupport` out of the link and the rest is under `#if DEBUG`.
3. Only when the maintainer says so: `release/mobile/ios.sh --upload`. It exports the same archive
   again with `destination upload`, using Xcode's account session. App Store Connect → ShellX →
   TestFlight lists the build after processing (5–30 minutes).
4. Test the TestFlight build on a real iPhone against a Mac running ShellX, then submit it for
   review.
5. Keep `MIN_MOBILE` in `deploy/relay.env` (now `1.0.0`) as it is until 2.0.0 is live on the
   store. Raising it earlier sends every Flutter 1.0.0 user to an update that does not exist yet.

## App Store Connect

- **Same app.** 2.0.0 replaces the Flutter 1.0.0 on the same App Store Connect app (bundle id
  `com.shellx.prod`): a new version of that app, not a new app.
- **Export compliance.** The maintainer answers the encryption question in App Store Connect (the
  build → **Manage**). What to know: besides the HTTPS iOS provides, the app implements the Noise
  protocol itself (`Noise_XX_25519_ChaChaPoly_SHA256`, in `shellx-link`) on top of CryptoKit's
  standard algorithms. `Info.plist` does not set
  `ITSAppUsesNonExemptEncryption`, so the question comes back for each build until the answer is
  settled and that key (and `ITSEncryptionExportComplianceCode` if Apple issues one) is added.
- **App Review** needs a demo account and a video in the review notes: the app does nothing until
  it is paired with a Mac running ShellX, and a reviewer has no such Mac. The video shows sign-in,
  pairing by QR, an agent session, answering a pending request and voice input.
- **App Privacy** answers match `shellx-ios/ShellX/PrivacyInfo.xcprivacy`: no tracking; the only
  data collected is the email address, linked to the account and used for app functionality
  (sign-in). Agent conversations travel end to end encrypted between iPhone and Mac. The manifest
  also declares the required-reason APIs the app uses: `UserDefaults` (`CA92.1`) and file
  timestamps of its own history files (`C617.1`).
- **Push.** P3 has no push, so the build has no `aps-environment`. From P4 (notifications) the
  entitlement becomes required, and `ios.sh` should then refuse a build without it.

## One-time setup

- Xcode → Settings → Accounts: signed in with the Account Holder's Apple ID, team `W4RF3W4VTZ`.
  Nothing else is needed; `ios.sh` never takes a password or an API key.
- Signing is automatic and reuses what the Flutter app left on the account:
  - the archive is signed with the "Apple Development" certificate in the login keychain and the
    Xcode-managed development profile of `com.shellx.prod`;
  - the export uses the team's cloud-managed **Apple Distribution** certificate (its private key
    lives with Apple, so the keychain has no distribution identity) and the Xcode-managed App Store
    profile of `com.shellx.prod`.

  If Xcode says it would create a certificate, a profile or an App ID capability, stop and decide
  first; only the Account Holder or an Admin may create a distribution certificate.
