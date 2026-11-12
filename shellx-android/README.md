# ShellX for Android

The native ShellX Android app (1.0.0): Kotlin, Jetpack Compose and Material 3, Android 8.0 (API 26) and
later, phone layout. It pairs with a Mac running ShellX over ShellX Link.

## Licence boundary

`shellx-android/` is closed source ("All rights reserved", see [LICENSE](LICENSE)) and ships on Google
Play, so it must not contain or link GPL code. It may use only:

- its own code (`app/`, `core/`, `scripts/`);
- the MIT library [`shellx-link/kotlin/`](../shellx-link/kotlin/README.md) (`link-core`, `link-account`);
- libraries from Maven Central and Google's Maven repository under Apache-2.0, MIT, BSD-2-Clause,
  BSD-3-Clause or the Bouncy Castle licence;
- Google SDKs listed by name: Play services (FCM and `googleid`), Firebase and Play In-App Updates.

GPL, LGPL and AGPL are never allowed. Nothing is copied, linked or imported from `ios/`, `Packages/`,
`Sources/`, `cmux-tui/` or `shellx-core/`. Translating from `shellx-ios/` is fine.

`scripts/shellx/check-android-license.sh` enforces this for `shellx-android/` and `shellx-link/kotlin/`. It
fails on:

- a dependency in a `gradle.lockfile` that is not on `scripts/shellx/android-license-allowlist.txt`, or that
  ships while its line says `test`;
- a module `build.gradle.kts` without a `gradle.lockfile` next to it;
- an allowlist line with a duplicate key, an unknown scope, a licence its scope does not allow, any GPL
  licence, a wildcard other than `androidx.*:*`, `org.jetbrains.kotlin:*` and `org.jetbrains.kotlinx:*`, or a
  Google SDK not listed by artifact;
- a Groovy `*.gradle` file, a repository other than `google()` and `mavenCentral()` (`gradlePluginPortal()`
  only in a settings `pluginManagement` block);
- a Gradle path that is not a plain string literal, is absolute, or leaves `shellx-android/`,
  `shellx-link/kotlin/`, `shellx-link/vectors/` and `shellx-link/spec/`;
- a `.jar`, `.aar` or `.so` file (other than the Gradle wrapper), a symlink, or the name of the upstream
  company (so this README avoids writing it);
- `scripts/shellx/check-link-license.sh` failing.

Test classpaths may also use EPL-1.0, EPL-2.0, ICU and CDDL-1.1 (JUnit, Robolectric and their
dependencies); the check tells the two apart by the lockfile configuration names.

Every module locks its runtime classpaths in a `gradle.lockfile`. After a dependency change:

1. `shellx-android/scripts/dev.sh lock` rewrites every lockfile;
2. `bash scripts/shellx/check-android-license.sh` names each new artefact with its lockfile and scope;
3. read each artefact's POM licence and add one allowlist line per `group:artifact`, in sorted order
   (the procedure is in Task 3 Step 6 of `docs/superpowers/plans/2026-11-07-shellx-android-3a-scaffold.md`);
4. rerun the check until it prints `check-android-license: ok`, and commit the lockfiles and the allowlist
   with the change.

## Layout

