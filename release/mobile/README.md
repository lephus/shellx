# Mobile release (iPhone and Android)

The native iPhone app [`shellx-ios/`](../../shellx-ios) (`com.shellx.prod`, "ShellX") is built
and signed on the maintainer's Mac, not in CI. The native Android app [`shellx-android/`](../../shellx-android) (also `com.shellx.prod`, "ShellX") is built
and signed the same way; `android.sh` never uploads: the maintainer uploads its bundle in Play Console.

| Command | Does | Output |
|---|---|---|
| `release/mobile/ios.sh` | Release archive, App Store export, checks | `build/release/ios/ShellX-<version>-<build>.xcarchive`, `.ipa` and `.source` |
| `release/mobile/ios.sh --upload` | Uploads the archive that `ios.sh` built and checked for the current version and build | TestFlight build, `ShellX-<version>-<build>.uploaded` |
| `release/mobile/ios.sh --check-app [--unsigned] <path.app>` | Only the checks, on a built app | |
| `shellx-ios/scripts/dev.sh test release` | Unsigned Release build and `--check-app --unsigned`, no Apple account (also part of `test all`) | |
| `release/mobile/android.sh` | Signed release bundle (R8 on), every Android check | `build/release/android/ShellX-<version>-<code>.aab`, `.mapping.txt` and `.source` |
| `release/mobile/android.sh --check-aab <file.aab> [<mapping.txt>]` | Only the checks, on a built bundle (it also needs the upload key properties file) | |
| `release/mobile/android.sh --mark-uploaded` | Records that the checked bundle of the current version was uploaded in Play Console | `ShellX-<version>-<code>.uploaded` |
| `python3 release/mobile/play/store_assets.py listing\|graphics\|screenshots` | Store listing checks, icon, feature graphics, screenshots | `build/release/android/play/` |
| `shellx-android/scripts/dev.sh build-release` | Unsigned release build and its checks (also part of `test all`) | |

Run them from the repo root. Full `xcodebuild` logs go to `build/release/ios/logs/`. The
`.xcarchive` of an uploaded build is never deleted: it holds the dSYMs for crash reports.

## iPhone: every release

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
   - its `ShellXGoogleClientID` is not a Google iOS client id (`SHELLX_GOOGLE_IOS_CLIENT` in `shellx-ios/Config/Release.xcconfig` still holds the placeholder);
   - it lacks the Sign in with Apple entitlement `com.apple.developer.applesignin`;
   - it lacks Google's sign-in branding: the `GoogleG` asset (in `Assets.car`) or `GoogleSans-Medium.ttf`;
   - it embeds a `.framework` in `Frameworks/` (P3 links everything statically);
   - any Mach-O file in it contains Debug-only code: a test fake (`FakeRelayAccount`, `FakeIdentityProvider`, `InMemorySecretStore`, `FakeTranscriber`, `FakeVoicePermissions`), anything from `ShellXAppTestSupport`, or the Debug demo switch `SHELLX_DEMO`. `Release.xcconfig` leaves `ShellXAppTestSupport` out of the link. The in-app demo (`ShellXDemo`, "Try without an account") ships on purpose.

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

## iPhone: App Store Connect

- **Same app.** The native 1.0.0 replaces the Flutter 1.0.0 on the same App Store Connect app
  (bundle id `com.shellx.prod`): a higher build number of the same version, not a new app. This
  works only while version 1.0.0 has not been released on the store; once it has, App Store
  Connect refuses new 1.0.0 builds and the next upload needs 1.0.1 or above.
- **Export compliance.** `shellx-ios/Config/Info.plist` sets `ITSAppUsesNonExemptEncryption` to
  `NO`, so App Store Connect does not ask the encryption question for each build. The maintainer
  settled on this for 1.0.0 (5): besides the HTTPS iOS provides, the app builds the Noise protocol
  (`Noise_XX_25519_ChaChaPoly_SHA256`, in `shellx-link`), a published protocol, only from
  CryptoKit's algorithms (X25519, ChaChaPoly, SHA-256, HMAC-SHA256) and implements no algorithm
  itself. That is Apple's "encryption limited to that within the Apple operating system", which
  needs no documentation in App Store Connect. An algorithm the app implements itself, or a
  library that brings its own, changes the answer: revisit the key before shipping one.
