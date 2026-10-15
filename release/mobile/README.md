# Mobile release (iPhone + Android)

The phone app `apps/mobile` (`com.shellx.prod` on both stores) is built and signed on the
maintainer's Mac, not in CI (decided 2026-10-15).

| Store | Command | Output |
|---|---|---|
| App Store (TestFlight first) | `release/mobile/ios.sh` builds and checks; `release/mobile/ios.sh --upload` also uploads | `apps/mobile/build/ios/ipa/*.ipa` |
| Google Play | `release/mobile/android.sh` | `build/release/ShellX-com.shellx.prod-<version>.aab`, uploaded by hand in Play Console |

Run both from the repo root.

## Every release

1. Raise `version:` in `apps/mobile/pubspec.yaml`. `X.Y.Z` is the store version; `+N` is the build
   number (iOS `CFBundleVersion`, Android `versionCode`). Raise `N` for **every** upload, even a
   rebuild of the same `X.Y.Z`: both stores refuse a build number they have already seen.
2. `release/mobile/ios.sh --upload`. The script refuses an ipa that is not signed by team
   `W4RF3W4VTZ`, has another bundle id or version than the pubspec, or lacks
   `aps-environment = production`. App Store Connect → ShellX → TestFlight lists the build after
   processing (5–30 minutes).
3. `release/mobile/android.sh`. The script refuses a bundle not signed by the upload key. Play
   Console → ShellX → Testing → Internal testing → **Create new release** → upload the `.aab`.
4. Test the TestFlight / internal-testing build on real phones (`docs/superpowers/GOLIVE-v1.md`,
   section iOS/AND), then promote it to production in each console.
5. After a release that old phones must not keep using, raise `MIN_MOBILE` in `deploy/relay.env`
   (admin.shellx.pro can do it too) — never before the new build is live in both stores.

## One-time setup

### iPhone

- Xcode → Settings → Accounts: signed in with `phulealali@gmail.com`, team `W4RF3W4VTZ`. The
  project uses automatic signing; the first export lets Xcode create the **Apple Distribution**
  certificate and the App Store profile of `com.shellx.prod` (`ExportOptions.plist`,
  `-allowProvisioningUpdates`). Only the Account Holder or an Admin may create that certificate.
- App ID `com.shellx.prod` has **Push Notifications**; the APNs key (`.p8`) is uploaded to Firebase
  project `shellxpro` (`docs/superpowers/HANDOFF.md`, push notifications, step 1). Without it no
  iPhone gets a notification, and nothing in the build fails.
- App Store Connect has the app (bundle id `com.shellx.prod`). Put its **Apple ID** (App
  Information → Apple ID, digits only) into `APP_STORE_ID` in `ios.sh`, so "Open the App Store" on
  the update-required screen opens the listing instead of `https://shellx.pro/`.
- **Export compliance.** The app implements standard algorithms itself (Noise:
  X25519 / ChaCha20-Poly1305 / BLAKE2s, in `packages/shellx_core`) on top of the HTTPS that iOS
  provides. `Info.plist` does not set `ITSAppUsesNonExemptEncryption`, so App Store Connect asks
  about encryption for each build (TestFlight → the build → **Manage**). Once the answer is settled,
  add that key (and `ITSEncryptionExportComplianceCode` if Apple issues one) to
  `apps/mobile/ios/Runner/Info.plist` to stop the question.
- CocoaPods: if `pod install` says the specs repository is too out-of-date (for example after a
  Firebase bump), run `pod repo update trunk` once.

### Android

- **Upload key**: `~/.shellx-release/shellx-upload.jks`, with its passwords in
  `~/.shellx-release/key.properties` (`storeFile`, `storePassword`, `keyAlias`, `keyPassword`; mode
  600, outside the repo). Gradle reads the file named by `SHELLX_ANDROID_KEY_PROPERTIES` (the script
  sets it to that path), else `apps/mobile/android/key.properties` (gitignored); without either, a
  release build is debug-signed and `android.sh` refuses it. **Back up both files** (a password
  manager); Play App Signing holds the real app signing key, so a lost upload key can be reset in
  Play Console → Setup → App signing, but that takes Google's approval and a few days.
- Play App Signing is on (the default for a new app): upload the first `.aab` and accept it.
- A personal developer account created after November 2023 must run a closed test with at least
  12 testers for 14 days before it can publish to production; an organization account need not.