| Path | What |
| --- | --- |
| `settings.gradle.kts` | The root build `shellx-android`, with `:core` and `:app`. It includes the build `../shellx-link/kotlin`, so `com.shellx.link:link-core` and `link-account` come from source. |
| `gradle/libs.versions.toml` | Every version. `kotlin` and `junit` must equal the same keys in `shellx-link/kotlin`; `dev.sh` checks this. The SDK levels are `androidMinSdk`, `androidCompileSdk` and `androidTargetSdk`. |
| `version.properties` | `VERSION_NAME` (the iPhone's marketing version) and `VERSION_CODE` (raised before every Google Play upload). |
| `core/` | The app's logic on plain Kotlin/JVM, tested with JUnit 5. No Android dependency. |
| `app/` | The Android app: Compose UI, resources, platform glue. Unit and render tests run on the JVM with Robolectric. |
| `scripts/` | `dev.sh`, `import-strings.py`, `strings-ios-only.txt` and the script tests. |

## Building and testing: `scripts/dev.sh`

Always build through `scripts/dev.sh` (or, for Google Play builds, `release/mobile/android.sh`).

```sh
shellx-android/scripts/dev.sh test link          # JVM tests of shellx-link/kotlin
shellx-android/scripts/dev.sh test core          # :core tests
shellx-android/scripts/dev.sh test app           # :app unit tests, debug and release variants (Robolectric)
shellx-android/scripts/dev.sh test screenshots   # the *RenderTest classes
shellx-android/scripts/dev.sh test all           # all of them, the script tests and build-release
shellx-android/scripts/dev.sh screenshots record /tmp/shots   # render tests -> PNGs in /tmp/shots
shellx-android/scripts/dev.sh emulator --api 36 --headless    # boot ShellX_Dev_API_36, install and open
shellx-android/scripts/dev.sh device             # install and open the debug app on a phone
shellx-android/scripts/dev.sh build-release      # unsigned release build (R8) and its checks
shellx-android/scripts/dev.sh lock               # rewrite the lockfiles after a dependency change
shellx-android/scripts/dev.sh clean              # delete the private emulators and the build/ folders
```

Every `test` command first runs the licence check, `import-strings.py --check` and the version catalog check.

- **JDK and SDK.** Gradle runs on JDK 17: `JAVA_HOME` defaults to Android Studio's JDK, and any JDK 17 works
  (`export JAVA_HOME=…`). `ANDROID_HOME` defaults to `~/Library/Android/sdk`. The SDK packages (platform,
  build tools, emulator, system images) are installed by the user with `sdkmanager`. `dev.sh` never downloads
  them, and `gradle.properties` sets `android.builder.sdkDownload=false`, so AGP fails on a missing package
  instead of installing it (the licence check refuses the file without that line). Robolectric runs the JVM tests on Android SDK 35
  (`app/src/test/resources/robolectric.properties`), because its SDK 36 runtime needs Java 21.
- **Emulators.** `dev.sh emulator --api <26|36>` uses its own emulators, `ShellX_Dev_API_26` (port 5580,
  serial `emulator-5580`) and `ShellX_Dev_API_36` (port 5582, `emulator-5582`), created on first use from the
  installed `arm64-v8a` image (Play Store, then Google APIs, then default) with a Pixel 5 profile. It shuts
  the other one down first, so at most one runs. `--headless` runs it without a window. The emulator log is
  `build/dev/emulator-<api>.log`.
- **Phone.** `dev.sh device` takes the serial from `--serial`, then `$SHELLX_ANDROID_SERIAL`, then the first
  line of `~/.config/shellx/android-serial`, then the only phone `adb devices` lists. It refuses an emulator
  serial and a phone that is not ready. It installs only a debuggable APK of `com.shellx.prod` and checks
  the APK first (`aapt2 dump badging`): a release (non-debuggable) APK is refused on a phone. A debug
  install replaces a Play-installed "ShellX" (same id).
- **Release check.** `build-release` builds the unsigned release APK with R8, then checks with `aapt2`: app
  id `com.shellx.prod`, label "ShellX", the version in `version.properties`, min SDK 26, the target SDK from
  the catalog, a locale config, not debuggable, and that R8 wrote `mapping.txt`. No signing key is involved.
- **Memory.** Gradle's memory limits come from `~/.gradle/gradle.properties`, never from this project.
  `shellx-android/gradlew -p shellx-android --stop` frees the Gradle daemon's memory.

## App ids

Both builds use `com.shellx.prod`; the debug build is labelled "ShellX Dev" and the release build "ShellX".
The debug resource overlay `app/src/debug/res/values/strings_android.xml` renames the app. The namespace is
`com.shellx.app` in both. `AppIdentityTest` runs on both variants. Firebase config is
`app/google-services.json`, shared by both.

## Strings

- `scripts/import-strings.py` generates `app/src/main/res/values{,-vi}/strings.xml` from the iPhone catalog
  `shellx-ios/ShellX/Localizable.xcstrings`. Never edit those files by hand; rerun the script.
- A name defined in `values/strings_android.xml` replaces the generated one, with its Vietnamese text in
  `values-vi/strings_android.xml`. Android-only strings (`app_name`) live there too. iPhone-only keys are
  listed in `scripts/strings-ios-only.txt`.
- The importer refuses an iPhone string with iPhone wording (iPhone, iOS, App Store, TestFlight, Apple,
  VoiceOver, Face ID, iCloud, Siri and the like) unless it has an Android override, and it refuses
  unsupported format specifiers. Overrides say "phone", "Google Play" and "TalkBack" instead. Every `dev.sh test` fails while the
  generated files are stale (`import-strings.py --check`).

## Theme and assets

`ShellXTheme` uses the iPhone's colours (`ui/theme/ShellXColors.kt`, from the iPhone's asset catalog), with no
dynamic colour; light or dark follows the system for now. Material 3 `surface` is the screen colour, and
cards, sheets and fields sit on the `surfaceContainer*` roles (the iPhone's `Surface`). The window background
(`@color/shellx_background`) matches, so nothing flashes before Compose draws, and the Android 12+ splash
shows the app icon on it.

The logo (`res/drawable/shellx_logo.xml`) and the adaptive icon (`res/mipmap-anydpi-v26/ic_launcher.xml` with
background, foreground and monochrome layers) are drawn from `design/shellx-logo.svg`. The icon layers use a
768-unit viewport with the logo's 512 units offset by 128, so the glyphs stay inside the launcher's safe
circle.

## Third-party assets

`app/src/main/res/drawable-{mdpi,xhdpi,xxhdpi,xxxhdpi}/ic_google_g.png` is Google's official "G", cropped unchanged
(20 × 20 dp) from the Light, no-text, Square Android + Web icons of Google's sign-in bundle
(https://developers.google.com/static/identity/images/signin-assets.zip, SHA-256
`ba884069e12093b06bcfd776915081254a7c95094b80d50be2c5dc6bac1c1da1`, linked from
https://developers.google.com/identity/branding-guidelines, "Download Pre-Approved Brand Icons").
`app/src/main/assets/fonts/GoogleSans.ttf` is Google Sans, the static Medium face from fonts.google.com, under the
SIL OFL 1.1 (`GoogleSans-OFL.txt`, shipped next to it). Both serve only the Continue with Google button, which
follows that page. Never replace them with a Google logo from `ios/`, `Packages/` or `Sources/`, or with a drawn one.

## Render tests

Render tests run on the JVM: Robolectric's native graphics with Roborazzi's capture (no Gradle plugin, record
mode only). Each is a `…RenderTest` class in `app/src/testDebug/kotlin/com/shellx/app/screenshots/` that calls
`ShellXSnapshots.capture(name) { … }` with `@GraphicsMode(NATIVE)` and
`@Config(qualifiers = ShellXSnapshots.DEVICE_QUALIFIERS)` (an iPhone 16's 393 × 852 dp at 3x). It writes
`<name>-<light|dark>-<en|vi>.png`: `test screenshots` into `app/build/shellx-snapshots/`, and
`screenshots record <dir>` into `<dir>`. As on the iPhone, the tests check sizes and colours and that light
differs from dark; no golden images are committed.

## Firebase

Push uses Firebase Cloud Messaging with one config per build type: `app/src/debug/google-services.json` and
`app/src/release/google-services.json`. Both are committed (they are not secrets). The google-services plugin
applies only when both files exist; until then push stays off and `build-release` says so.

## Releasing

Google Play bundles are built and signed on the maintainer's Mac with `release/mobile/android.sh`, never in CI and never uploaded by a script. [release/mobile/README.md](../release/mobile/README.md) has the checks, the Play Console steps, the Data safety answers, the store listing and the device checklist. `dev.sh build-release` is the unsigned check that every `dev.sh test all` runs; `dev.sh` never signs with the upload key.