- **App Review.** Sign-in is Google or Apple only, so there is no demo account to give. The review notes say: "Without a Mac running ShellX, tap “Try without an account” on the sign-in screen: it opens a sample Mac with workspaces, agent sessions and requests waiting for you. Full use needs a Mac running ShellX (https://shellx.pro). To delete an account: Settings › Account › Delete Account…."
- **App Privacy.** `shellx-ios/ShellX/PrivacyInfo.xcprivacy` declares no tracking and one collected
  data type: the email address, linked to the account, used for app functionality (sign-in). The
  maintainer decides whether the App Store Connect answers (and then the manifest) also list
  **User ID** (the account's `user_id`) and **Device ID** (the relay stores each phone's device
  name, platform and Link public key). Agent conversations travel end to end encrypted between
  iPhone and Mac. The manifest also declares the required-reason APIs the app uses: `UserDefaults`
  (`CA92.1`) and file timestamps of its own history files (`C617.1`).
- **Push.** P3 has no push, so the build has no `aps-environment`. From P4 (notifications) the
  entitlement becomes required, and `ios.sh` should then refuse a build without it.

## iPhone: one-time setup

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

## Android: every release

1. Raise `VERSION_CODE` in `shellx-android/version.properties` before **every** upload, even a rebuild of the
   same version: Google Play refuses a versionCode it has already seen (the first upload is 100). `VERSION_NAME`
   is the iPhone's `MARKETING_VERSION` for the same features (contracts §7); `android.sh` prints a note when
   they differ. Commit and push `develop`: `android.sh` builds only a commit that is on `origin/develop` or
   `origin/main`.
2. Once a year, in late August, Google raises the target API level that new apps and updates need. Read
   https://developer.android.com/google/play/requirements/target-sdk; when the rule changed, add its line to
   `release/mobile/android-play-target-sdk.txt` and raise `androidTargetSdk` and `androidCompileSdk` in
   `shellx-android/gradle/libs.versions.toml` (the SDK packages are installed with `sdkmanager`, see
   `shellx-android/README.md`). `android.sh` refuses to build once the newest line is more than 365 days old.
3. `release/mobile/android.sh`. It builds `:app:bundleRelease` signed with the upload key and refuses the bundle
   when a check fails (next section). On success it writes `build/release/android/ShellX-<version>-<code>.aab`,
   its R8 mapping (`.mapping.txt`) and the commit it was built from (`.source`), and prints the upload key's
   fingerprints.
4. USER: Play Console → ShellX → Test and release → Testing → Internal testing → **Create new release**. Upload
   the `.aab`; release name `<version> (<code>)`; release notes from
   `release/mobile/play/listing/en-US/release-notes.txt` and `vi/release-notes.txt` (update them first) →
   **Next** → **Save and publish** (the button may read **Start rollout to Internal testing**).
5. `release/mobile/android.sh --mark-uploaded`. From then on `android.sh` refuses this versionCode.
6. Install the build from the internal testing link on a real phone and go through "Android: device checklist".
7. Promote it: "Google Play Console", Play 10.
8. Keep the `.aab` and `.mapping.txt` of every uploaded build. The bundle carries its R8 mapping
   (`BUNDLE-METADATA/com.android.tools.build.obfuscation/proguard.map`), so Play deobfuscates crash reports by
   itself; if App bundle explorer → the version → **Downloads** shows no deobfuscation file, upload
   `.mapping.txt` there.
9. `MIN_MOBILE` in `deploy/relay.env` is one minimum for both phones: raise it only to a version that is live on
   both the App Store and Google Play.

## Android: what android.sh refuses

- uncommitted changes, untracked files included, in `shellx-android/`, `shellx-link/`, `release/mobile/` or the
  licence check files; a HEAD that is not on `origin/develop` or `origin/main` (it fetches first, and refuses
  when it cannot); a versionCode already marked uploaded;
- a JDK older than 17; no `bundletool`, or one older than 1.17.0; an upload key properties file that is missing,
  that other users can read, that lacks `storeFile`, `storePassword`, `keyAlias` or `keyPassword`, or whose
  `storeFile` does not exist;
- a failing `scripts/shellx/check-android-license.sh`; a `shellx-android/app/google-services.json` that is
  missing or not for `com.shellx.prod` of project `shellxpro`; a `google_web_client_id`
  (`shellx-android/app/src/main/res/values/google_oauth.xml`) that is still the placeholder or that differs from
  the Web client id in `docs/superpowers/ledgers/shellx-signin-rollout.md` (contracts §16; compared once that
  ledger exists and holds the id); an analytics, advertising or crash-reporting SDK on the release classpath
  (Firebase Analytics, Crashlytics, Performance, In-App Messaging; Play services measurement, ads, analytics,
  App Set); `cleartextTrafficPermitted="true"` in `app/src/main` or `app/src/release`;
