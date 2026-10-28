# Mobile release (iPhone)

The native iPhone app [`shellx-ios/`](../../shellx-ios) (`com.shellx.prod`, "ShellX") is built
and signed on the maintainer's Mac, not in CI. There is no Android app; the Flutter app and its
`android.sh` are gone.

| Command | Does | Output |
|---|---|---|
| `release/mobile/ios.sh` | Release archive, App Store export, checks | `build/release/ios/ShellX-<version>-<build>.xcarchive`, `.ipa` and `.source` |
| `release/mobile/ios.sh --upload` | Uploads the archive that `ios.sh` built and checked for the current version and build | TestFlight build, `ShellX-<version>-<build>.uploaded` |
| `release/mobile/ios.sh --check-app [--unsigned] <path.app>` | Only the checks, on a built app | |
| `shellx-ios/scripts/dev.sh test release` | Unsigned Release build and `--check-app --unsigned`, no Apple account (also part of `test all`) | |

Run them from the repo root. Full `xcodebuild` logs go to `build/release/ios/logs/`. The
`.xcarchive` of an uploaded build is never deleted: it holds the dSYMs for crash reports.

## Every release

1. Raise `CURRENT_PROJECT_VERSION` in `shellx-ios/Config/Version.xcconfig` before **every** upload,
   even a rebuild of the same version: App Store Connect refuses a build number it has already
   seen. `MARKETING_VERSION` is the store version (1.0.0 for P3; the first native upload is
   1.0.0 (5)). Commit the change.
2. `release/mobile/ios.sh`. It archives the `ShellX` scheme in Release for a generic iPhone with
   automatic signing (`-allowProvisioningUpdates`), exports it with `ExportOptions.plist`, and
   refuses the ipa when:
   - it is not signed by team `W4RF3W4VTZ`;
   - its bundle id is not `com.shellx.prod`;
   - its version or build differs from `Version.xcconfig`;
   - `get-task-allow` is true (a development signature);
   - it has `aps-environment` with a value other than `production`;
   - it embeds a `.framework` in `Frameworks/` (P3 links everything statically);
   - any Mach-O file in it contains Debug-only code: the demo (`SHELLX_DEMO`), `FakeMac`,
     `FakeRelayAccount`, `InMemorySecretStore` or anything from `ShellXAppTestSupport`.
     `Release.xcconfig` leaves `ShellXAppTestSupport` out of the link, and the app's demo code is
     under `#if DEBUG`.

   It also refuses to start when this build number was already uploaded, and it records the commit
   it was built from (`.source`).
3. Test the ipa if needed, then, only when the maintainer says so: `release/mobile/ios.sh --upload`.
   It uploads the archive from step 2, not a new build: it exports it again with
   `destination upload`, using Xcode's account session. It refuses when there is no checked archive
   for the current version and build, when `shellx-ios/`, `shellx-link/` or `release/mobile/` has
   uncommitted changes or a new commit since step 2, and when the build was already uploaded. After
   the upload it writes `ShellX-<version>-<build>.uploaded`. App Store Connect → ShellX →
   TestFlight lists the build after processing (5–30 minutes).
4. Test the TestFlight build on a real iPhone against a Mac running ShellX, then submit it for
   review.
5. Keep `MIN_MOBILE` in `deploy/relay.env` at `1.0.0`. The native app ships as 1.0.0, the same
   version as the Flutter app, so the relay cannot tell the two apart by version: moving Flutter
   users onto the native app through `MIN_MOBILE` needs a later native version (1.0.1 or above)
   live on the store first. Raising it earlier sends them to an update that does not exist yet.

## App Store Connect

- **Same app.** The native 1.0.0 replaces the Flutter 1.0.0 on the same App Store Connect app
  (bundle id `com.shellx.prod`): a higher build number of the same version, not a new app. This
  works only while version 1.0.0 has not been released on the store; once it has, App Store
  Connect refuses new 1.0.0 builds and the next upload needs 1.0.1 or above.
- **Export compliance.** The maintainer answers the encryption question in App Store Connect (the
  build → **Manage**). What to know: besides the HTTPS iOS provides, the app implements the Noise
  protocol itself (`Noise_XX_25519_ChaChaPoly_SHA256`, in `shellx-link`) on top of CryptoKit's
  standard algorithms. `Info.plist` does not set
  `ITSAppUsesNonExemptEncryption`, so the question comes back for each build until the answer is
  settled and that key (and `ITSEncryptionExportComplianceCode` if Apple issues one) is added.
- **App Review** needs a demo account and a video in the review notes: the app does nothing until
  it is paired with a Mac running ShellX, and a reviewer has no such Mac. The video shows sign-in,
  pairing by QR, an agent session, answering a pending request and voice input.
- **App Privacy.** `shellx-ios/ShellX/PrivacyInfo.xcprivacy` declares no tracking and one collected
  data type: the email address, linked to the account, used for app functionality (sign-in). The
  maintainer decides whether the App Store Connect answers (and then the manifest) also list
  **User ID** (the account's `user_id`) and **Device ID** (the relay stores each phone's device
  name, platform and Link public key). Agent conversations travel end to end encrypted between
  iPhone and Mac. The manifest also declares the required-reason APIs the app uses: `UserDefaults`
  (`CA92.1`) and file timestamps of its own history files (`C617.1`).
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

  With `-allowProvisioningUpdates`, Xcode does not ask: when automatic signing needs a profile, a
  renewed profile or a certificate, it creates it on the account during the step. `ios.sh` cannot
  stop that. It lists team `W4RF3W4VTZ`'s provisioning profiles, the certificates they name and the
  keychain's signing identities before and after each signing step (archive, export, upload) and
  prints anything new or gone between `!!!` lines. A new cloud-managed certificate never reaches the
  keychain; it shows up as a new `certificate` line in a new profile. When such lines appear
  unexpectedly, review Certificates, Identifiers & Profiles in the developer account before
  uploading. Only the Account Holder or an Admin may create a distribution certificate.