- a bundle that `jarsigner` cannot verify, that is signed with an Android debug key, or whose signer is not the
  upload key (SHA-256 compared with `keytool`);
- in the bundle's manifest: an application id other than `com.shellx.prod`; a versionCode or versionName other
  than `version.properties`; a minSdk other than 26; a targetSdk other than the catalog's `androidTargetSdk` or
  below Google Play's rule of the day; `android:debuggable`, `android:testOnly` or
  `android:usesCleartextTraffic` set to true; backup not off (`android:allowBackup="false"`); the debug-only
  activities of Compose tooling; a permission that is not in `release/mobile/android-permissions.txt`, or one
  that the list names and the bundle does not request; and, whatever the list says,
  `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` (S3 §7.4c) and `com.google.android.gms.permission.AD_ID`. A change to
  that list changes the Data safety answers or needs a Play declaration: update "Google Play: Data safety" in
  the same commit;
- debug-only code in the dex files or the R8 mapping: test libraries (JUnit, Robolectric, Roborazzi,
  kotlin-test, AndroidX Test, Compose UI test, coroutines test, MockWebServer), OkHttp's logging interceptor,
  LeakCanary, Compose tooling (its `@Preview` annotations excepted), the packages `com.shellx.core.testing`,
  `com.shellx.app.testing`, `com.shellx.app.screenshots` and `com.shellx.app.debug`, the test fakes
  `FakeRelayAccount`, `FakeIdentityProvider`, `InMemorySecretStore`, `FakeTranscriber` and
  `FakeVoicePermissions`, and `SHELLX_DEMO`. The in-app demo (`com.shellx.core.demo`, "Try without an account")
  ships on purpose;
- a native library of any ABI that is not ready for 16 KB memory pages (the rule below); native libraries while
  the bundle config does not ask for 16 KB zip alignment (`PAGE_ALIGNMENT_16K`). Google Play requires 16 KB
  support for new apps and updates that target Android 15 or later since 2025-11-01;
- a bundle without dex files, without its R8 mapping or with one that differs from `mapping.txt`, or whose
  resources lack the Firebase app id, the Google web client id or Google's "G" (`drawable/ic_google_g`, plan 3D);
- a bundle without the open-source licence notices behind Settings › About › Licenses
  (`assets/licenses/third_party_licenses.txt`), and a notice file that is out of date (next paragraphs).

Each refusal prints `violation: <what>` lines and no bundle is copied to `build/release/android/`.
`release/mobile/android.sh --check-aab <file.aab>` runs the same bundle checks on a built bundle; it also compares the bundle's signer with the upload key, so the upload key properties file must exist on that machine. On 2026-11-12
the signed bundle prints exactly one violation: `google_web_client_id` is still the placeholder, until plan 1D's
user steps (the Web OAuth client) are done and its id is written into `google_oauth.xml`.

**The 16 KB rule.** For each `.so` of every ABI, `check_android_bundle.py` refuses a LOAD segment aligned below
16 KB (`a LOAD segment is aligned to 4096 bytes; Google Play needs 16 KB (16384)`). It also rounds the GNU_RELRO
segment's start down and its end up to 16 KB, and refuses the bundle only when another loaded segment (PT_LOAD)
has a byte inside the padding that rounding added, before the start or after the end:
`GNU_RELRO 0x… shares its 16 KB pages with other loaded data at 0x…`. A RELRO padded past its own LOAD with
nothing else in those pages is accepted. Google Play runs its own 16 KB check, whose result is unknown until the
first upload, so after the first upload read the 16 KB status of the bundle in Play Console › App bundle
explorer.

**Licence notices.** The app shows `shellx-android/app/src/main/assets/licenses/third_party_licenses.txt`, which
`shellx-android/scripts/generate-licences.py` writes from `shellx-android/app/gradle.lockfile` and the POMs in
the Gradle cache. Google's oss-licenses plugin is not used: its library needs compileSdk 37 and the project is at
36. After any lockfile change run `python3 shellx-android/scripts/generate-licences.py` and commit the file.
`generate-licences.py --check`, which `shellx-android/scripts/dev.sh` and `android.sh` run, refuses a stale
file. The generator reads POMs from `~/.gradle/caches`: on a machine with an empty cache, run
`shellx-android/scripts/dev.sh lock` and one build first.

## Android: upload key and tools

- The upload key that signed the Flutter bundles is `~/.shellx-release/shellx-upload.jks`, with
  `~/.shellx-release/key.properties` (`storeFile`, `storePassword`, `keyAlias`, `keyPassword`; mode 600; outside
  the repo). `storeFile` may be absolute, start with `~/`, or be relative to the properties file. Upload key
  certificate: SHA-256 `15:1C:F3:98:CF:B0:92:48:FE:EA:D6:87:66:3C:B4:26:EB:F8:8E:3B:BF:AC:FE:17:E8:D4:C1:7D:96:AF:5A:06`,
  SHA-1 `D1:FF:07:56:42:D7:0A:14:AA:B2:CC:37:A6:DC:A2:24:0B:FE:4B:5C`.
- `shellx-android/app/build.gradle.kts` signs the release build only with the file named by
  `SHELLX_ANDROID_KEY_PROPERTIES`. `android.sh` sets it to the path above unless it is already set, and passes
  `--no-configuration-cache`, so no password lands in Gradle's configuration cache. Without the variable the
  release build is unsigned, which is what `dev.sh build-release` checks; `dev.sh` unsets it.
- Back up both files (a password manager). Play App Signing holds the app signing key, so a lost upload key can
  be replaced: Play Console → App signing → **Request upload key reset**, with the new key's certificate as a
  PEM file; Google approves it in a few days.
- `bundletool` 1.17.0 or newer (`brew install bundletool`): `android.sh` reads the bundle's manifest and config
  with it. The store graphics need `rsvg-convert` (`brew install librsvg`) and `sips` (part of macOS).

## Google Play Console

Every step below is the maintainer's. No script signs in to Play Console, Google Cloud or Firebase, changes
their settings or uploads. Answers that come from the code are written out here. What the
console gives back goes into "Google Play: facts"; SHA-1s and OAuth client IDs go into plan 1D's ledger
`docs/superpowers/ledgers/shellx-signin-rollout.md`. Play Console moves its menus: when a path below is not
there, type the page's name into the Play Console search box.

### Play 1. USER — account type (decides the path to production)

Settings (⚙) → Developer account → Account details: note **Account type** (Personal or Organization) and when
the account was created. A personal account created after 2023-11-13 must run a closed test with at least 12
testers, opted in for 14 continuous days, before it can apply for production (path B in Play 10). If ShellX's
Dashboard shows **Apply for production**, path B applies whatever the account type says. Record both under
"Google Play: facts".

### Play 2. USER — the highest versionCode

ShellX → Test and release → App bundle explorer (or "Latest releases and bundles"): note the highest version code
uploaded so far, or "none". `VERSION_CODE` must be higher; the Flutter app's last local code was 2, and the
first native upload is 100.

### Play 3. USER — App content

Policy and programs → App content:

- **Privacy policy:** `https://shellx.pro/privacy`.
- **App access:** "All or some functionality in my app is restricted" → **Add instructions** → name
  `Demo without an account`; leave the username and password empty; in "Any other information required to
  access your app" paste:

  ```text
  ShellX controls the AI coding agents and terminals that run on the user's own Mac, so full use needs a Mac running ShellX (https://shellx.pro).

  To see every screen without a Mac or an account: on the first screen, tap "Try without an account". It opens a sample Mac with workspaces, agent sessions and requests waiting for an answer. A "Demo · Exit" banner stays on top, and nothing is sent to any server.

  The app has two ways to sign in, and either one creates a new, empty ShellX account that then offers "Try with a sample Mac": "Continue with Google" with any Google account, or an email address: type it, tap "Send code", and enter the 6-digit code that ShellX emails to that address (it works for ten minutes). The demo above needs neither.

  To delete an account: Settings › Account › Delete Account…
  ```

  How a Google Play reviewer gets in: through "Try without an account", which needs no mailbox. The code
  has no review account and no fixed code, and the relay emails a different code to each address, so a reviewer
  cannot use the email way without an inbox of their own. If Play asks for credentials or rejects the
  instructions as incomplete, USER: make a test mailbox, state its address and how to read its codes in the
  text above, and keep it working while the review lasts. Status: `pending (USER)`.

- **Ads:** "No, my app does not contain ads".
- **Content rating:** start the questionnaire; email: the support email; category "All other app types" (or
  "Utility, Productivity, Communication, or Other" when that is offered). Answer **No** to every question about
  violence, sexuality, language, controlled substances, gambling, crude humour, users interacting or exchanging
  content, sharing location, buying digital goods and unrestricted internet access: ShellX shows only what the
  user's own Mac and agents produce for that user, and nothing passes between users. Save and submit; expect the
  lowest rating everywhere.
- **Target audience and content:** age group **18 and over** only; "Could your store listing unintentionally
  appeal to children?" **No**.
- **News apps:** No. **Government apps:** No. **Financial features:** none. **Health:** none.
- **Data safety:** "Google Play: Data safety" below. Before you submit it, check that the website describes
  deletion (plan 1D publishes it): `curl -fsSL https://shellx.pro/privacy | grep -c -F 'Settings › Account › Delete Account…'`
  and `curl -fsSL https://shellx.pro/privacy | grep -c 'id="delete-account"'` both print 1 or more.
- **Advertising ID:** "No" (`android.sh` refuses the `AD_ID` permission).
- Any other declaration Play shows (foreground service, photo and video permissions, exact alarms, full-screen
  intent, accessibility): ShellX uses none of them; stop and find out how the permission got past
  `release/mobile/android-permissions.txt`.

### Play 4. USER — store settings

Grow users → Store presence → Store settings: **App**, category **Productivity**; email: the support address of
the privacy policy (`phule9225@gmail.com` today); website `https://shellx.pro`; no phone number.

### Play 5. USER — main store listing

First make the files ("Google Play: store listing and graphics"). Grow users → Store presence → Main store
listing, default language **English (United States) – en-US**: **App name**, **Short description** and **Full
description** from `release/mobile/play/listing/en-US/` (`title.txt`, `short-description.txt`,
`full-description.txt`); **App icon** `build/release/android/play/icon-512.png`; **Feature graphic**
`feature-graphic-en-US.jpg`; **Phone screenshots** `screenshots/dark/en-US/*.jpg` in file-name order. No video,
and no tablet screenshots (the app has a phone layout only). Then **Manage translations → Add your own
translations → Vietnamese – vi**, with `listing/vi/`, `feature-graphic-vi.jpg` and `screenshots/dark/vi/*.jpg`.
The light theme set is in `screenshots/light/`; use one theme for both languages.

### Play 6. USER — pricing and countries

Monetize → App pricing: **Free**. An app published as free cannot become paid later (in-app products remain
possible). Countries and regions: all.

### Play 7. USER — first upload to internal testing

Test and release → Testing → Internal testing:

1. **Testers** → create an email list "ShellX internal" with the Google account of your phone → Save. Copy the
   opt-in link into "Google Play: facts".
2. **Create new release.** The first time, Play App Signing asks how the app is signed: keep the Google-generated
   key (Play App Signing). The upload key stays `~/.shellx-release/shellx-upload.jks`.
3. Upload `build/release/android/ShellX-<version>-<code>.aab`, release name `<version> (<code>)`, release notes
   from both `release-notes.txt` files → **Next** → **Save and publish**.
4. Run `release/mobile/android.sh --mark-uploaded`.

### Play 8. USER — signing keys, Google sign-in and push (contracts §16, plan 1D)

Type "App signing" into the Play Console search box (Test and release → App integrity → Play app signing, or
Protected with Play → Play Store protection → Manage Play app signing). Copy the SHA-1 and SHA-256 of the **App
signing key certificate** and of the **Upload key certificate**. The upload key's SHA-256 must equal the
`==> upload key:` line of `android.sh` (`15:1C:F3:98:CF:B0:92:48:FE:EA:D6:87:66:3C:B4:26:EB:F8:8E:3B:BF:AC:FE:17:E8:D4:C1:7D:96:AF:5A:06`).
Write both SHA-256s into "Google Play: facts" and the App signing **SHA-1** into the rollout ledger (client 5's
row and "Hand-off to 3D / 3H"). Then, in the Google Cloud project `shellxpro`:

1. **The third Android OAuth client.** Google sign-in on Android uses three Android OAuth clients, each one
   package and one SHA-1 (contracts §16), all under the one app `com.shellx.prod`: `ShellX Android (dev)`
   (`com.shellx.prod` + this Mac's debug SHA-1), `ShellX Android (upload key)` (`com.shellx.prod` + the upload
   key SHA-1, `D1:FF:07:56:42:D7:0A:14:AA:B2:CC:37:A6:DC:A2:24:0B:FE:4B:5C`) and `ShellX Android (Play signing)`
   (`com.shellx.prod` + the **App signing** SHA-1). Plan 1D creates the first two and leaves the third
   `pending (3H)` until the first upload exists. Create it: Google Auth Platform → Clients →
   **+ Create client** → Android → name `ShellX Android (Play signing)`, package `com.shellx.prod`, the App
   signing SHA-1 → Create; record its client ID in the ledger's client 5 row. Without it, "Continue with Google"
   fails on every install from Google Play. If the ledger still shows client 3 `pending (3H)`, create it the
   same way with the debug SHA-1
   (`keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android | grep SHA1`).
2. **The Firebase API key** (contracts §12, plan 1D Task 4): APIs & Services → Credentials → API keys → the key
   that the ledger's "Firebase" section names ("Android key (auto created by Firebase)") → Application
   restrictions: Android apps → **+ Add** `com.shellx.prod` with the App signing SHA-1 → leave the API
   restrictions unchanged → Save. Then check push on the Play build (D8).

### Play 9. USER — pre-launch report

About an hour after the rollout: Test and release → Pre-launch report → Overview. Expect no crash and no ANR;
Google's test robot reaches only the sign-in screen and the demo. Note the warnings worth fixing.

### Play 10. USER — testing tracks and the path to production

Choose the path from Play 1:

- **Path A** (an organization account, or a personal account created on or before 2023-11-13, and no **Apply for
  production** on the Dashboard): when the device checklist passes on the internal build and
  `docs/superpowers/ledgers/shellx-android-parity.md` has no `todo` row (S3 §8: production once G1 and G2 hold), Test and release →
  Production → **Create new release** → **Add from library** → the same bundle → release notes → **Next** →
  **Save and publish**. Google reviews it; a staged rollout is optional. Going from internal testing straight to
  production is acceptable: S3 §8's order (internal → closed → production) means closed testing when Play requires it.
- **Path B** (a personal account created after 2023-11-13):
  1. Test and release → Testing → Closed testing → the "Alpha" track → **Testers**: an email list or a Google
     Group with at least 12 people. Invite 15–20: a tester who opts out stops counting, and one who opts out and
     back in starts their 14 days again. Countries: all.
  2. **Create new release** → **Add from library** → the same bundle → **Next** → **Save and publish**. Send the
     opt-in link; each tester opts in, installs ShellX from Google Play and keeps it.
  3. Write the day the 12th tester opted in under "Google Play: facts". Fourteen days later: Dashboard → **Apply
     for production**. Play asks about the closed test (how you recruited testers, how they used the app, a
     summary of their feedback), about the app (who it is for, its value, expected installs in the first year)
     and about readiness (what changed after testing, how you know it is ready). Answer from the real test.
  4. Google usually answers within 7 days. Then follow path A.

## Google Play: Data safety

Drafted from the code on 2026-11-07 (plan 3H). `android.sh` keeps the facts these answers depend on: the exact
permission list; no analytics, advertising or crash SDK; no cleartext traffic. Check the answers again whenever
`release/mobile/android-permissions.txt` or the release classpath changes.

- Does your app collect or share any of the required user data types? **Yes**.
- Is all of the user data collected by your app encrypted in transit? **Yes**: HTTPS to `relay.shellx.pro` and to
  Google; the release build refuses cleartext traffic.
- Account creation methods: both of these. **Username and other authentication**: an email address with a
  6-digit one-time code that ShellX emails to it (no password). **OAuth**: Sign in with Google.
- Delete account URL: **https://shellx.pro/privacy#delete-account**.
- Do you provide a way for users to request that some or all of their data is deleted, without requiring them to
  delete their account? **No**.
- Shared with third parties: **nothing**. Google (Firebase Cloud Messaging) and the server host process data on
  ShellX's behalf, which Play does not count as sharing.

| Data type | Collected | Processed ephemerally | Required or optional | Purposes | Fact |
| --- | --- | --- | --- | --- | --- |
| Personal info › Email address | Yes | No | Required | App functionality, Account management | Both sign-in ways collect it. With the emailed code the user types the address and the app sends it, with the app's language, to the relay, which emails the code; with Google it comes from the Google ID token. The relay stores the account's email and the apps show it. |
| Personal info › Name | Yes | Yes | Required | Account management | Only the Google way: the ID token the app sends carries the Google profile name; the relay reads only the email and the account ID, and stores no name. The emailed-code way asks for no name. |
| Personal info › User IDs | Yes | No | Required | App functionality, Account management | The ShellX account and device IDs, and, for Google sign-in, the Google account ID (`sub`). |
| Device or other IDs | Yes | No | Required | App functionality | The Firebase Cloud Messaging token and the Firebase installation ID (registered after sign-in, whether or not notifications are allowed), and the phone's ShellX device ID, Link public key and device name (the phone's name from Android settings, or its model name when none is set), which the user's Mac shows. The IP address is used only in memory, to limit sign-in attempts. |
| App info and performance › Diagnostics | Yes (maintainer's call, below) | No | Required | App functionality | The app's version number, sent with each request so the relay can ask outdated apps to update. |
| Messages, Photos and videos, Files and docs, App activity | No | | | | Agent chat, answers, attachments and terminal input and output are end-to-end encrypted (Noise_XX_25519_ChaChaPoly_SHA256) between the phone and the user's own Mac; the relay forwards data it cannot read, which Play does not count as collected. |
| Audio › Voice or sound recordings | No (maintainer's call, below) | | | | The phone's speech recognition turns speech into text, on the phone when it can, otherwise through the service the phone uses (usually Google's); ShellX receives only the text, which travels end-to-end encrypted to the Mac. |
| Photos (camera) | No | | | | The camera only reads the pairing QR code, on the phone. |
| Location, Financial info, Health and fitness, Contacts, Calendar, Web browsing, Installed apps, Crash logs | No | | | | No location, contacts or calendar permission; no analytics or crash SDK (`android.sh` refuses them). |

The maintainer's calls, as for the iPhone's App Privacy answers:

- **App version.** Declaring it as Diagnostics is the cautious answer; the alternative treats a version number as
  not user data. The privacy policy already says the server stores it.
- **Voice.** ShellX never receives audio, but the phone's speech service may send it to its own servers under its
  own terms (privacy policy §2). The cautious alternative declares "Voice or sound recordings" as collected,
  processed ephemerally, optional, for App functionality.

## Google Play: store listing and graphics

- **Copy:** `release/mobile/play/listing/<en-US|vi>/`: `title.txt` (at most 30 characters),
  `short-description.txt` (80), `full-description.txt` (4000), `release-notes.txt` (500; edit it for each
  upload) and `feature-graphic-tagline.txt`. `python3 release/mobile/play/store_assets.py listing` checks the
  limits, the composed form, emoji, the words Play bans in titles and short descriptions, and that the in-app
  labels the copy quotes are the app's own strings.
- **Icon and feature graphics:** `python3 release/mobile/play/store_assets.py graphics` writes
  `build/release/android/play/icon-512.png` (`design/shellx-logo.svg` without its border, full bleed, 512 px,
  32-bit PNG; Play rounds the corners and adds the shadow) and `feature-graphic-<en-US|vi>.jpg`
  (`release/mobile/play/feature-graphic.svg` with the tagline, 1024×500, JPEG without alpha).
- **Screenshots:** `shellx-android/scripts/dev.sh screenshots record build/release/android/play/render`, then
  `python3 release/mobile/play/store_assets.py screenshots --from build/release/android/play/render` →
  `build/release/android/play/screenshots/<light|dark>/<en-US|vi>/<NN>-<slug>.jpg`, 1080×1920, from
  `StoreScreenshotsRenderTest` (the demo's screens). Shots whose sample text is Vietnamese are in the Vietnamese
  set only (`SHOTS` in `store_assets.py`).

## Android: device checklist

On the user's own Android phone, with the build installed from the internal testing link (Play 7), before every
promotion. Record each item as pass, fail or n/a with the date; any fail stops the promotion. Prerequisites:
Play 8 done; a Mac running ShellX 1.8.0 or later, signed in with the same Google account (for D7, the first
desktop release with the phone terminal, contracts §7); the relay deployed with plans 1A and 3F (plan 1D);
Gboard (or Laban Key) with Vietnamese Telex.

- **D1. The phone.** Maker, model, Android version and API level (Settings › About phone, or
  `adb shell getprop ro.product.manufacturer`, `ro.product.model`, `ro.build.version.release`,
  `ro.build.version.sdk`); the parity ledger's "Test devices" table has them. D9's late-notification test
  applies when the maker is Xiaomi (Redmi, POCO), OPPO, vivo, realme, OnePlus or iQOO.
- **D2. Install and first launch.** The launcher shows "ShellX" with the ShellX icon. The app
  opens on the logo, then the sign-in screen, in the phone's light or dark mode. Settings › About shows the
  uploaded version and code.
- **D3. Demo.** On the sign-in screen, "Try without an account" opens the demo with the "Demo · Exit" banner:
  workspaces, running agents and requests show; Allow on a permission card removes it; Exit returns to sign-in.
  Turn on airplane mode and repeat: the demo works the same.
- **D4. Sign-in, both ways.** (a) Email code: on the sign-in screen type an address you can read in "Email
  address" and tap "Send code"; the code step opens ("We sent a 6-digit code to …"); the mail arrives (check
  spam) with a 6-digit code; enter it: the app is signed in, and Settings › Account labels the address "Email
  code". Also try a wrong code (an error, the step stays) and "Resend code" (it counts down first). Sign out.
  (b) Google: "Continue with Google" opens Google's account sheet; after choosing the account the app is
  signed in, and Settings › Account shows its email. A developer error or an immediate failure of this button
  means the `ShellX Android (Play signing)` client is missing (Play 8); the email way does not need it. Once, for S1 §2.1 criterion 2 (plan 1D leaves it to
  this plan): sign in here first with a Google account new to ShellX, then on a Mac with the same account, then do
  D5 with that Mac; time the seconds from Google's sheet to signed in.
- **D5. Pairing with the camera.** On the Mac, Pair Phone… shows a QR code. On the phone, scan it: the camera
  permission prompt appears once; after Allow the phone shows the Mac's name and waits; Allow on the Mac; the
  phone lists the Mac's workspaces. Then turn the camera permission off in Android settings and scan again: the
  app shows the camera-blocked state with a way to the settings, and pasting the `shellx-link://…` code still
  pairs.
- **D6. Voice.** In an agent chat with an empty field, hold the mic: the microphone prompt appears once; say a
  Vietnamese sentence and release: the recognised text is sent. Settings › Voice now shows the language picker;
  switch to English and repeat.
- **D7. Telex in the terminal.** Open a workspace's shell pane. With Gboard set to Vietnamese Telex, type
  `tieengs Vieejt` and Enter: the Mac's terminal shows `tiếng Việt`, with the right marks and no doubled
  letters. Backspace removes one character; an English keyboard types plain ASCII.
- **D8. Push.** With ShellX in the background, make an agent on the Mac ask for permission: within seconds a
  notification names the agent and the workspace (on Android 13 and later the app asked for the notification
  permission first). Tapping it opens Needs you on that request. Answering a request on the Mac removes its
  notification. With ShellX open in front, a request shows in the app and no system notification appears. With
  the phone locked for 5 minutes, a new request still arrives.
- **D9. "Notifications arriving late?" ("Thông báo đến trễ?").** Settings › Notifications shows the row; it
  explains the steps for this phone's maker, and its button opens ShellX's page in Android settings. When D1 says
  the maker holds notifications: swipe ShellX away from the recent apps, trigger a request and note whether it
  arrives; follow the in-app steps (autostart, no battery restriction), swipe ShellX away again and trigger
  another: it must arrive.
- **D10. Back.** The system Back gesture (predictive back on Android 14 and later) closes a sheet, then the
  screen, then leaves the app from the home screen; nothing traps Back.
- **D11. Delete account** (last, once with a throwaway Google account and once with a throwaway email address).
  Sign out (it asks first), sign in with the throwaway account, Settings › Account › Delete Account…: the dialog
  says what is deleted. For Google, Google asks for the account again; for an email-code account the app emails a
  new 6-digit code to the address and asks for it, and only a tap on Delete Account then deletes. Afterwards the
  app returns to sign-in with no Mac, and signing in again with that account or address starts an empty account.
  Sign back in with your own account, and pair again if the Mac is gone.
- **D12. Update prompt.** n/a for the first release. From the second release on: keep the older build
  installed, roll the newer one out to internal testing, and check that Google Play's own update dialog (plan 3E's
  flexible flow: "Update" / "No thanks") appears at launch and on a return to the app, and that a "Restart" bar
  shows once the download is done.
- **D13. About.** Settings › About › Licenses opens the open-source licence notices, which list the app's libraries
  with their licences (the iPhone opens shellx.pro instead: an Android-only difference in the parity ledger); Back
  returns to Settings.

## Google Play: facts

Not secret. SHA-1s and OAuth client IDs live in `docs/superpowers/ledgers/shellx-signin-rollout.md` (plan 1D).

| Fact | Value | From |
| --- | --- | --- |
| Developer account type | pending (USER) | Play 1 |
| Account created after 2023-11-13 (path B) | pending (USER) | Play 1 |
| Highest versionCode uploaded before the native app | pending (USER) | Play 2 |
| Upload key certificate SHA-256 | 15:1C:F3:98:CF:B0:92:48:FE:EA:D6:87:66:3C:B4:26:EB:F8:8E:3B:BF:AC:FE:17:E8:D4:C1:7D:96:AF:5A:06 | `android.sh` |
| App signing key certificate SHA-256 | pending (USER, Play 8) | Play 8 |
| Internal testing opt-in link | pending (USER, Play 7) | Play 7 |
| Closed test: day the 12th tester opted in (path B) | pending (USER, Play 10) | Play 10 |
