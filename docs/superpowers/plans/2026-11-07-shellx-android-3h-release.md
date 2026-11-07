# ShellX Android 3H — Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the ShellX Android app releasable on Google Play: `release/mobile/android.sh` builds the signed app bundle and refuses it unless every release check passes (it never uploads), Gradle signs release builds with the upload key, the store listing (English and Vietnamese copy, icon, feature graphic, screenshots from the demo) is produced and checked, and `release/mobile/README.md` holds the Play Console runbook, the Data safety answers, the testing tracks and the device checklist as USER steps.

**Architecture:** `release/mobile/android.sh` (bash 3.2, built like `release/mobile/ios.sh`) refuses dirty or unpushed sources, builds `:app:bundleRelease` signed with the upload key named by `SHELLX_ANDROID_KEY_PROPERTIES`, verifies the signature with `jarsigner` and `keytool`, dumps the bundle's manifest and config with `bundletool`, and hands every content check to `release/mobile/check_android_bundle.py` (Python 3.9 standard library). Only then does it copy the bundle, its R8 mapping and its commit into `build/release/android/`. `release/mobile/play/store_assets.py` checks the listing copy and renders the store graphics with `rsvg-convert` and `sips`; the phone screenshots come from a Robolectric render test of the demo's screens. Everything in Play Console, Google Cloud or Firebase is a USER step.

**Tech Stack:** bash 3.2, Python 3.9 standard library with `unittest`, Gradle Kotlin DSL (Android Gradle plugin signing config), bundletool 1.17.0 or newer (Homebrew), JDK 17 `keytool` and `jarsigner`, `rsvg-convert` (librsvg), `sips` (macOS), Kotlin with Robolectric and Roborazzi (plan 3A's `ShellXSnapshots`).

**Spec:** `docs/superpowers/specs/2026-11-07-shellx-android-app-design.md` (S3, in Vietnamese) §5, §6.1, §7.3–§7.4c, §8 and §10; `docs/superpowers/specs/2026-11-07-shellx-google-sign-in-design.md` (S1) §6.7, §6.8 and §10. Cross-plan names: `docs/superpowers/plans/2026-11-07-shellx-mobile-contracts.md` §1, §5, §7, §8, §11, §12 and §14–§16; where they and this plan overlap, the contracts win. This plan builds on plan 3A (Gradle build, `dev.sh`, licence check, `version.properties`, Firebase files), 3C (the demo), 3D, 3E and 3G (screens and their render tests) and 1D (the rollout ledger and the Google OAuth clients).

## Global Constraints

- Branch `feat/shellx-android-3h-release` from `develop`, in the worktree `.worktrees/android-3h-release`. Run every command from the worktree root unless a step names another directory.
- Files this plan may change: `release/mobile/` (new `android.sh`, `check_android_bundle.py`, `android-play-target-sdk.txt`, `android-permissions.txt`, `play/`, `tests/`; `README.md`), `shellx-android/app/build.gradle.kts` (release signing; Task 7's licences plugin and library), `shellx-android/settings.gradle.kts`, `shellx-android/gradle/libs.versions.toml`, `shellx-android/app/gradle.lockfile` and `scripts/shellx/android-license-allowlist.txt` (Task 7 only), `shellx-android/scripts/dev.sh` (two changes in Task 4, one more on Task 7's fallback path), `shellx-android/README.md` (the "Releasing" section), `shellx-android/app/src/main/kotlin/com/shellx/app/ui/settings/AboutSection.kt` and the new `Licences.kt` (Task 7), `shellx-android/app/src/testDebug/kotlin/com/shellx/app/screenshots/StoreScreenshotsRenderTest.kt`, `shellx-android/app/src/testDebug/kotlin/com/shellx/app/ui/settings/LicencesRowTest.kt`, the files of Task 7's fallback path (only on that path), `shellx-android/version.properties` (Task 9), `docs/superpowers/ledgers/shellx-android-parity.md` (the phone row, Task 7's `A-` row, and Task 9 Step 1's rows for new iPhone keys), `shellx-android/app/src/main/res/values*/strings.xml` (generated), `values*/strings_android.xml` and `shellx-android/scripts/strings-ios-only.txt` (only through Task 9 Step 1's string import, by plan 3A Task 11 Step 1's rule) and, after landing, `docs/superpowers/ledgers/shellx-signin-rollout.md` (only its `pending (3H)` items and the criterion 2 row of Task 9 Step 7). Nothing else.
- Never upload a bundle, never call the Google Play Developer API, never sign in to Play Console, Google Cloud or Firebase, never change their settings, never publish, never deploy, never merge to `main`. Each of those is a USER step; the executor only hands the user the exact step.
- The upload key: never print, copy, commit or `cat` `~/.shellx-release/key.properties` or the keystore. Inspect the properties file only with `test -f`, `stat -f '%Lp'` and `grep -c` on key names. The store password reaches `keytool` only through the environment variable `SHELLX_STOREPASS`, and Gradle only through the properties file. Never ask for a password in chat; the user types passwords only in their own Terminal.
- Shell scripts run on bash 3.2: no associative arrays, no `mapfile`, no `${x,,}`; `set -euo pipefail`. Every `rm` target is written `"${VAR:?}/…"` or `"${VAR:?}"`: this session's safety check refuses a removal whose target could expand to `/`.
- Python: 3.9 standard library only, `from __future__ import annotations`, scripts run with `python3 -I`. Tests use `unittest` and must pass under both `python3` and `/usr/bin/python3`.
- JDK and Gradle as in plan 3A: `JAVA_HOME` defaults to `/Applications/Android Studio.app/Contents/jbr/Contents/Home`, `ANDROID_HOME` to `$HOME/Library/Android/sdk`. Gradle runs only through `shellx-android/scripts/dev.sh`, `release/mobile/android.sh`, and the commands Task 4 names. Any Gradle run with `SHELLX_ANDROID_KEY_PROPERTIES` set passes `--no-configuration-cache`, so no password is written to Gradle's configuration cache.
- Never install `com.shellx.prod` on any phone (plan 3A): the user installs it from the Google Play internal testing track. Never touch the user's running ShellX or cmux apps.
- Exact values: application id `com.shellx.prod`; minSdk 26; targetSdk at least Google Play's rule of the day (36 since 2026-08-31); the first `VERSION_CODE` is 100 and must be above every versionCode already uploaded; versionCode at most 2100000000; outputs in `build/release/android/`; key properties default `~/.shellx-release/key.properties`, keystore `~/.shellx-release/shellx-upload.jks`; Firebase project `shellxpro`; privacy policy `https://shellx.pro/privacy`; account deletion URL `https://shellx.pro/privacy#delete-account`; in-app deletion path "Settings › Account › Delete Account…" / "Cài đặt › Tài khoản › Xoá tài khoản…"; demo button "Try without an account" / "Xem thử không cần tài khoản" (contracts §11–§12, plan 1C).
- Store copy is exactly this plan's text: UTF-8, composed form (NFC), one trailing newline. Change it only by the rule of Task 5 Step 7.
- Commits use an explicit `git add <paths>`, never `git add -A`. When a task has logic, the failing test is committed first: `test(release): …`, then `feat(release): …`; Gradle and Kotlin changes use `build(shellx-android): …` and `test(shellx-android): …`; documentation `docs(release): …`.
- Landing (contracts §1): after the final review, merge into `develop` and push `develop`. Every Play Console, Google Cloud and Firebase action, and the upload, stay the user's.

## Review Focus

1. **The upload key properties file as the user really has it.** `storeFile` may be relative to the properties file, start with `~/`, or be absolute (the Flutter build accepted any); the file may be missing, readable by others, or lack a key. The script and Gradle must resolve the keystore the same way and refuse clearly. Tests: Task 3 `test_store_file_may_be_relative_under_home_or_absolute`, `test_refuses_a_missing_shared_or_incomplete_key_file`.
2. **A password with `$`, quotes, spaces or `=`.** It must reach `keytool` intact, through the environment, and never appear in the output, in `keytool`'s argument list or in the Gradle log. Test: Task 3 `test_build_writes_the_checked_bundle_its_mapping_and_its_source` (its store password is `st$re pw"=1`).
3. **Where the script is run from.** A detached HEAD on a pushed commit (a tag checkout), a run from a subdirectory or from a worktree must work, and the outputs land at the root of that checkout. Test: Task 3 `test_accepts_a_detached_pushed_head_run_from_a_subdirectory`.
4. **No network, or a renamed remote.** When `git fetch` fails, stale `origin/*` refs must not let an unpushed commit through. Test: Task 3 `test_refuses_when_origin_cannot_be_fetched`.
5. **Store copy that Play rejects or that drifts from the app.** Vietnamese counted in characters, decomposed (NFD) text pasted from elsewhere, an emoji, a banned word in the title or short description, and a quoted in-app label that a later plan renamed. Tests: Task 5 `test_limits_are_counted_in_characters`, `test_refuses_decomposed_text_emoji_banned_words_and_missing_files`, `test_the_listing_quotes_the_apps_own_labels`.

## File map

```
release/mobile/android.sh                         Task 3   build, check, --check-aab, --mark-uploaded
release/mobile/check_android_bundle.py            Tasks 1–2, 7 every content check (sources and bundle)
release/mobile/android-play-target-sdk.txt        Task 1   Google Play's target API rule table
release/mobile/android-permissions.txt            Task 1   the exact permission set of the release build (Task 4 may adjust)
release/mobile/tests/test_android_manifest_checks.py   Task 1
release/mobile/tests/test_android_bundle_checks.py     Task 2
release/mobile/tests/test_android_sh.py                Task 3
release/mobile/tests/test_store_assets.py              Task 5
release/mobile/play/store_assets.py               Task 5   listing checks, icon, feature graphics, screenshots
release/mobile/play/feature-graphic.svg           Task 5
release/mobile/play/listing/{en-US,vi}/{title,short-description,full-description,release-notes,feature-graphic-tagline}.txt   Task 5
shellx-android/app/build.gradle.kts               Task 4   release signing from SHELLX_ANDROID_KEY_PROPERTIES
shellx-android/scripts/dev.sh                     Task 4   unset the key variable; test all runs release/mobile/tests
shellx-android/app/src/testDebug/kotlin/com/shellx/app/screenshots/StoreScreenshotsRenderTest.kt   Task 6
release/mobile/tests/test_android_licence_checks.py    Task 7
shellx-android/{settings.gradle.kts,app/build.gradle.kts,gradle/libs.versions.toml}   Task 7   Google's open-source licences plugin and library
shellx-android/app/src/main/kotlin/com/shellx/app/ui/settings/{AboutSection,Licences}.kt   Task 7   Settings › About › Licenses
shellx-android/app/src/testDebug/kotlin/com/shellx/app/ui/settings/LicencesRowTest.kt      Task 7
release/mobile/README.md, shellx-android/README.md     Task 8
shellx-android/version.properties                 Task 9   the first Play version
```

---

### Task 0: Worktree, prerequisites, tools and the facts only the user has

**Files:** none in the repository.

**Interfaces:**
- Produces, for later tasks (write them down; they are not stored anywhere yet): `PLAY_API` (Google Play's target API level today), the upload key state, `ACCOUNT_TYPE`, `ACCOUNT_CREATED`, `HIGHEST_CODE`, the phone's maker, model and Android version, and the rollout ledger's state (Web client id, `pending (3H)` items).

- [ ] **Step 1: Create the worktree**

  Use superpowers:using-git-worktrees: a new branch `feat/shellx-android-3h-release` from `develop` at `.worktrees/android-3h-release` (ignored through `.git/info/exclude`). Git fallback:

  ```bash
  cd /Users/lehuuphu/Documents/myProjects/shellx
  git worktree add .worktrees/android-3h-release -b feat/shellx-android-3h-release develop
  cd .worktrees/android-3h-release
  git branch --show-current; git merge-base --is-ancestor develop HEAD && echo based-on-develop
  ```

  Expected: `feat/shellx-android-3h-release`, then `based-on-develop`. If a native tool picked another name, run `git branch -m feat/shellx-android-3h-release`.

- [ ] **Step 2: Find the plan files**

  The contracts and the plans may be untracked in the main checkout. When `docs/superpowers/plans/2026-11-07-shellx-mobile-contracts.md` is missing in the worktree, read it, this plan and plans 3A, 3C and 1D from `/Users/lehuuphu/Documents/myProjects/shellx/docs/superpowers/plans/` by absolute path. Never add them to this branch.

- [ ] **Step 3: Check that plans 3A–3G are on `develop`**

  ```bash
  for f in shellx-android/version.properties shellx-android/scripts/dev.sh scripts/shellx/check-android-license.sh \
    shellx-android/app/src/release/google-services.json shellx-android/app/src/main/res/values/google_oauth.xml \
    shellx-android/core/src/main/kotlin/com/shellx/core/demo/DemoEnvironment.kt \
    shellx-android/app/src/main/kotlin/com/shellx/app/ui/nav/ShellXNavHost.kt \
    shellx-android/app/src/testDebug/kotlin/com/shellx/app/screenshots/ShellXSnapshots.kt; do
    test -e "$f" && echo "ok $f" || echo "MISSING $f"; done
  grep -c 'cmd_build_release' shellx-android/scripts/dev.sh
  grep -rl 'FirebaseMessagingService' shellx-android/app/src/main | head -1
  grep -rl 'TerminalPane' shellx-android/app/src/main | head -1
  ```

  Expected: eight `ok` lines, a count of 1 or more, and one path from each `grep -rl` (3E's FCM client, 3G's terminal). A `MISSING` line or an empty `grep` means a plan has not landed: stop and tell the user that 3H runs after 3A–3G (contracts §1). The one exception is `google-services.json`: when only it is missing, plan 3A Task 10 is still `pending (USER)`; ask the user to do that task's Step 1 and go on meanwhile.

- [ ] **Step 4: Check the tools**

  ```bash
  "/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/java" -version 2>&1 | head -1
  bundletool version; rsvg-convert --version; command -v sips
  python3 --version; /usr/bin/python3 --version
  ```

  Expected: `openjdk version "17.` (or newer), a bundletool version of 1.17.0 or newer, an `rsvg-convert` version, `/usr/bin/sips`, and two Python versions of 3.9 or newer. If bundletool is missing or older, ask the user to run `brew install bundletool` (or `brew upgrade bundletool`) in their own Terminal. If `rsvg-convert` is missing: `brew install librsvg`.

- [ ] **Step 5: Look up Google Play's target API rule (read-only)**

  Open https://developer.android.com/google/play/requirements/target-sdk. Note `PLAY_API`: the level that new apps and app updates must target today, and the date it applies from. On 2026-11-07 that is 36 from 2026-08-31 (extensions ended 2026-11-01). If a newer rule is already in force on the day you run this, Task 1 Step 4 appends its line to the table, and 3A's `androidTargetSdk` must be at least that level: if it is lower, stop and tell the user (raising it is an SDK install, plan 3A Task 0 Step 6).

- [ ] **Step 6: USER — the upload key is on this Mac**

  Run (no content is printed):

  ```bash
  ls -l ~/.shellx-release/ | awk '{print $1, $NF}'
  stat -f '%Lp' ~/.shellx-release/key.properties
  grep -c -E '^[[:space:]]*(storeFile|storePassword|keyAlias|keyPassword)[[:space:]]*[=:]' ~/.shellx-release/key.properties
  ```

  Expected: `key.properties` and `shellx-upload.jks` listed, `600`, then `4`. If the folder is missing, ask the user to restore `~/.shellx-release` from their backup. If the key is lost, tell the user the README's upload key reset path (Task 8, "Android: upload key and tools") and record "upload key: pending (USER)"; then Task 4 Step 6, Task 7 Step 16 and Task 9 Step 6 are skipped and reported as pending.

- [ ] **Step 7: USER — Play Console facts needed before the build**

  Ask the user (in Vietnamese) for two facts from Play Console:
  1. `ACCOUNT_TYPE` and `ACCOUNT_CREATED`: Play Console → ⚙ Settings → Developer account → Account details: "Account type" (Personal or Organization) and roughly when the account was created (before or after 2023-11-13). Also whether ShellX's Dashboard shows **Apply for production**.
  2. `HIGHEST_CODE`: ShellX → Test and release → App bundle explorer (or "Latest releases and bundles"): the highest version code uploaded so far, or "none".

  **Meanwhile:** go on with Tasks 1–7. When an answer is missing at Task 8, write `pending (USER)`. When `HIGHEST_CODE` is 100 or more, Task 9 Step 2 sets `VERSION_CODE` to `HIGHEST_CODE + 1`.

- [ ] **Step 8: Record the phone**

  Run: `grep -n "The user's phone" docs/superpowers/ledgers/shellx-android-parity.md`

  The row holds the maker, model and Android version (plan 3A Task 1). If it says `pending (USER)`, ask the user for the phone's maker, model and Android version (or read them with `adb -s "$(cat ~/.config/shellx/android-serial)" shell getprop ro.product.manufacturer` and `ro.product.model`, `ro.build.version.release`, `ro.build.version.sdk` when the phone is connected). Task 8 writes the answer into the row. `OEM_HOLDS_PUSH` is `yes` when the maker is Xiaomi (Redmi, POCO), OPPO, vivo, realme, OnePlus or iQOO.

- [ ] **Step 9: Read the sign-in rollout state (plan 1D)**

  ```bash
  L=docs/superpowers/ledgers/shellx-signin-rollout.md; test -f "$L" || L=/Users/lehuuphu/Documents/myProjects/shellx/$L
  grep -n -E 'ShellX Web \(Android sign-in\)|ShellX Android|pending \(3H\)' "$L"
  grep -n -E '^\| (1 Relay deploy \(1A \+ 3F\)|2 Desktop 1\.8\.0 and iPhone) \|' "$L"
  grep -o '<string name="google_web_client_id"[^<]*<' shellx-android/app/src/main/res/values/google_oauth.xml
  ```

  Note the Web client id of row "ShellX Web (Android sign-in)", the Android client rows, and every `pending (3H)` item; and whether `google_web_client_id` still holds a placeholder. If the ledger does not exist yet, plan 1D has not started: go on; the release checks then refuse a placeholder id, and Task 9 reports the release candidate as waiting for 1D.

  Also note `RELAY_LIVE` (the Status row "1 Relay deploy (1A + 3F)" says `done`: the production relay has Google sign-in and Android push) and `MAC_1_8_0` (the row "2 Desktop 1.8.0 and iPhone" says `done`). Nothing here stops this plan, but the device checklist's D4–D9 and D11 need both; Task 9 reports them as waiting while either is not `done`.

---

### Task 1: Bundle checker, part 1 — manifest, Google Play's target API rule and the permission list

**Files:**
- Create: `release/mobile/check_android_bundle.py`
- Create: `release/mobile/android-play-target-sdk.txt`, `release/mobile/android-permissions.txt`
- Test: `release/mobile/tests/test_android_manifest_checks.py`

**Interfaces:**
- Produces (module `check_android_bundle`, imported by the tests with `release/mobile` on `sys.path`):

```python
ANDROID_NS = "{http://schemas.android.com/apk/res/android}"
APPLICATION_ID = "com.shellx.prod"
MIN_SDK = "26"
NEVER_ALLOWED_PERMISSIONS: dict[str, str]   # permission -> reason quoted in the message
DEBUG_ONLY_ACTIVITIES = ("androidx.activity.ComponentActivity", "androidx.compose.ui.tooling.PreviewActivity")

class RuleTableError(ValueError): ...

@dataclass(frozen=True)
class Manifest:
    package: str; version_code: str; version_name: str; min_sdk: str; target_sdk: str
    application: dict[str, str]     # android:* attributes of <application>, by local name
    permissions: tuple[str, ...]    # <uses-permission> and <uses-permission-sdk-23>, in order
    activities: tuple[str, ...]     # android:name of each <activity> inside <application>

def parse_manifest(xml_text: str) -> Manifest
def required_target_sdk(rules_text: str, today: datetime.date) -> tuple[int, datetime.date]   # (level, in force since)
def read_permission_list(text: str) -> list[str]
def manifest_problems(m: Manifest, *, version_name: str, version_code: str, catalog_target_sdk: str,
                      required_sdk: int, required_since: datetime.date, permissions: list[str]) -> list[str]
```

- [ ] **Step 1: Write the failing tests**

  Create `release/mobile/tests/test_android_manifest_checks.py`:

```python
"""Tests for the manifest and target-SDK checks of release/mobile/check_android_bundle.py (plan 3H).

Run: python3 -m unittest discover -s release/mobile/tests -t release/mobile/tests -v
"""
from __future__ import annotations

import datetime
import sys
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO / "release" / "mobile"))
import check_android_bundle as cab  # noqa: E402

ANDROID = "http://schemas.android.com/apk/res/android"
PERMS = ["android.permission.CAMERA", "android.permission.INTERNET"]
RULES = "# comment\n\n2024-08-31 34\n2025-08-31 35\n2026-08-31 36\n"
SINCE = datetime.date(2026, 8, 31)


def manifest_xml(package="com.shellx.prod", code="105", name="1.2.3", min_sdk="26", target="36",
                 app='android:allowBackup="false"', permissions=PERMS, activities=("com.shellx.app.MainActivity",)):
    perms = "".join('<uses-permission android:name="%s"/>' % p for p in permissions)
    acts = "".join('<activity android:name="%s" android:exported="true"/>' % a for a in activities)
    return ('<manifest xmlns:android="%s" android:versionCode="%s" android:versionName="%s" package="%s">'
            '<uses-sdk android:minSdkVersion="%s" android:targetSdkVersion="%s"/>%s<application %s>%s</application>'
            '</manifest>' % (ANDROID, code, name, package, min_sdk, target, perms, app, acts))


def problems(xml=None, **overrides):
    expected = dict(version_name="1.2.3", version_code="105", catalog_target_sdk="36", required_sdk=36,
                    required_since=SINCE, permissions=PERMS)
    expected.update(overrides)
    return cab.manifest_problems(cab.parse_manifest(xml or manifest_xml()), **expected)


def has(found, text):
    return any(text in p for p in found)


class PlayRuleTableTest(unittest.TestCase):
    def test_rules_pick_the_newest_rule_in_force(self):
        self.assertEqual((36, SINCE), cab.required_target_sdk(RULES, datetime.date(2026, 11, 7)))
        self.assertEqual((36, SINCE), cab.required_target_sdk(RULES, datetime.date(2026, 8, 31)))
        self.assertEqual(35, cab.required_target_sdk(RULES, datetime.date(2026, 8, 30))[0])
        self.assertEqual(36, cab.required_target_sdk(RULES, datetime.date(2027, 8, 31))[0])

    def test_rules_refuse_a_stale_table(self):
        with self.assertRaises(cab.RuleTableError) as caught:
            cab.required_target_sdk(RULES, datetime.date(2027, 9, 1))
        self.assertIn("is from 2026-08-31, more than 365 days ago", str(caught.exception))
        self.assertIn("https://developer.android.com/google/play/requirements/target-sdk", str(caught.exception))

    def test_rules_refuse_a_day_before_every_rule(self):
        with self.assertRaises(cab.RuleTableError) as caught:
            cab.required_target_sdk(RULES, datetime.date(2020, 1, 1))
        self.assertIn("has no rule in force on 2020-01-01", str(caught.exception))

    def test_rules_refuse_a_malformed_line(self):
        for line in ("2026-13-01 36", "2026-08-31", "2026-08-31 thirty-six"):
            with self.assertRaises(cab.RuleTableError) as caught:
                cab.required_target_sdk("2025-08-31 35\n" + line + "\n", datetime.date(2026, 1, 1))
            self.assertIn("android-play-target-sdk.txt line 2", str(caught.exception))

    def test_the_real_table_requires_36_on_2026_11_07(self):
        text = (REPO / "release/mobile/android-play-target-sdk.txt").read_text(encoding="utf-8")
        self.assertEqual((36, SINCE), cab.required_target_sdk(text, datetime.date(2026, 11, 7)))


class ManifestTest(unittest.TestCase):
    def test_parses_the_manifest_bundletool_prints(self):
        m = cab.parse_manifest(manifest_xml(app='android:allowBackup="false" android:label="@string/app_name"'))
        self.assertEqual(("com.shellx.prod", "105", "1.2.3", "26", "36"),
                         (m.package, m.version_code, m.version_name, m.min_sdk, m.target_sdk))
        self.assertEqual("false", m.application["allowBackup"])
        self.assertEqual(tuple(PERMS), m.permissions)
        self.assertEqual(("com.shellx.app.MainActivity",), m.activities)

    def test_the_release_manifest_passes(self):
        self.assertEqual([], problems())

    def test_refuses_another_application_id(self):
        self.assertIn("application id is com.shellx.dev, expected com.shellx.prod",
                      problems(manifest_xml(package="com.shellx.dev")))

    def test_refuses_versions_unlike_version_properties(self):
        found = problems(manifest_xml(code="104", name="1.2.2"))
        self.assertIn("versionCode is 104, shellx-android/version.properties says 105", found)
        self.assertIn("versionName is 1.2.2, shellx-android/version.properties says 1.2.3", found)

    def test_refuses_a_min_sdk_other_than_26(self):
        self.assertIn("minSdkVersion is 24, expected 26", problems(manifest_xml(min_sdk="24")))

    def test_refuses_a_target_sdk_below_play_or_unlike_the_catalog(self):
        found = problems(manifest_xml(target="35"))
        self.assertIn("targetSdkVersion is 35, the version catalog's androidTargetSdk is 36", found)
        self.assertTrue(has(found, "targetSdkVersion 35 is below 36, which Google Play requires since 2026-08-31"))
        self.assertEqual([], problems(manifest_xml(target="37"), catalog_target_sdk="37"))

    def test_refuses_debuggable_test_only_cleartext_and_backup(self):
        app = ('android:debuggable="true" android:testOnly="true" android:usesCleartextTraffic="true" '
               'android:allowBackup="true"')
        found = problems(manifest_xml(app=app))
        for text in ("android:debuggable is true", "android:testOnly is true",
                     "android:usesCleartextTraffic is true", "android:allowBackup is not false"):
            self.assertTrue(has(found, text), text)
        self.assertTrue(has(problems(manifest_xml(app="")), "android:allowBackup is not false"))

    def test_refuses_debug_only_activities(self):
        found = problems(manifest_xml(activities=("com.shellx.app.MainActivity", "androidx.activity.ComponentActivity")))
        self.assertIn("declares the debug-only activity androidx.activity.ComponentActivity", found)

    def test_permissions_must_match_the_list_exactly(self):
        found = problems(manifest_xml(permissions=["android.permission.INTERNET", "android.permission.READ_CONTACTS"]))
        self.assertTrue(has(found, "requests android.permission.READ_CONTACTS, which release/mobile/android-permissions.txt does not list"))
        self.assertTrue(has(found, "release/mobile/android-permissions.txt lists android.permission.CAMERA, which the bundle does not request"))

    def test_never_allowed_permissions_are_refused_even_when_listed(self):
        never = ["android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS", "com.google.android.gms.permission.AD_ID"]
        found = problems(manifest_xml(permissions=PERMS + never), permissions=PERMS + never)
        self.assertTrue(has(found, "REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, which ShellX never ships (S3 §7.4c)"))
        self.assertTrue(has(found, "AD_ID, which ShellX never ships (the Advertising ID declaration says no)"))

    def test_the_real_permission_list_is_well_formed(self):
        names = cab.read_permission_list((REPO / "release/mobile/android-permissions.txt").read_text(encoding="utf-8"))
        self.assertIn("android.permission.INTERNET", names)
        self.assertEqual(sorted(set(names)), names)
        for never in cab.NEVER_ALLOWED_PERMISSIONS:
            self.assertNotIn(never, names)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run them to see them fail**

  Run: `python3 -m unittest discover -s release/mobile/tests -t release/mobile/tests -v`

  Expected: `FAILED (errors=1)`, with `ModuleNotFoundError: No module named 'check_android_bundle'`.

- [ ] **Step 3: Commit the failing tests**

  ```bash
  git add release/mobile/tests/test_android_manifest_checks.py
  git commit -m "test(release): Android release checks for the manifest, Play's target API rule and permissions"
  ```

- [ ] **Step 4: Write the two data files**

  `release/mobile/android-play-target-sdk.txt`, exactly (append a line when Task 0 Step 5 found a newer rule in force):

```text
# Google Play's target API level rule for new apps and app updates (phones). Source:
# https://developer.android.com/google/play/requirements/target-sdk
# Each line: <day the rule applies from, YYYY-MM-DD> <minimum targetSdkVersion>
# Google raises the level about once a year (late August). release/mobile/android.sh refuses to build when the
# newest line is more than 365 days old: read the page above and add the new rule here.
2024-08-31 34
2025-08-31 35
2026-08-31 36
```

  `release/mobile/android-permissions.txt`, exactly (Task 4 Step 7 may adjust it by its rules):

```text
# Every permission the release build of the ShellX Android app requests, exactly (release/mobile/android.sh checks
# the bundle against this list). A change here changes the Data safety answers or needs a Play declaration:
# update release/mobile/README.md ("Google Play: Data safety") in the same commit. One name per line, sorted.
android.permission.ACCESS_NETWORK_STATE                    # network changes (S3 §7.3); Firebase Cloud Messaging
android.permission.CAMERA                                  # pairing QR code (CameraX); images never leave the phone
android.permission.INTERNET                                # relay.shellx.pro and Google services
android.permission.POST_NOTIFICATIONS                      # "Needs you" notifications on Android 13 and later
android.permission.RECORD_AUDIO                            # hold-to-talk voice input (SpeechRecognizer)
android.permission.WAKE_LOCK                               # Firebase Cloud Messaging
com.google.android.c2dm.permission.RECEIVE                 # Firebase Cloud Messaging
com.shellx.prod.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION   # AndroidX Core, signature level: this app only
```

- [ ] **Step 5: Implement the manifest part of `release/mobile/check_android_bundle.py`**

  Standard library only; the file starts with `#!/usr/bin/env python3`, a docstring naming plan 3H, and `from __future__ import annotations`. Behaviour, beyond what the tests pin:
  - `parse_manifest` reads the XML that `bundletool dump manifest` prints, with `xml.etree.ElementTree`. A missing attribute is `""`.
  - `required_target_sdk`: each non-blank line, after cutting a `#` comment, is `<YYYY-MM-DD> <int>` (`datetime.date.fromisoformat`); otherwise `RuleTableError('release/mobile/android-play-target-sdk.txt line <n>: expected "<YYYY-MM-DD> <api level>", got "<stripped line>"')`. With no line on or before `today`: `RuleTableError("release/mobile/android-play-target-sdk.txt has no rule in force on <today>")`. When `today` is more than 365 days after the newest line: `RuleTableError("the newest rule in release/mobile/android-play-target-sdk.txt is from <date>, more than 365 days ago: read https://developer.android.com/google/play/requirements/target-sdk and add this year's line")`. Otherwise the newest line on or before `today`.
  - `read_permission_list`: one name per line, `#` comments and blank lines dropped, file order kept.
  - `NEVER_ALLOWED_PERMISSIONS = {"android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS": "S3 §7.4c", "com.google.android.gms.permission.AD_ID": "the Advertising ID declaration says no"}`.
  - `manifest_problems` returns, in this order, one message per problem:

    | Check | Message |
    | --- | --- |
    | package | `application id is <x>, expected com.shellx.prod` |
    | versionCode | `versionCode is <x>, shellx-android/version.properties says <y>` |
    | versionName | `versionName is <x>, shellx-android/version.properties says <y>` |
    | minSdkVersion | `minSdkVersion is <x>, expected 26` |
    | targetSdkVersion vs catalog | `targetSdkVersion is <x>, the version catalog's androidTargetSdk is <y>` |
    | targetSdkVersion vs Play (not a number, or below) | `targetSdkVersion <x> is below <n>, which Google Play requires since <date> (release/mobile/android-play-target-sdk.txt)` |
    | `debuggable`, `testOnly`, `usesCleartextTraffic` equal to `true` | `android:<attr> is true` |
    | `allowBackup` other than `false` (missing included) | `android:allowBackup is not false (S3 §7.3: nothing is backed up)` |
    | each activity in `DEBUG_ONLY_ACTIVITIES` | `declares the debug-only activity <name>` |
    | each requested permission in `NEVER_ALLOWED_PERMISSIONS` (whether listed or not) | `requests <p>, which ShellX never ships (<reason>)` |
    | each other requested permission not in the list | `requests <p>, which release/mobile/android-permissions.txt does not list (a new permission changes the Data safety answers or needs a Play declaration)` |
    | each listed permission not requested | `release/mobile/android-permissions.txt lists <p>, which the bundle does not request: remove it from the list` |

- [ ] **Step 6: Run the tests to see them pass**

  Run: `python3 -m unittest discover -s release/mobile/tests -t release/mobile/tests -v && /usr/bin/python3 -m unittest discover -s release/mobile/tests -t release/mobile/tests`

  Expected: `Ran 16 tests`, `OK`, twice.

- [ ] **Step 7: Commit**

  ```bash
  git add release/mobile/check_android_bundle.py release/mobile/android-play-target-sdk.txt release/mobile/android-permissions.txt
  git commit -m "feat(release): check the Android release manifest, Play's target API rule and the permission list"
  ```

---

### Task 2: Bundle checker, part 2 — native code, debug-only code, R8 mapping, Firebase, the Google web client id, and the command line

**Files:**
- Modify: `release/mobile/check_android_bundle.py`
- Test: `release/mobile/tests/test_android_bundle_checks.py`

**Interfaces:**
- Consumes: Task 1's module.
- Produces:

```python
MAPPING_ENTRY = "BUNDLE-METADATA/com.android.tools.build.obfuscation/proguard.map"
DEBUG_ONLY_PACKAGES: tuple[str, ...]; DEBUG_ONLY_ALLOWED: tuple[str, ...]; DEBUG_ONLY_NAMES: tuple[str, ...]
FORBIDDEN_SDKS: tuple[str, ...]
def elf_problems(entry: str, data: bytes) -> list[str]
def debug_only_hits(dex: dict[str, bytes], mapping_text: str) -> list[str]          # sorted, unique
def lockfile_problems(text: str) -> list[str]
def google_services_app_id(text: str) -> tuple[str | None, list[str]]                # (app id of com.shellx.prod, problems)
def google_web_client_problems(oauth_xml: str, ledger_text: str | None) -> tuple[str | None, list[str]]
def main(argv: list[str] | None = None) -> int
```

  Command line (Task 3 calls it from the repository root, with repository-relative paths, so messages name files that way):

  ```
  python3 -I release/mobile/check_android_bundle.py sources --google-services <json> --google-oauth <xml>
          [--rollout-ledger <md>] [--lockfile <gradle.lockfile>]
  python3 -I release/mobile/check_android_bundle.py bundle --google-services <json> --google-oauth <xml>
          [--rollout-ledger <md>] [--lockfile <gradle.lockfile>] [--mapping <mapping.txt>]
          --aab <file.aab> --manifest-xml <file> --bundle-config <file> --version-name <x.y.z> --version-code <n>
          --catalog-target-sdk <n> --play-rules <file> --permissions <file> --today <YYYY-MM-DD>
  ```

  Each problem prints `violation: <message>` on stdout and the exit status is 1. On success `sources` prints `source checks passed: Firebase app <id>, Google web client <id>` and `bundle` prints one line, `bundle checks passed: com.shellx.prod <name> (<code>), target SDK <t> (Google Play needs <n> since <date>), <k> permissions, native code: <native>, R8 mapping <bytes> bytes`; both exit 0. `<native>` is `none` or `<n> libraries 16 KB aligned`. Usage errors exit 2 (argparse).

- [ ] **Step 1: Write the failing tests**

  Create `release/mobile/tests/test_android_bundle_checks.py`:

```python
"""Tests for the bundle, source and command-line checks of release/mobile/check_android_bundle.py (plan 3H).

Run: python3 -m unittest discover -s release/mobile/tests -t release/mobile/tests -v
"""
from __future__ import annotations

import json
import struct
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO / "release" / "mobile"))
import check_android_bundle as cab  # noqa: E402

LOAD, RELRO = 1, 0x6474E552
APP_ID = "1:111111111111:android:2222222222222222"
WEB_ID = "123456789012-abcdefghij0123456789abcdefghij01.apps.googleusercontent.com"
PLACEHOLDER = "0-shellx-placeholder.apps.googleusercontent.com"
PERMS = ["android.permission.CAMERA", "android.permission.INTERNET"]
MAPPING = (b"# compiler: R8\ncom.shellx.app.MainActivity -> com.shellx.app.MainActivity:\n"
           b"com.shellx.core.demo.DemoScript -> a.a:\n")
CONFIG_16K = '{"optimizations": {"uncompressNativeLibraries": {"enabled": true, "alignment": "PAGE_ALIGNMENT_16K"}}}'
GOOGLE_SERVICES = json.dumps({"project_info": {"project_id": "shellxpro"}, "client": [
    {"client_info": {"mobilesdk_app_id": "1:111111111111:android:3333333333333333",
                     "android_client_info": {"package_name": "com.shellx.dev"}}},
    {"client_info": {"mobilesdk_app_id": APP_ID, "android_client_info": {"package_name": "com.shellx.prod"}}}]})
LEDGER_ROW = "| 6 | ShellX Web (Android sign-in) | Web application | — | — | %s |\n"
MANIFEST = ('<manifest xmlns:android="http://schemas.android.com/apk/res/android" android:versionCode="105" '
            'android:versionName="1.2.3" package="com.shellx.prod"><uses-sdk android:minSdkVersion="26" '
            'android:targetSdkVersion="36"/><uses-permission android:name="android.permission.CAMERA"/>'
            '<uses-permission android:name="android.permission.INTERNET"/><application android:allowBackup="false">'
            '<activity android:name="com.shellx.app.MainActivity"/></application></manifest>')


def oauth_xml(value):
    return ('<?xml version="1.0" encoding="utf-8"?>\n<resources>\n    <string name="google_web_client_id" '
            'translatable="false">%s</string>\n</resources>\n' % value)


def elf64(segments):
    """A little-endian ELF64 header and program headers; segments are (p_type, p_vaddr, p_memsz, p_align)."""
    head = bytearray(64)
    head[0:7] = b"\x7fELF\x02\x01\x01"
    struct.pack_into("<HHIQQQIHHHHHH", head, 16, 3, 183, 1, 0, 64, 0, 0, 64, 56, len(segments), 0, 0, 0)
    return bytes(head) + b"".join(struct.pack("<IIQQQQQQ", t, 0, 0, v, v, m, m, a) for t, v, m, a in segments)


def elf32(segments):
    head = bytearray(52)
    head[0:7] = b"\x7fELF\x01\x01\x01"
    struct.pack_into("<HHIIIIIHHHHHH", head, 16, 3, 40, 1, 0, 52, 0, 0, 52, 32, len(segments), 0, 0, 0)
    return bytes(head) + b"".join(struct.pack("<IIIIIIII", t, 0, v, v, m, m, 0, a) for t, v, m, a in segments)


ALIGNED = elf64([(LOAD, 0, 0x680, 0x4000), (LOAD, 0x4680, 0x1D8, 0x4000)])
FOUR_K = elf64([(LOAD, 0, 0x680, 0x1000), (LOAD, 0x1680, 0x1D8, 0x1000)])


def make_aab(folder, extra=None, mapping=MAPPING, dex=b"dex\n035\x00Lcom/shellx/app/MainActivity;",
             resources=b"\x0a\x20" + APP_ID.encode() + b"\x12" + WEB_ID.encode() + b"\x1a\x0bic_google_g"
             + b"\x22\x14third_party_licenses\x2a\x1cthird_party_license_metadata"):
    entries = {"base/manifest/AndroidManifest.xml": b"proto", "base/resources.pb": resources}
    if dex is not None:
        entries["base/dex/classes.dex"] = dex
    if mapping is not None:
        entries[cab.MAPPING_ENTRY] = mapping
    entries.update(extra or {})
    path = Path(folder) / "app-release.aab"
    with zipfile.ZipFile(path, "w") as z:
        for name, data in entries.items():
            z.writestr(name, data)
    return path


class NativeLibraryTest(unittest.TestCase):
    def test_every_library_needs_16_kb_load_alignment(self):
        self.assertEqual([], cab.elf_problems("base/lib/arm64-v8a/libok.so", ALIGNED))
        self.assertEqual([], cab.elf_problems("base/lib/armeabi-v7a/libok.so", elf32([(LOAD, 0, 0x680, 0x4000)])))
        for entry, data in (("base/lib/arm64-v8a/libold.so", FOUR_K), ("base/lib/x86_64/libold.so", FOUR_K),
                            ("base/lib/armeabi-v7a/libold.so", elf32([(LOAD, 0, 0x680, 0x1000)]))):
            self.assertEqual(["%s: a LOAD segment is aligned to 4096 bytes; Google Play needs 16 KB (16384)" % entry],
                             cab.elf_problems(entry, data))

    def test_relro_examples_of_the_android_guide(self):
        entry = "base/lib/arm64-v8a/libx.so"
        example1 = elf64([(LOAD, 0, 0xCFAF0, 0x4000), (LOAD, 0xDFAF0, 0x4510, 0x4000), (RELRO, 0xDFAF0, 0x1510, 1)])
        example2 = elf64([(LOAD, 0, 0xCFAF0, 0x4000), (LOAD, 0xDFAF0, 0x3510, 0x4000), (RELRO, 0xDFAF0, 0x510, 1)])
        example4 = elf64([(LOAD, 0, 0x680, 0x4000), (LOAD, 0x4680, 0x980, 0x4000), (RELRO, 0x4680, 0x980, 1)])
        self.assertEqual(["%s: GNU_RELRO ends at 0xe1000, inside a 16 KB page that also holds writable data" % entry],
                         cab.elf_problems(entry, example1))
        self.assertEqual([], cab.elf_problems(entry, example2))
        self.assertEqual([], cab.elf_problems(entry, ALIGNED))  # example 3: no GNU_RELRO
        self.assertEqual([], cab.elf_problems(entry, example4))

    def test_a_library_that_is_not_elf_is_refused(self):
        self.assertEqual(["base/lib/arm64-v8a/libz.so: not an ELF shared library"],
                         cab.elf_problems("base/lib/arm64-v8a/libz.so", b"not an elf file at all, " * 3))


class DebugOnlyCodeTest(unittest.TestCase):
    def test_debug_only_code_is_found_by_package_and_by_name(self):
        dex = {"base/dex/classes.dex": b"..Lorg/robolectric/RuntimeEnvironment;..",
               "base/dex/classes2.dex": b"..InMemorySecretStore..Landroidx/compose/ui/tooling/PreviewActivity;.."}
        mapping = "org.junit.Assert -> a.b:\n    void fail() -> a\ncom.shellx.core.testing.ManualClock -> c.d:\n"
        hits = cab.debug_only_hits(dex, mapping)
        for hit in ("org.junit.Assert (R8 mapping)", "com.shellx.core.testing.ManualClock (R8 mapping)",
                    "Lorg/robolectric/ (base/dex/classes.dex)", "InMemorySecretStore (base/dex/classes2.dex)",
                    "Landroidx/compose/ui/tooling/ (base/dex/classes2.dex)"):
            self.assertIn(hit, hits)

    def test_the_demo_and_compose_preview_annotations_ship(self):
        dex = {"base/dex/classes.dex": b"..Landroidx/compose/ui/tooling/preview/Preview;..Lcom/shellx/core/demo/FakeMac;.."}
        mapping = ("com.shellx.core.demo.FakeMac -> e.f:\ncom.shellx.core.demo.DemoRelay -> e.g:\n"
                   "com.shellx.core.demo.DemoSecretStore -> e.h:\nandroidx.compose.ui.tooling.preview.Preview -> i.j:\n")
        self.assertEqual([], cab.debug_only_hits(dex, mapping))


class SourceFilesTest(unittest.TestCase):
    def test_release_classpath_has_no_analytics_ads_or_crash_sdk(self):
        text = ("# comment\n"
                "com.google.firebase:firebase-messaging:24.1.0=debugRuntimeClasspath,releaseRuntimeClasspath\n"
                "com.google.firebase:firebase-analytics:22.0.0=releaseRuntimeClasspath\n"
                "com.google.android.gms:play-services-measurement-api:22.0.0=debugRuntimeClasspath,releaseRuntimeClasspath\n"
                "com.google.firebase:firebase-crashlytics:19.0.0=debugUnitTestRuntimeClasspath\n"
                "empty=\n")
        found = cab.lockfile_problems(text)
        self.assertEqual(2, len(found))
        self.assertTrue(found[0].startswith("com.google.firebase:firebase-analytics:22.0.0 is on the release classpath"))
        self.assertTrue(found[1].startswith("com.google.android.gms:play-services-measurement-api:22.0.0 is on the release"))

    def test_firebase_must_be_configured_for_com_shellx_prod_of_shellxpro(self):
        self.assertEqual((APP_ID, []), cab.google_services_app_id(GOOGLE_SERVICES))
        app_id, found = cab.google_services_app_id(json.dumps({"project_info": {"project_id": "elsewhere"}, "client": []}))
        self.assertIsNone(app_id)
        self.assertIn("google-services.json is for project elsewhere, expected shellxpro", found)
        self.assertIn("google-services.json has no client for com.shellx.prod", found)
        self.assertEqual((None, ["google-services.json is not valid JSON"]), cab.google_services_app_id("{"))

    def test_the_web_client_id_must_be_real_and_match_the_rollout_ledger(self):
        self.assertEqual((WEB_ID, []), cab.google_web_client_problems(oauth_xml(WEB_ID), None))
        value, found = cab.google_web_client_problems(oauth_xml(PLACEHOLDER), None)
        self.assertIsNone(value)
        self.assertTrue(found[0].startswith('google_web_client_id is "%s", not a Google OAuth client id' % PLACEHOLDER))
        other = "999999999999-zzzzzzzzzz0123456789abcdefghij01.apps.googleusercontent.com"
        value, found = cab.google_web_client_problems(oauth_xml(WEB_ID), "# Ledger\n" + LEDGER_ROW % other)
        self.assertEqual(["google_web_client_id %s differs from the Web client id %s in "
                          "docs/superpowers/ledgers/shellx-signin-rollout.md (client \"ShellX Web (Android sign-in)\")"
                          % (WEB_ID, other)], found)
        self.assertEqual((WEB_ID, []), cab.google_web_client_problems(oauth_xml(WEB_ID), LEDGER_ROW % WEB_ID))
        self.assertEqual((WEB_ID, []), cab.google_web_client_problems(oauth_xml(WEB_ID), LEDGER_ROW % ("`%s`" % WEB_ID)))
        self.assertEqual((WEB_ID, []), cab.google_web_client_problems(oauth_xml(WEB_ID), LEDGER_ROW % ""))
        self.assertEqual((WEB_ID, []), cab.google_web_client_problems(oauth_xml(WEB_ID), LEDGER_ROW % "pending (1D)"))
        self.assertEqual((None, ["google_oauth.xml has no google_web_client_id string"]),
                         cab.google_web_client_problems("<resources/>", None))


class CommandLineTest(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp())
        self.addCleanup(lambda: subprocess.run(["rm", "-rf", str(self.dir)]))
        files = {"manifest.xml": MANIFEST, "config.json": CONFIG_16K, "rules.txt": "2026-08-31 36\n",
                 "permissions.txt": "\n".join(PERMS) + "\n", "google-services.json": GOOGLE_SERVICES,
                 "google_oauth.xml": oauth_xml(WEB_ID)}
        for name, text in files.items():
            (self.dir / name).write_text(text, encoding="utf-8")
        (self.dir / "mapping.txt").write_bytes(MAPPING)

    def run_cli(self, command, *extra):
        d = self.dir
        args = [sys.executable, "-I", str(REPO / "release/mobile/check_android_bundle.py"), command,
                "--google-services", str(d / "google-services.json"), "--google-oauth", str(d / "google_oauth.xml")]
        if command == "bundle":
            args += ["--manifest-xml", str(d / "manifest.xml"), "--bundle-config", str(d / "config.json"),
                     "--version-name", "1.2.3", "--version-code", "105", "--catalog-target-sdk", "36",
                     "--play-rules", str(d / "rules.txt"), "--permissions", str(d / "permissions.txt"),
                     "--today", "2026-11-07"]
        return subprocess.run(args + list(extra), capture_output=True, text=True)

    def test_a_good_bundle_passes_with_a_summary(self):
        aab = make_aab(self.dir, {"base/lib/arm64-v8a/libok.so": ALIGNED, "base/lib/armeabi-v7a/libok.so": elf32([(LOAD, 0, 0x680, 0x4000)])})
        r = self.run_cli("bundle", "--aab", str(aab), "--mapping", str(self.dir / "mapping.txt"))
        self.assertEqual(0, r.returncode, r.stdout + r.stderr)
        self.assertEqual("bundle checks passed: com.shellx.prod 1.2.3 (105), target SDK 36 (Google Play needs 36 since "
                         "2026-08-31), 2 permissions, native code: 2 libraries 16 KB aligned, R8 mapping %d bytes\n"
                         % len(MAPPING), r.stdout)

    def test_violations_are_printed_and_exit_1(self):
        aab = make_aab(self.dir, {"base/lib/arm64-v8a/libold.so": FOUR_K})
        (self.dir / "config.json").write_text("{}", encoding="utf-8")
        (self.dir / "mapping.txt").write_bytes(MAPPING + b"extra -> x:\n")
        r = self.run_cli("bundle", "--aab", str(aab), "--mapping", str(self.dir / "mapping.txt"))
        self.assertEqual(1, r.returncode)
        lines = r.stdout.splitlines()
        self.assertTrue(all(line.startswith("violation: ") for line in lines), r.stdout)
        self.assertIn("violation: base/lib/arm64-v8a/libold.so: a LOAD segment is aligned to 4096 bytes; Google Play "
                      "needs 16 KB (16384)", lines)
        self.assertIn("violation: the bundle has native libraries but its config asks for no zip alignment; it must "
                      "ask for PAGE_ALIGNMENT_16K (Android Gradle plugin 8.5.1 or later)", lines)
        self.assertIn("violation: the bundle's R8 mapping differs from %s" % (self.dir / "mapping.txt"), lines)

    def test_without_a_mapping_file_the_embedded_mapping_is_scanned(self):
        aab = make_aab(self.dir, mapping=MAPPING + b"org.junit.Assert -> a:\n")
        r = self.run_cli("bundle", "--aab", str(aab))
        self.assertEqual(1, r.returncode)
        self.assertIn("violation: release contains debug-only code: org.junit.Assert (R8 mapping)", r.stdout)

    def test_a_bundle_without_dex_mapping_or_configured_ids_is_refused(self):
        aab = make_aab(self.dir, mapping=None, dex=None, resources=b"\x0a\x00")
        r = self.run_cli("bundle", "--aab", str(aab))
        self.assertEqual(1, r.returncode)
        for text in ("the bundle has no dex files (base/dex/classes*.dex)",
                     "the bundle has no R8 mapping (%s)" % cab.MAPPING_ENTRY,
                     "the bundle's resources do not hold Google's \"G\" (drawable/ic_google_g)",
                     "the bundle's resources do not hold the Firebase app id %s" % APP_ID,
                     "the bundle's resources do not hold google_web_client_id %s" % WEB_ID):
            self.assertIn(text, r.stdout)

    def test_sources_checks_the_source_files_only(self):
        lockfile = self.dir / "gradle.lockfile"
        lockfile.write_text("com.google.firebase:firebase-messaging:24.1.0=releaseRuntimeClasspath\nempty=\n")
        r = self.run_cli("sources", "--lockfile", str(lockfile))
        self.assertEqual(0, r.returncode, r.stdout + r.stderr)
        self.assertEqual("source checks passed: Firebase app %s, Google web client %s\n" % (APP_ID, WEB_ID), r.stdout)
        (self.dir / "google_oauth.xml").write_text(oauth_xml(PLACEHOLDER), encoding="utf-8")
        (self.dir / "google-services.json").unlink()
        r = self.run_cli("sources")
        self.assertEqual(1, r.returncode)
        self.assertIn("violation: missing %s" % (self.dir / "google-services.json"), r.stdout)
        self.assertIn('violation: google_web_client_id is "%s", not a Google OAuth client id' % PLACEHOLDER, r.stdout)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run them to see them fail**

  Run: `python3 -m unittest discover -s release/mobile/tests -t release/mobile/tests`

  Expected: `FAILED`; the new tests error with `AttributeError: module 'check_android_bundle' has no attribute …` or fail because the command line has no `bundle` or `sources` command yet. Task 1's 16 tests still pass.

- [ ] **Step 3: Commit the failing tests**

  ```bash
  git add release/mobile/tests/test_android_bundle_checks.py
  git commit -m "test(release): Android bundle checks for native code, debug-only code, mapping, Firebase and the web client id"
  ```

- [ ] **Step 4: Implement**

  - **Constants**, exactly:
    - `DEBUG_ONLY_PACKAGES = ("org.junit.", "junit.", "org.robolectric.", "com.github.takahirom.roborazzi.", "androidx.test.", "androidx.compose.ui.test.", "androidx.compose.ui.tooling.", "kotlinx.coroutines.test.", "kotlin.test.", "mockwebserver3.", "okhttp3.mockwebserver.", "okhttp3.logging.", "leakcanary.", "com.shellx.core.testing.", "com.shellx.app.testing.", "com.shellx.app.screenshots.", "com.shellx.app.debug.")`
    - `DEBUG_ONLY_ALLOWED = ("androidx.compose.ui.tooling.preview.",)`
    - `DEBUG_ONLY_NAMES = ("FakeRelayAccount", "FakeIdentityProvider", "InMemorySecretStore", "FakeTranscriber", "FakeVoicePermissions", "SHELLX_DEMO")` — the iPhone's list (plan 1C) and plan 3C's test kit names. The demo (`com.shellx.core.demo`: `FakeMac`, `DemoScript`, `DemoRelay`, `DemoSecretStore`, `DemoEnvironment`) ships and is never matched.
    - `FORBIDDEN_SDKS = ("com.google.firebase:firebase-analytics", "com.google.firebase:firebase-crashlytics", "com.google.firebase:firebase-perf", "com.google.firebase:firebase-inappmessaging", "com.google.android.gms:play-services-measurement", "com.google.android.gms:play-services-ads", "com.google.android.gms:play-services-analytics", "com.google.android.gms:play-services-appset")`, matched as prefixes of `group:artifact`.
    - `CLIENT_ID_RE = re.compile(r"^[0-9]+-[a-z0-9]+\.apps\.googleusercontent\.com$")` (plan 1D's rule); the ledger row name `ShellX Web (Android sign-in)`.
  - **`elf_problems`** (Google's 16 KB guidance, https://developer.android.com/guide/practices/page-sizes). Not an ELF file (`\x7fELF`, class byte 1 or 2, data byte 1 or 2, readable headers): `<entry>: not an ELF shared library`. Program headers, by `e_ident[4]` (endianness from `e_ident[5]`):

    | Class | `e_phoff` | `e_phentsize`, `e_phnum` | Header fields used |
    | --- | --- | --- | --- |
    | 64-bit | `Q` at 32 | `HH` at 54 | `IIQQQQQQ`: type 0, vaddr 3, memsz 6, align 7 |
    | 32-bit | `I` at 28 | `HH` at 42 | `IIIIIIII`: type 0, vaddr 2, memsz 5, align 7 |

    - Any `PT_LOAD` (1) with `p_align < 0x4000`: one message, `<entry>: a LOAD segment is aligned to <align> bytes; Google Play needs 16 KB (16384)`.
    - Each `PT_GNU_RELRO` (`0x6474E552`) whose end (`vaddr + memsz`) is not a multiple of `0x4000` and is not also the end of the `PT_LOAD` that contains its start: `<entry>: GNU_RELRO ends at <hex end>, inside a 16 KB page that also holds writable data` (end written with `%#x`).
  - **`debug_only_hits`**:
    - In the mapping, a class line is a line that does not start with a space, a tab or `#` and contains ` -> `. Its original name (before ` -> `) is a hit when it starts with a `DEBUG_ONLY_PACKAGES` entry but no `DEBUG_ONLY_ALLOWED` entry, or when its simple name (after the last `.`, before any `$`) is in `DEBUG_ONLY_NAMES`. Hit text: `<original name> (R8 mapping)`.
    - In each dex blob, a package is a hit when its descriptor `L` + prefix with `.` → `/` occurs at a position that does not start an allowed descriptor (`Landroidx/compose/ui/tooling/preview/`). Hit text: `<descriptor> (<entry>)`. A name of `DEBUG_ONLY_NAMES` found anywhere in the bytes: `<name> (<entry>)`.
  - **`lockfile_problems`**: lines `group:artifact:version=conf1,conf2,…`; skip blank lines, `#` comments and `empty=`; a line whose configurations include `releaseRuntimeClasspath` and whose `group:artifact` starts with a `FORBIDDEN_SDKS` entry gives `<group:artifact:version> is on the release classpath: ShellX declares no analytics, advertising or crash reporting`, in file order.
  - **`google_services_app_id`**: invalid JSON → `(None, ["google-services.json is not valid JSON"])`. Messages: `google-services.json is for project <x>, expected shellxpro`; `google-services.json has no client for com.shellx.prod`. The id is the `client_info.mobilesdk_app_id` of the client whose `android_client_info.package_name` is `com.shellx.prod`; it is returned only when there is no problem.
  - **`google_web_client_problems`** (contracts §16): parse the XML; the value is the stripped text of `<string name="google_web_client_id">`. Messages: invalid XML → `google_oauth.xml is not valid XML`; no such string → `google_oauth.xml has no google_web_client_id string`; a value that does not match `CLIENT_ID_RE` (the placeholder included) → `google_web_client_id is "<value>", not a Google OAuth client id: fill it from docs/superpowers/ledgers/shellx-signin-rollout.md (client "ShellX Web (Android sign-in)", plan 1D)`. With ledger text: the table row whose second cell is exactly `ShellX Web (Android sign-in)` has its client id in the last cell, read with backticks and spaces stripped; a cell that is empty or starts with `pending` is ignored; any other cell that differs → `google_web_client_id <value> differs from the Web client id <ledger id> in docs/superpowers/ledgers/shellx-signin-rollout.md (client "ShellX Web (Android sign-in)")`. The value is returned only when there is no problem.
  - **`main`** (argparse with the two sub-commands): missing input files give `missing <path as given>`. Both commands run the source checks (Firebase file, OAuth file with the ledger when given, lockfile when given). `bundle` also:
    - reads the rule table, the permission list and the manifest, and runs `manifest_problems` (a `RuleTableError` becomes one violation);
    - opens the bundle as a zip (`<aab> is not an app bundle` when it cannot);
    - dex entries `^[^/]+/dex/classes\d*\.dex$` (none → `the bundle has no dex files (base/dex/classes*.dex)`);
    - native entries `^[^/]+/lib/<abi>/<name>.so$`, of every ABI, go through `elf_problems`: every `.so` must be 16 KB aligned, always. When there is any native library, the config text must hold `"alignment": "PAGE_ALIGNMENT_16K"` or `…_64K`, else `the bundle has native libraries but its config asks for <found value or no> zip alignment; it must ask for PAGE_ALIGNMENT_16K (Android Gradle plugin 8.5.1 or later)`;
    - `MAPPING_ENTRY` missing → `the bundle has no R8 mapping (BUNDLE-METADATA/com.android.tools.build.obfuscation/proguard.map)`; with `--mapping`: an empty file → `<path> is empty (did R8 run?)`, different bytes → `the bundle's R8 mapping differs from <path>`. The debug-only scan uses the `--mapping` file when given, else the embedded mapping; any hit → one violation `release contains debug-only code: <hit>, <hit>, …`;
    - the concatenated bytes of every `*/resources.pb` must contain the Firebase app id and the web client id (when those were found): `the bundle's resources do not hold the Firebase app id <id> (the google-services plugin did not run for release)`, `the bundle's resources do not hold google_web_client_id <id>`;
    - Google's "G" on the sign-in button (plan 3D Contract additions 10, like plan 1C's `ios.sh`). The app finds it by name (`getIdentifier("ic_google_g", "drawable", …)`), so the same `resources.pb` bytes must contain `ic_google_g` (a file path may be shortened, the name may not); otherwise `the bundle's resources do not hold Google's "G" (drawable/ic_google_g): plan 3D Task 9 Steps 7–9 (USER) are not done, or the resource shrinker dropped it (res/raw/keep_google_branding.xml)`.
  - End the file with `if __name__ == "__main__": sys.exit(main())`.

- [ ] **Step 5: Run the tests to see them pass**

  Run: `python3 -m unittest discover -s release/mobile/tests -t release/mobile/tests -v && /usr/bin/python3 -m unittest discover -s release/mobile/tests -t release/mobile/tests`

  Expected: `Ran 29 tests`, `OK`, twice.

- [ ] **Step 6: Commit**

  ```bash
  git add release/mobile/check_android_bundle.py
  git commit -m "feat(release): check native code, debug-only code, the R8 mapping, Firebase and the web client id of Android bundles"
  ```

---

### Task 3: `release/mobile/android.sh` — build, refuse, check, `--check-aab`, `--mark-uploaded`

**Files:**
- Create: `release/mobile/android.sh` (executable)
- Test: `release/mobile/tests/test_android_sh.py`

**Interfaces:**
- Consumes: Task 2's command line; plan 3A's `shellx-android/gradlew`, `version.properties`, `gradle/libs.versions.toml` key `androidTargetSdk`, `app/gradle.lockfile`, `scripts/shellx/check-android-license.sh`; contracts §16's `google_oauth.xml`.
- Produces (the README and Task 9 rely on these):
  - `release/mobile/android.sh` (build), `--check-aab <file.aab> [<mapping.txt>]`, `--mark-uploaded`, `-h|--help|help`;
  - `build/release/android/ShellX-<VERSION_NAME>-<VERSION_CODE>.aab`, `.mapping.txt`, `.source` (`<sha> clean`), `.uploaded` (`<UTC time> from <sha>`), and `build/release/android/logs/gradle-<name>-<YYYYmmdd-HHMMSS>.log`;
  - the stdout line `==> upload key: SHA-256 <fingerprint> (SHA-1 <fingerprint>)`.

- [ ] **Step 1: Write the failing tests**

  Create `release/mobile/tests/test_android_sh.py`:

```python
"""Tests for release/mobile/android.sh (plan 3H): gating, signature, outputs, --check-aab and --mark-uploaded.

Each test clones a throwaway repository from a bare origin. Gradle, bundletool, keytool, jarsigner and java are
fakes; curl and wget are fakes that record any call. The real bundle checker runs.
Run: python3 -m unittest discover -s release/mobile/tests -t release/mobile/tests -v
"""
from __future__ import annotations

import datetime
import json
import os
import shutil
import subprocess
import tempfile
import unittest
import zipfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
MOBILE = REPO / "release" / "mobile"
STORE_PW = 'st$re pw"=1'
KEY_PW = "k3y pw 'x'"
UPLOAD_SHA256 = ":".join(["15", "1C", "F3", "98"] + ["AB"] * 26 + ["5A", "06"])
UPLOAD_SHA1 = ":".join(["CD"] * 20)
OTHER_SHA256 = ":".join(["EE"] * 32)
APP_ID = "1:111111111111:android:2222222222222222"
WEB_ID = "123456789012-abcdefghij0123456789abcdefghij01.apps.googleusercontent.com"
MAPPING = (b"# compiler: R8\ncom.shellx.app.MainActivity -> com.shellx.app.MainActivity:\n"
           b"com.shellx.core.demo.DemoScript -> a.a:\n")
NAME = "ShellX-1.2.3-105"

FAKE_GRADLEW = """#!/usr/bin/env bash
# Fake Gradle wrapper: records its arguments and the key file, then writes the bundle and the R8 mapping.
set -eu
dir="$(cd "$(dirname "$0")" && pwd)"
{ printf 'args=%s\\n' "$*"; printf 'key=%s\\n' "${SHELLX_ANDROID_KEY_PROPERTIES:-}"; } >>"$FIXTURE_GRADLE_LOG"
mkdir -p "$dir/app/build/outputs/bundle/release" "$dir/app/build/outputs/mapping/release"
cp "$FIXTURE_AAB" "$dir/app/build/outputs/bundle/release/app-release.aab"
cp "$FIXTURE_MAPPING" "$dir/app/build/outputs/mapping/release/mapping.txt"
echo "BUILD SUCCESSFUL in 1s"
"""
FAKE_BUNDLETOOL = """#!/usr/bin/env bash
case "$1 ${2:-}" in
  "version "*) echo "${FAKE_BUNDLETOOL_VERSION:-1.18.3}" ;;
  "dump manifest") cat "$FIXTURE_MANIFEST" ;;
  "dump config") cat "$FIXTURE_CONFIG" ;;
  *) echo "fake bundletool: unexpected $*" >&2; exit 2 ;;
esac
"""
FAKE_KEYTOOL = """#!/usr/bin/env bash
# Fake keytool: -list needs the store password in SHELLX_STOREPASS; -printcert shows the signer of the bundle.
printf '%s\\n' "$*" >>"$FIXTURE_KEYTOOL_LOG"
case " $* " in
  *" -printcert "*)
    printf 'Signer #1:\\n\\nCertificate #1:\\nOwner: %s\\nCertificate fingerprints:\\n\\t SHA1: %s\\n\\t SHA256: %s\\n' \\
      "${FAKE_SIGNER_OWNER:-CN=ShellX Upload}" "$FIXTURE_UPLOAD_SHA1" "${FAKE_SIGNER_SHA256:-$FIXTURE_UPLOAD_SHA256}" ;;
  *" -list "*)
    if [ "${SHELLX_STOREPASS:-}" != "$FIXTURE_STORE_PW" ]; then
      echo "keytool error: java.io.IOException: keystore password was incorrect" >&2; exit 1
    fi
    printf 'Alias name: upload\\nCertificate fingerprints:\\n\\t SHA1: %s\\n\\t SHA256: %s\\n' \\
      "$FIXTURE_UPLOAD_SHA1" "$FIXTURE_UPLOAD_SHA256" ;;
  *) echo "fake keytool: unexpected $*" >&2; exit 2 ;;
esac
"""
FAKE_JARSIGNER = "#!/usr/bin/env bash\necho 'jar verified.'\n"
FAKE_JAVA = "#!/usr/bin/env bash\necho 'openjdk version \"17.0.9\" 2023-10-17' >&2\n"
FAKE_NETWORK = "#!/usr/bin/env bash\necho \"$(basename \"$0\") $*\" >>\"$FIXTURE_NETWORK_LOG\"\nexit 1\n"
FAKE_LICENCE = ("#!/usr/bin/env bash\nif [ -n \"${FAKE_LICENCE_FAIL:-}\" ]; then echo 'violation: x: y'; exit 1; fi\n"
                "echo 'check-android-license: ok'\n")


def write(path: Path, text: str, mode: int = 0o644) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    path.chmod(mode)
    return path


def permissions():
    lines = (MOBILE / "android-permissions.txt").read_text(encoding="utf-8").splitlines()
    return [line.split("#", 1)[0].strip() for line in lines if line.split("#", 1)[0].strip()]


def manifest_xml(debuggable=False):
    perms = "".join('<uses-permission android:name="%s"/>' % p for p in permissions())
    extra = ' android:debuggable="true"' if debuggable else ""
    return ('<manifest xmlns:android="http://schemas.android.com/apk/res/android" android:versionCode="105" '
            'android:versionName="1.2.3" package="com.shellx.prod"><uses-sdk android:minSdkVersion="26" '
            'android:targetSdkVersion="36"/>%s<application android:allowBackup="false"%s>'
            '<activity android:name="com.shellx.app.MainActivity" android:exported="true"/></application>'
            '</manifest>' % (perms, extra))


def oauth_xml(value):
    return ('<?xml version="1.0" encoding="utf-8"?>\n<resources>\n    <string name="google_web_client_id" '
            'translatable="false">%s</string>\n</resources>\n' % value)


class Fixture:
    def __init__(self, test: unittest.TestCase):
        self.tmp = Path(tempfile.mkdtemp(prefix="android-sh-"))
        test.addCleanup(shutil.rmtree, self.tmp, True)
        t = self.tmp
        self.home, self.tools, self.jdk, self.keys = t / "home", t / "tools", t / "jdk", t / "keys"
        self.home.mkdir()
        for name, text in (("bundletool", FAKE_BUNDLETOOL), ("curl", FAKE_NETWORK), ("wget", FAKE_NETWORK)):
            write(self.tools / name, text, 0o755)
        for name, text in (("java", FAKE_JAVA), ("keytool", FAKE_KEYTOOL), ("jarsigner", FAKE_JARSIGNER)):
            write(self.jdk / "bin" / name, text, 0o755)
        write(self.keys / "upload.jks", "not a real keystore\n")
        self.key_properties = write(self.keys / "key.properties", "storeFile=upload.jks\nstorePassword=%s\n"
                                    "keyAlias=upload\nkeyPassword=%s\n" % (STORE_PW, KEY_PW), 0o600)
        write(t / "manifest.xml", manifest_xml())
        write(t / "config.json", '{"optimizations": {"uncompressNativeLibraries": {"enabled": true}}}')
        (t / "mapping.txt").write_bytes(MAPPING)
        self.aab = t / "fixture.aab"
        with zipfile.ZipFile(self.aab, "w") as z:
            z.writestr("base/manifest/AndroidManifest.xml", b"proto")
            z.writestr("base/dex/classes.dex", b"dex\n035\x00Lcom/shellx/app/MainActivity;")
            z.writestr("base/resources.pb", b"\x0a\x20" + APP_ID.encode() + b"\x12" + WEB_ID.encode() + b"\x1a\x0bic_google_g"
                       + b"\x22\x14third_party_licenses\x2a\x1cthird_party_license_metadata")
            z.writestr("BUNDLE-METADATA/com.android.tools.build.obfuscation/proguard.map", MAPPING)
        self.repo = t / "repo"
        self.git_env = {"PATH": os.environ["PATH"], "HOME": str(self.home), "GIT_CONFIG_NOSYSTEM": "1",
                        "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@example.com",
                        "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@example.com"}
        self.git("init", "-q", "--bare", str(t / "origin.git"), cwd=t)
        self.git("clone", "-q", str(t / "origin.git"), str(self.repo), cwd=t)
        self.git("checkout", "-q", "-b", "develop")
        self.populate()
        self.commit_and_push("fixture")

    def git(self, *args, cwd=None):
        return subprocess.run(["git", *args], cwd=cwd or self.repo, env=self.git_env, check=True,
                              capture_output=True, text=True).stdout

    def populate(self):
        r = self.repo
        for name in ("android.sh", "check_android_bundle.py", "android-play-target-sdk.txt", "android-permissions.txt"):
            write(r / "release" / "mobile" / name, (MOBILE / name).read_text(encoding="utf-8"), 0o755)
        rules = r / "release" / "mobile" / "android-play-target-sdk.txt"   # a rule dated today: never stale (365 days)
        rules.write_text(rules.read_text(encoding="utf-8") + "%s 36\n" % datetime.date.today().isoformat(), encoding="utf-8")
        write(r / ".gitignore", "build/\n")
        write(r / "shellx-android/version.properties", "VERSION_NAME=1.2.3\nVERSION_CODE=105\n")
        write(r / "shellx-android/gradle/libs.versions.toml", '[versions]\nandroidTargetSdk = "36"\n')
        write(r / "shellx-android/gradlew", FAKE_GRADLEW, 0o755)
        write(r / "shellx-android/app/gradle.lockfile",
              "com.google.firebase:firebase-messaging:24.1.0=releaseRuntimeClasspath\nempty=\n")
        write(r / "shellx-android/app/src/release/google-services.json", json.dumps(
            {"project_info": {"project_id": "shellxpro"}, "client": [{"client_info": {
                "mobilesdk_app_id": APP_ID, "android_client_info": {"package_name": "com.shellx.prod"}}}]}))
        write(r / "shellx-android/app/src/main/res/values/google_oauth.xml", oauth_xml(WEB_ID))
        write(r / "shellx-android/app/src/main/AndroidManifest.xml", "<manifest/>\n")
        write(r / "shellx-ios/Config/Version.xcconfig", "MARKETING_VERSION = 1.2.3\nCURRENT_PROJECT_VERSION = 7\n")
        write(r / "scripts/shellx/check-android-license.sh", FAKE_LICENCE, 0o755)
        for name in ("check_android_license.py", "android-license-allowlist.txt", "check-link-license.sh"):
            write(r / "scripts/shellx" / name, "# placeholder\n")
        write(r / "shellx-link/README.md", "placeholder\n")
        write(r / "docs/README.md", "placeholder\n")

    def commit_and_push(self, message):
        self.git("add", "-A")
        self.git("commit", "-q", "-m", message)
        self.git("push", "-q", "origin", "HEAD:develop")

    def env(self, **extra):
        t = self.tmp
        env = {"PATH": "%s:/usr/bin:/bin:/usr/sbin:/sbin" % self.tools, "HOME": str(self.home), "LANG": "C",
               "GIT_CONFIG_NOSYSTEM": "1", "JAVA_HOME": str(self.jdk),
               "SHELLX_ANDROID_KEY_PROPERTIES": str(self.key_properties),
               "FIXTURE_AAB": str(self.aab), "FIXTURE_MAPPING": str(t / "mapping.txt"),
               "FIXTURE_MANIFEST": str(t / "manifest.xml"), "FIXTURE_CONFIG": str(t / "config.json"),
               "FIXTURE_GRADLE_LOG": str(t / "gradle.log"), "FIXTURE_KEYTOOL_LOG": str(t / "keytool.log"),
               "FIXTURE_NETWORK_LOG": str(t / "network.log"), "FIXTURE_STORE_PW": STORE_PW,
               "FIXTURE_UPLOAD_SHA256": UPLOAD_SHA256, "FIXTURE_UPLOAD_SHA1": UPLOAD_SHA1}
        env.update(extra)
        return env

    def run(self, *args, cwd=None, env=None, **extra):
        return subprocess.run(["bash", str(self.repo / "release/mobile/android.sh"), *args], cwd=cwd or self.repo,
                              env=env or self.env(**extra), capture_output=True, text=True)


class AndroidShTest(unittest.TestCase):
    def setUp(self):
        self.f = Fixture(self)
        self.out = self.f.repo / "build" / "release" / "android"

    def assertRefused(self, result, text):
        self.assertEqual(1, result.returncode, result.stdout + result.stderr)
        self.assertIn(text, result.stderr)
        self.assertFalse((self.out / (NAME + ".aab")).exists())

    def test_build_writes_the_checked_bundle_its_mapping_and_its_source(self):
        r = self.f.run()
        self.assertEqual(0, r.returncode, r.stdout + r.stderr)
        self.assertEqual(self.f.aab.read_bytes(), (self.out / (NAME + ".aab")).read_bytes())
        self.assertEqual(MAPPING, (self.out / (NAME + ".mapping.txt")).read_bytes())
        head = self.f.git("rev-parse", "HEAD").strip()
        self.assertEqual(head + " clean\n", (self.out / (NAME + ".source")).read_text())
        self.assertIn("bundle checks passed: com.shellx.prod 1.2.3 (105)", r.stdout)
        self.assertIn("==> upload key: SHA-256 %s (SHA-1 %s)" % (UPLOAD_SHA256, UPLOAD_SHA1), r.stdout)
        self.assertIn("Not uploaded.", r.stdout)
        gradle = (self.f.tmp / "gradle.log").read_text()
        self.assertIn("--no-configuration-cache", gradle)
        self.assertIn(":app:bundleRelease", gradle)
        self.assertIn("key=" + str(self.f.key_properties), gradle)
        keytool = (self.f.tmp / "keytool.log").read_text()
        self.assertIn("-storepass:env SHELLX_STOREPASS", keytool)
        self.assertIn("-keystore " + str(self.f.keys / "upload.jks"), keytool)
        for secret in (STORE_PW, KEY_PW):
            self.assertNotIn(secret, r.stdout + r.stderr + keytool + gradle)
        self.assertFalse((self.f.tmp / "network.log").exists())

    def test_refuses_uncommitted_and_untracked_changes_in_the_sources(self):
        write(self.f.repo / "shellx-android/version.properties", "VERSION_NAME=1.2.3\nVERSION_CODE=106\n")
        self.assertRefused(self.f.run(), "uncommitted changes in shellx-android/, shellx-link/, release/mobile/ "
                                         "or the licence check")
        self.f.git("checkout", "--", "shellx-android/version.properties")
        write(self.f.repo / "release/mobile/notes.txt", "draft\n")
        self.assertRefused(self.f.run(), "?? release/mobile/notes.txt")
        self.assertFalse((self.f.tmp / "gradle.log").exists())

    def test_changes_outside_the_sources_do_not_matter(self):
        write(self.f.repo / "docs/README.md", "changed\n")
        write(self.f.repo / "docs/new.md", "new\n")
        r = self.f.run()
        self.assertEqual(0, r.returncode, r.stdout + r.stderr)

    def test_refuses_a_commit_that_is_not_on_origin(self):
        write(self.f.repo / "shellx-android/app/src/main/AndroidManifest.xml", "<manifest> </manifest>\n")
        self.f.git("commit", "-q", "-am", "local only")
        head = self.f.git("rev-parse", "HEAD").strip()
        self.assertRefused(self.f.run(), "HEAD %s is not on origin/develop or origin/main" % head)

    def test_accepts_a_detached_pushed_head_run_from_a_subdirectory(self):
        self.f.git("checkout", "-q", "--detach", "HEAD")
        r = self.f.run(cwd=self.f.repo / "shellx-android")
        self.assertEqual(0, r.returncode, r.stdout + r.stderr)
        self.assertTrue((self.out / (NAME + ".aab")).is_file())

    def test_refuses_when_origin_cannot_be_fetched(self):
        self.f.git("remote", "set-url", "origin", str(self.f.tmp / "missing.git"))
        self.assertRefused(self.f.run(), "could not fetch origin")

    def test_refuses_a_missing_shared_or_incomplete_key_file(self):
        missing = self.f.tmp / "nope.properties"
        self.assertRefused(self.f.run(SHELLX_ANDROID_KEY_PROPERTIES=str(missing)),
                           "no upload key properties at %s" % missing)
        self.f.key_properties.chmod(0o644)
        self.assertRefused(self.f.run(), "is readable by other users; run: chmod 600 %s" % self.f.key_properties)
        write(self.f.key_properties, "storeFile=upload.jks\nkeyAlias=upload\n", 0o600)
        self.assertRefused(self.f.run(), "lacks storePassword")

    def test_store_file_may_be_relative_under_home_or_absolute(self):
        release_dir = self.f.home / ".shellx-release"
        write(release_dir / "shellx-upload.jks", "not a real keystore\n")
        write(release_dir / "key.properties", "storeFile=~/.shellx-release/shellx-upload.jks\nstorePassword=%s\n"
              "keyAlias=upload\nkeyPassword=%s\n" % (STORE_PW, KEY_PW), 0o600)
        env = self.f.env()
        del env["SHELLX_ANDROID_KEY_PROPERTIES"]  # the default: ~/.shellx-release/key.properties
        r = self.f.run(env=env)
        self.assertEqual(0, r.returncode, r.stdout + r.stderr)
        self.assertIn("-keystore %s" % (release_dir / "shellx-upload.jks"), (self.f.tmp / "keytool.log").read_text())
        self.assertIn("key=%s" % (release_dir / "key.properties"), (self.f.tmp / "gradle.log").read_text())
        write(self.f.key_properties, "storeFile=%s\nstorePassword=%s\nkeyAlias=upload\nkeyPassword=%s\n"
              % (self.f.keys / "upload.jks", STORE_PW, KEY_PW), 0o600)
        r = self.f.run()
        self.assertEqual(0, r.returncode, r.stdout + r.stderr)
        write(self.f.key_properties, "storeFile=gone.jks\nstorePassword=x\nkeyAlias=upload\nkeyPassword=y\n", 0o600)
        r = self.f.run()  # refused before building: the bundle checked by the run above stays
        self.assertEqual(1, r.returncode)
        self.assertIn("the keystore %s named by storeFile does not exist" % (self.f.keys / "gone.jks"), r.stderr)

    def test_refuses_a_bundle_signed_by_another_key_or_a_debug_key(self):
        self.assertRefused(self.f.run(FAKE_SIGNER_SHA256=OTHER_SHA256),
                           "is signed by SHA-256 %s, expected the upload key %s" % (OTHER_SHA256, UPLOAD_SHA256))
        self.assertRefused(self.f.run(FAKE_SIGNER_OWNER="CN=Android Debug, O=Android, C=US"),
                           "is signed with an Android debug key")

    def test_refuses_a_bundle_that_fails_the_bundle_checks(self):
        write(self.f.tmp / "manifest.xml", manifest_xml(debuggable=True))
        r = self.f.run()
        self.assertRefused(r, "nothing was written to build/release/android/")
        self.assertIn("violation: android:debuggable is true", r.stdout)

    def test_refuses_source_problems_before_building(self):
        self.assertRefused(self.f.run(FAKE_LICENCE_FAIL="1"), "the licence check failed")
        write(self.f.repo / "shellx-android/app/src/main/res/values/google_oauth.xml",
              oauth_xml("0-shellx-placeholder.apps.googleusercontent.com"))
        (self.f.repo / "shellx-android/app/src/release/google-services.json").unlink()
        self.f.commit_and_push("placeholder and no Firebase file")
        r = self.f.run()
        self.assertRefused(r, "the source checks failed")
        self.assertIn("violation: missing shellx-android/app/src/release/google-services.json", r.stdout)
        self.assertIn('violation: google_web_client_id is "0-shellx-placeholder.apps.googleusercontent.com", '
                      'not a Google OAuth client id', r.stdout)
        write(self.f.repo / "shellx-android/app/src/main/res/xml/network_security_config.xml",
              '<network-security-config><base-config cleartextTrafficPermitted="true"/></network-security-config>\n')
        self.f.git("checkout", "HEAD~1", "--", "shellx-android/app/src")
        self.f.commit_and_push("cleartext")
        self.assertRefused(self.f.run(), "a release source set permits cleartext traffic: "
                                         "shellx-android/app/src/main/res/xml/network_security_config.xml")
        self.assertFalse((self.f.tmp / "gradle.log").exists())

    def test_refuses_a_missing_or_old_bundletool(self):
        self.assertRefused(self.f.run(FAKE_BUNDLETOOL_VERSION="1.15.6"), "bundletool 1.15.6 is too old")
        (self.f.tools / "bundletool").unlink()
        self.assertRefused(self.f.run(), "bundletool not found; install it with: brew install bundletool")

    def test_refuses_bad_version_properties(self):
        for text, message in (("VERSION_NAME=1.2\nVERSION_CODE=105\n", "VERSION_NAME '1.2'"),
                              ("VERSION_NAME=1.2.3\nVERSION_CODE=0\n", "VERSION_CODE '0'"),
                              ("VERSION_NAME=1.2.3\nVERSION_CODE=2100000001\n", "VERSION_CODE '2100000001'")):
            write(self.f.repo / "shellx-android/version.properties", text)
            self.f.commit_and_push(message)
            self.assertRefused(self.f.run(), message)

    def test_mark_uploaded_needs_a_checked_bundle_then_blocks_its_version_code(self):
        self.assertRefused(self.f.run("--mark-uploaded"), "no checked bundle of ShellX 1.2.3 (105)")
        self.assertEqual(0, self.f.run().returncode)
        r = self.f.run("--mark-uploaded")
        self.assertEqual(0, r.returncode, r.stdout + r.stderr)
        self.assertIn("The next upload needs VERSION_CODE 106 or higher", r.stdout)
        self.assertRegex((self.out / (NAME + ".uploaded")).read_text(),
                         r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ from [0-9a-f]{40}\n$")
        again = self.f.run("--mark-uploaded")
        self.assertEqual(1, again.returncode)
        self.assertIn("is already marked uploaded", again.stderr)
        build = self.f.run()
        self.assertEqual(1, build.returncode)
        self.assertIn("Google Play refuses a versionCode it has seen", build.stderr)

    def test_check_aab_checks_a_given_bundle_without_git_or_outputs(self):
        write(self.f.repo / "shellx-android/version.properties", "VERSION_NAME=1.2.3\nVERSION_CODE=105\n# dirty\n")
        r = self.f.run("--check-aab", str(self.f.aab), str(self.f.tmp / "mapping.txt"))
        self.assertEqual(0, r.returncode, r.stdout + r.stderr)
        self.assertIn("bundle checks passed: com.shellx.prod 1.2.3 (105)", r.stdout)
        self.assertIn("==> upload key: SHA-256 " + UPLOAD_SHA256, r.stdout)
        self.assertFalse(self.out.exists())
        self.assertFalse((self.f.tmp / "gradle.log").exists())
        missing = self.f.run("--check-aab", str(self.f.tmp / "none.aab"))
        self.assertEqual(1, missing.returncode)
        self.assertIn("is not a file", missing.stderr)

    def test_notes_a_version_name_unlike_the_iphone(self):
        write(self.f.repo / "shellx-ios/Config/Version.xcconfig", "MARKETING_VERSION = 1.3.0\n")
        self.f.commit_and_push("iPhone 1.3.0")
        r = self.f.run()
        self.assertEqual(0, r.returncode, r.stdout + r.stderr)
        self.assertIn("note: VERSION_NAME 1.2.3 is not the iPhone's MARKETING_VERSION 1.3.0", r.stdout)

    def test_usage_and_no_upload_path(self):
        r = self.f.run("--help")
        self.assertEqual(0, r.returncode)
        for text in ("--check-aab", "--mark-uploaded", "never uploads"):
            self.assertIn(text, r.stdout)
        bad = self.f.run("--upload")
        self.assertEqual(2, bad.returncode)
        self.assertIn("unknown option --upload", bad.stderr)
        script = (MOBILE / "android.sh").read_text(encoding="utf-8")
        for word in ("androidpublisher", "googleapis", "fastlane", "gcloud", "curl", "wget"):
            self.assertNotIn(word, script)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run them to see them fail**

  Run: `python3 -m unittest discover -s release/mobile/tests -t release/mobile/tests -p 'test_android_sh.py'`

  Expected: `FAILED (errors=17)`, each with `FileNotFoundError` for `release/mobile/android.sh`.

- [ ] **Step 3: Commit the failing tests**

  ```bash
  git add release/mobile/tests/test_android_sh.py
  git commit -m "test(release): android.sh refuses dirty, unpushed or unsigned releases and never uploads"
  ```

- [ ] **Step 4: Implement `release/mobile/android.sh`**

  `#!/usr/bin/env bash`, `set -euo pipefail`, executable (`chmod +x`), in the style of `release/mobile/ios.sh`. Its header comment is exactly the following, and `usage` prints it (the `awk` of `ios.sh`; to stderr with status 2 on a usage error):

```text
#!/usr/bin/env bash
# Builds the Google Play app bundle of the ShellX Android app (shellx-android/, com.shellx.prod), signed with
# the upload key, and checks it. It never uploads: the maintainer uploads the bundle in Play Console by hand.
# See release/mobile/README.md: "Android: every release", and "Android: what android.sh refuses" for the checks.
#
#   release/mobile/android.sh
#       Release bundle (R8 on) signed with the upload key, then every check. Writes
#       build/release/android/ShellX-<version>-<code>.aab, its R8 mapping (.mapping.txt) and the commit it was
#       built from (.source). Refuses uncommitted changes in shellx-android/, shellx-link/, release/mobile/ or the
#       licence check files, a commit that is not on origin/develop or origin/main (fetched first), and a version
#       code that was already uploaded.
#   release/mobile/android.sh --check-aab <file.aab> [<mapping.txt>]
#       Only the bundle checks and the upload-key signature check, on a bundle that is already built.
#   release/mobile/android.sh --mark-uploaded
#       Records that the checked bundle of the current version was uploaded in Play Console
#       (ShellX-<version>-<code>.uploaded). From then on the build refuses this version code.
#
# The upload key's properties file (storeFile, storePassword, keyAlias, keyPassword) is
# $SHELLX_ANDROID_KEY_PROPERTIES, default ~/.shellx-release/key.properties (mode 600, outside the repo).
# The script never prints a password: keytool reads the store password from the environment.
```

  **Variables:** `APP_ID=com.shellx.prod`, `MIN_BUNDLETOOL=1.17.0`, `REPO_ROOT` (two levels above the script, `pwd -P`), `ANDROID_DIR="$REPO_ROOT/shellx-android"`, `OUT_DIR="$REPO_ROOT/build/release/android"`, `CHECKER="$REPO_ROOT/release/mobile/check_android_bundle.py"`, `SOURCE_PATHS=(shellx-android shellx-link release/mobile scripts/shellx/check-android-license.sh scripts/shellx/check_android_license.py scripts/shellx/android-license-allowlist.txt scripts/shellx/check-link-license.sh)`. Defaults, exported: `JAVA_HOME` and `ANDROID_HOME` as in Global Constraints, `SHELLX_ANDROID_KEY_PROPERTIES="$HOME/.shellx-release/key.properties"`.

  **Functions and their behaviour** (`die` prints `android.sh: <message>` on stderr and exits 1; `note` prints `==> <message>` on stdout; a work directory from `mktemp -d` is removed by an `EXIT` trap with `rm -r -f "${WORK:?}"`):
  1. `read_version`: `VERSION_NAME` and `VERSION_CODE` are the last `^VERSION_NAME=` / `^VERSION_CODE=` lines of `shellx-android/version.properties`. Refusals: `VERSION_NAME '<v>' in shellx-android/version.properties is not X.Y.Z` (`^[0-9]+\.[0-9]+\.[0-9]+$`); `VERSION_CODE '<v>' in shellx-android/version.properties is not an integer from 1 to 2100000000`. `NAME="ShellX-$VERSION_NAME-$VERSION_CODE"`.
  2. `require_clean_and_pushed`: `git -C "$REPO_ROOT" status --porcelain --untracked-files=normal -- "${SOURCE_PATHS[@]}"`; any output → stderr `android.sh: uncommitted changes in shellx-android/, shellx-link/, release/mobile/ or the licence check; commit them first:` and the first 20 lines, exit 1. Then `git fetch --quiet origin` (failure → `could not fetch origin, so HEAD cannot be checked against origin/develop and origin/main`). HEAD must be an ancestor of `refs/remotes/origin/develop` or `refs/remotes/origin/main` (each only when it exists), else `HEAD <sha> is not on origin/develop or origin/main; push it first (git push origin develop)`.
  3. `require_tools`: the major version in the first line of `"$JAVA_HOME/bin/java" -version` must be 17 or more (`JDK 17 or newer needed (JAVA_HOME=<path>)`); `keytool` and `jarsigner` come from `$JAVA_HOME/bin`; `bundletool` from `PATH` (`bundletool not found; install it with: brew install bundletool`), its version is the last line of `bundletool version`, compared with `sort -V` (`bundletool <v> is too old; 1.17.0 or newer prints the 16 KB alignment (brew upgrade bundletool)`); `python3` on `PATH`.
  4. `prop <key>`: `sed -n "s/^[[:space:]]*<key>[[:space:]]*[=:][[:space:]]*//p"` of the properties file, first match, verbatim. Never echo its result.
  5. `read_key_properties`: the file must exist (`no upload key properties at <path> (release/mobile/README.md, "Android: upload key and tools")`); its mode (`stat -f '%Lp'`, falling back to `stat -c '%a'`) must end in `00` (`<path> is readable by other users; run: chmod 600 <path>`); `storeFile`, `storePassword`, `keyAlias` and `keyPassword` must be present (`<path> lacks <key>`, first missing). `storeFile`: `~/…` → `$HOME/…` (escape the tilde in the pattern: `${STORE_FILE#\~/}`); absolute → as is; otherwise `"$(dirname "$SHELLX_ANDROID_KEY_PROPERTIES")/<storeFile>"`, not canonicalized. It must exist: `the keystore <path> named by storeFile does not exist`.
  6. `check_signature <aab>`: `SHELLX_STOREPASS="$(prop storePassword)" "$KEYTOOL" -list -v -keystore <store> -alias <alias> -storepass:env SHELLX_STOREPASS 2>/dev/null` (failure → `keytool could not read the upload key (wrong storePassword or keyAlias in <path>?)`); the expected SHA-256 and SHA-1 are the second fields of the first `SHA256:` and `SHA1:` lines (`awk '$1 == "SHA256:" { print $2; exit }'`). `"$JARSIGNER" -verify <aab>` must print a line starting `jar verified.` (`jarsigner could not verify <aab>`). `"$KEYTOOL" -printcert -jarfile <aab>`: an `Owner:` containing `CN=Android Debug` → `<aab> is signed with an Android debug key (<owner>)`; a SHA-256 other than the expected one → `<aab> is signed by SHA-256 <actual>, expected the upload key <expected>`. On success: `note "upload key: SHA-256 <expected> (SHA-1 <sha1>)"`.
  7. `run_checker <sources|bundle> <args…>`: in a subshell `cd "$REPO_ROOT"`, run `python3 -I "$CHECKER" <command> --google-services shellx-android/app/src/release/google-services.json --google-oauth shellx-android/app/src/main/res/values/google_oauth.xml` plus `--rollout-ledger docs/superpowers/ledgers/shellx-signin-rollout.md` when that file exists, plus the arguments.
  8. `check_bundle <aab> <extra checker args…>`: `androidTargetSdk` from `shellx-android/gradle/libs.versions.toml` (line `androidTargetSdk = "<n>"`; missing → `no androidTargetSdk in shellx-android/gradle/libs.versions.toml`); `bundletool dump manifest --bundle=<aab>` and `bundletool dump config --bundle=<aab>` into the work directory, stderr dropped (failure → `bundletool could not read <aab>`); then `run_checker bundle` with `--aab`, `--manifest-xml`, `--bundle-config`, the two versions, `--catalog-target-sdk`, `--play-rules release/mobile/android-play-target-sdk.txt`, `--permissions release/mobile/android-permissions.txt`, `--today "$(date +%F)"` and the extra arguments; returns its status.
  9. `cmd_build`, in this order:
     1. `read_version`; when `"$OUT_DIR/$NAME.uploaded"` exists: `ShellX <name> (<code>) was uploaded (<its content>); Google Play refuses a versionCode it has seen. Raise VERSION_CODE in shellx-android/version.properties`;
     2. `require_clean_and_pushed`, `require_tools`, `read_key_properties`;
     3. `note "ShellX Android <name> (<code>): release bundle signed with the upload key"`;
     4. `note "licence boundary"`, then `bash "$REPO_ROOT/scripts/shellx/check-android-license.sh"` (failure → `the licence check failed (scripts/shellx/check-android-license.sh)`);
     5. `note "source checks"`, then `run_checker sources --lockfile shellx-android/app/gradle.lockfile` (failure → `the source checks failed (above)`);
     6. `grep -rlI 'cleartextTrafficPermitted="true"'` in `shellx-android/app/src/main` and `shellx-android/app/src/release`, run from `$REPO_ROOT`; any hit → `a release source set permits cleartext traffic: <paths joined by spaces>`;
     7. remove the stale outputs: `rm -f "${OUT_DIR:?}/${NAME:?}.aab" "${OUT_DIR:?}/${NAME:?}.mapping.txt" "${OUT_DIR:?}/${NAME:?}.source" "${aab:?}" "${mapping:?}"`, where `aab` is `$ANDROID_DIR/app/build/outputs/bundle/release/app-release.aab` and `mapping` is `$ANDROID_DIR/app/build/outputs/mapping/release/mapping.txt`;
     8. `note "Gradle :app:bundleRelease (log: build/release/android/logs/<log name>)"`; run `"$ANDROID_DIR/gradlew" -p "$ANDROID_DIR" --console=plain --no-configuration-cache :app:bundleRelease`, all output into the log; the terminal shows only the log lines matching `error:|warning:|What went wrong|FAILURE|BUILD (SUCCESSFUL|FAILED)`. Failure → `Gradle failed; full log: <log>`; no bundle → `Gradle produced no <aab>`;
     9. `check_signature`, then `check_bundle "$aab" --mapping "$mapping" --lockfile shellx-android/app/gradle.lockfile` (failure → `refused <aab> (the checks above); nothing was written to build/release/android/`);
     10. copy the bundle and the mapping to `$OUT_DIR/$NAME.aab` and `$NAME.mapping.txt`, write `<sha> clean` to `$NAME.source`;
     11. when `shellx-ios/Config/Version.xcconfig` has a `MARKETING_VERSION` other than `VERSION_NAME`: `note "note: VERSION_NAME <name> is not the iPhone's MARKETING_VERSION <ios> (contracts §7: the same features carry the same version)"`;
     12. `note "build/release/android/<NAME>.aab (and .mapping.txt, .source)"` and the line `Not uploaded. Upload it in Play Console (release/mobile/README.md, "Android: every release"), then run: release/mobile/android.sh --mark-uploaded`.
  10. `cmd_check_aab <aab> [<mapping>]`: one or two arguments (else usage, status 2); a missing file → `<path> is not a file`; make both paths absolute; `read_version`, `require_tools`, `read_key_properties`, `check_signature`, `check_bundle` with `--mapping` when given (failure → `refused <aab> (the checks above)`). It never runs git and never creates `build/release/android/`.
  11. `cmd_mark_uploaded`: `.uploaded` exists → `ShellX <name> (<code>) is already marked uploaded (<content>)`; no `$NAME.aab` or `$NAME.source` → `no checked bundle of ShellX <name> (<code>); run release/mobile/android.sh first`; else write `<date -u +%Y-%m-%dT%H:%M:%SZ> from <sha of .source>` and `note "recorded: ShellX <name> (<code>) uploaded. The next upload needs VERSION_CODE <code + 1> or higher."`.
  12. Dispatch: no argument → build; `--check-aab`; `--mark-uploaded` (exactly one argument); `-h|--help|help` → usage, status 0; anything else → `android.sh: unknown option <x>` on stderr and usage, status 2.

  The script never uses `set -x`, never prints a password, and does not contain the words `androidpublisher`, `googleapis`, `fastlane`, `gcloud`, `curl` or `wget` (a test reads it).

- [ ] **Step 5: Run the tests to see them pass**

  Run: `bash -n release/mobile/android.sh && python3 -m unittest discover -s release/mobile/tests -t release/mobile/tests -v && /usr/bin/python3 -m unittest discover -s release/mobile/tests -t release/mobile/tests`

  Expected: `Ran 46 tests`, `OK`, twice (about 25 s each).

- [ ] **Step 6: Commit**

  ```bash
  git add release/mobile/android.sh
  git commit -m "feat(release): android.sh builds and checks the signed Google Play bundle, and never uploads"
  ```

---

### Task 4: Release signing in Gradle, `dev.sh`, and the first real signed bundle

**Files:**
- Modify: `shellx-android/app/build.gradle.kts`
- Modify: `shellx-android/scripts/dev.sh`
- Modify (only by Step 7's rules): `release/mobile/android-permissions.txt`

**Interfaces:**
- Consumes: Task 3 (`--check-aab`); plan 3A's `:app` release build type (R8 on, no signing config).
- Produces: release builds signed with the upload key whenever `SHELLX_ANDROID_KEY_PROPERTIES` is set; `UPLOAD_SHA256` and `UPLOAD_SHA1` (from the `==> upload key:` line, for Task 8).

- [ ] **Step 1: See that Gradle ignores the variable today**

  ```bash
  export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk"
  SHELLX_ANDROID_KEY_PROPERTIES=/nonexistent shellx-android/gradlew -p shellx-android --console=plain --no-configuration-cache :app:help 2>&1 | grep -c 'SHELLX_ANDROID_KEY_PROPERTIES names a missing file'
  ```

  Expected: `0`.

- [ ] **Step 2: Add the release signing to `shellx-android/app/build.gradle.kts`**

  Above `android { … }`, with a comment that points at `release/mobile/README.md` ("Android: upload key and tools"):
  - Read `providers.environmentVariable("SHELLX_ANDROID_KEY_PROPERTIES").orNull`. Unset → no signing config: the release build stays unsigned, as plan 3A's `dev.sh build-release` expects. There is no fallback file inside the repository (the Flutter build had one).
  - Set → that path must be a file, else `error("SHELLX_ANDROID_KEY_PROPERTIES names a missing file")`. Load it with `java.util.Properties`. Each of `storeFile`, `storePassword`, `keyAlias`, `keyPassword` must be non-empty, else `error("<file name>: missing <key>")`: messages name keys, never values.
  - `storeFile`: starts with `~/` → `File(System.getProperty("user.home"), rest)`; absolute → as is; otherwise relative to the properties file's folder (the rule of Task 3). Compute `rest` and every other path in a `val` first and pass only variables to `File(…)` and `file(…)`: 3A's licence rule 6 (run by `dev.sh test all` and `android.sh`) refuses a literal that starts with `/` or `~`, and any `$` template, inside those calls (for example `removePrefix("~/")` written inside `File(…)`).
  - `signingConfigs.create("upload")` with the four values, and `buildTypes.release.signingConfig = signingConfigs.getByName("upload")`. Debug signing does not change.

- [ ] **Step 3: Run Step 1's command again**

  Expected: `1` or more (the configuration fails with that message).

- [ ] **Step 4: Change `shellx-android/scripts/dev.sh`**
  - Next to the `JAVA_HOME` and `ANDROID_HOME` defaults, add `unset SHELLX_ANDROID_KEY_PROPERTIES` with the comment `# dev.sh never signs with the upload key; release/mobile/android.sh does.` Add the same sentence to the header comment, after the paragraph about `JAVA_HOME`.
  - `test all`: right after the existing `unittest discover` of `shellx-android/scripts/tests`, run `python3 -m unittest discover -s "$REPO_ROOT/release/mobile/tests" -t "$REPO_ROOT/release/mobile/tests"`. In the header, "the script tests" becomes "the script tests (shellx-android/scripts/tests and release/mobile/tests)".

- [ ] **Step 5: Check the unsigned paths**

  ```bash
  SHELLX_ANDROID_KEY_PROPERTIES=/nonexistent shellx-android/scripts/dev.sh build-release
  shellx-android/scripts/dev.sh test all
  ```

  Expected: `==> release checks passed (com.shellx.prod …)`; then `test all` passes, with `Ran 46 tests` and `OK` from `release/mobile/tests` along the way, and ends with `==> test all: passed`.

- [ ] **Step 6: Build a signed bundle and check it with `--check-aab`**

  Skip when Task 0 Step 6 recorded the key as pending. Otherwise:

  ```bash
  export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk"
  SHELLX_ANDROID_KEY_PROPERTIES="$HOME/.shellx-release/key.properties" shellx-android/gradlew -p shellx-android --console=plain --no-configuration-cache :app:bundleRelease 2>&1 | grep -E 'BUILD|FAILURE|What went wrong'
  release/mobile/android.sh --check-aab shellx-android/app/build/outputs/bundle/release/app-release.aab shellx-android/app/build/outputs/mapping/release/mapping.txt
  ```

  Expected: `BUILD SUCCESSFUL`; then `==> upload key: SHA-256 15:1C:F3:98:…:5A:06 (SHA-1 …)` (the upload key recorded in October 2026 starts with `15:1C:F3:98` and ends with `5A:06`; any other value means `key.properties` names another keystore: stop and tell the user); then `bundle checks passed: com.shellx.prod <VERSION_NAME> (<VERSION_CODE>), target SDK <API> (Google Play needs <PLAY_API> since <date>), <n> permissions, native code: …`. Write down `UPLOAD_SHA256` and `UPLOAD_SHA1`.

- [ ] **Step 7: When the check prints violations, apply exactly these rules, then rerun Step 6**
  - `requests <p>, which … does not list`: when `<p>` is `android.permission.VIBRATE`, add it (comment `# notification vibration (Firebase Cloud Messaging or NotificationCompat)`). For any other permission, stop and ask the user: every new permission changes the Data safety answers or needs a Play declaration (S3 §3 and §7.4c rule out a foreground service and `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`). Report `shellx-android/app/build/outputs/logs/manifest-merger-release-report.txt` lines naming the permission: they say which library adds it.
  - `… lists <p>, which the bundle does not request`: remove that line.
  - `google_web_client_id is "…", not a Google OAuth client id`: plan 1D has not filled the id yet. Record "release candidate waits for plan 1D (Web client id)" and go on: Task 9 cannot build the release candidate until it is filled.
  - `the bundle's resources do not hold the Firebase app id`, or a `google-services.json` problem: plan 3A Task 10 is not done; ask the user to do its Step 1.
  - `the bundle's resources do not hold Google's "G"`: when `ls shellx-android/app/src/main/res/drawable-*dpi/ic_google_g.png` lists nothing, plan 3D Task 9 Steps 7–9 (USER) are still pending: record "release candidate waits for Google's G (plan 3D)" and go on, like the 1D wait. When the files are there, the resource shrinker dropped them: stop and report it.
  - A 16 KB, debug-only, R8 mapping or SDK violation: stop and report it to the user with the library or class it names (a 32-bit library aligned to 4 KB counts: the rule covers every `.so`). Never weaken a check.

  Keep the permission list sorted. Rerun Step 6 until only the waiting-for-1D and waiting-for-the-G violations, or none, remain.

- [ ] **Step 8: Commit**

  ```bash
  git add shellx-android/app/build.gradle.kts shellx-android/scripts/dev.sh release/mobile/android-permissions.txt
  git commit -m "build(shellx-android): sign release builds with the upload key named by SHELLX_ANDROID_KEY_PROPERTIES"
  ```

---

### Task 5: Store listing copy, icon and feature graphics

**Files:**
- Create: `release/mobile/play/store_assets.py`
- Create: `release/mobile/play/feature-graphic.svg`
- Create: `release/mobile/play/listing/en-US/{title,short-description,full-description,release-notes,feature-graphic-tagline}.txt` and the same five in `release/mobile/play/listing/vi/`
- Test: `release/mobile/tests/test_store_assets.py`

**Interfaces:**
- Produces (module `store_assets`, imported with `release/mobile/play` on `sys.path`):

```python
LOCALES = ("en-US", "vi")
SHOTS: tuple[tuple[str, str, tuple[str, ...]], ...]   # (NN, slug, listing locales); Task 6 renders these
def listing_problems(root: Path) -> list[str]
def quoted_label_problems(res: Path) -> list[str]
def png_chunks(data: bytes) -> Iterator[tuple[bytes, bytes]]   # (chunk type, chunk data)
def png_info(data: bytes) -> tuple[int, int, int]              # (width, height, colour type)
def jpeg_info(data: bytes) -> tuple[int, int, int]             # (width, height, components)
def png_add_alpha(data: bytes) -> bytes
def render_icon(logo_svg: Path, out_dir: Path) -> Path         # out_dir/icon-512.png
def render_feature_graphic(template: Path, tagline: str, locale: str, out_dir: Path) -> Path   # out_dir/feature-graphic-<locale>.jpg
def prepare_screenshots(src: Path, out: Path) -> tuple[list[Path], list[str]]   # (files written, problems)
def main(argv: list[str] | None = None) -> int
```

  Command line: `python3 release/mobile/play/store_assets.py listing` (prints `listing ok: en-US, vi`, or `violation:` lines and status 1); `… graphics [--out <dir>]` (default `build/release/android/play`; prints `<path> <w>x<h> PNG RGBA` or `JPEG` per file); `… screenshots --from <dir> [--out <dir>]` (prints each file written, or `violation:` lines and status 1).

- [ ] **Step 1: Write the failing tests**

  Create `release/mobile/tests/test_store_assets.py`:

```python
"""Tests for release/mobile/play/store_assets.py (plan 3H): listing limits, icon, feature graphics, screenshots.

Run: python3 -m unittest discover -s release/mobile/tests -t release/mobile/tests -v
"""
from __future__ import annotations

import shutil
import subprocess
import sys
import tempfile
import unittest
import zlib
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO / "release" / "mobile" / "play"))
import store_assets as sa  # noqa: E402

LISTING = REPO / "release/mobile/play/listing"
TOOLS = shutil.which("rsvg-convert") is not None and shutil.which("sips") is not None


def make_listing(root: Path, **overrides) -> Path:
    for locale in ("en-US", "vi"):
        for name in ("title.txt", "short-description.txt", "full-description.txt", "release-notes.txt",
                     "feature-graphic-tagline.txt"):
            path = root / locale / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(overrides.get("%s/%s" % (locale, name), "ShellX") + "\n", encoding="utf-8")
    return root


def svg_png(width: int, height: int, body: str = "") -> bytes:
    svg = ('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d"><rect width="%d" height="%d" '
           'fill="#0B0716" fill-opacity="0.9"/>%s</svg>' % (width, height, width, height, body))
    return subprocess.run(["rsvg-convert"], input=svg.encode(), capture_output=True, check=True).stdout


class ListingTest(unittest.TestCase):
    def test_the_real_listing_fits_google_play(self):
        self.assertEqual([], sa.listing_problems(LISTING))

    def test_limits_are_counted_in_characters(self):
        with tempfile.TemporaryDirectory() as tmp:
            found = sa.listing_problems(make_listing(Path(tmp) / "long", **{
                "en-US/title.txt": "x" * 31, "vi/short-description.txt": "ệ" * 81,
                "en-US/full-description.txt": "y" * 4001, "vi/release-notes.txt": "z" * 501,
                "vi/feature-graphic-tagline.txt": "w" * 41}))
            self.assertIn("en-US/title.txt: 31 characters, Google Play allows 30", found)
            self.assertIn("vi/short-description.txt: 81 characters, Google Play allows 80", found)
            self.assertIn("en-US/full-description.txt: 4001 characters, Google Play allows 4000", found)
            self.assertIn("vi/release-notes.txt: 501 characters, Google Play allows 500", found)
            self.assertIn("vi/feature-graphic-tagline.txt: 41 characters, the feature graphic fits 40", found)
            self.assertEqual([], sa.listing_problems(make_listing(Path(tmp) / "ok", **{"vi/short-description.txt": "ệ" * 80})))

    def test_refuses_decomposed_text_emoji_banned_words_and_missing_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = make_listing(Path(tmp), **{"vi/title.txt": "Việt",
                                              "en-US/short-description.txt": "The best terminal \U0001F680",
                                              "vi/short-description.txt": "Ứng dụng miễn phí"})
            (root / "en-US" / "release-notes.txt").unlink()
            found = sa.listing_problems(root)
            self.assertIn("vi/title.txt: not in composed form (NFC)", found)
            self.assertIn("en-US/short-description.txt: contains an emoji", found)
            self.assertIn('en-US/short-description.txt: uses "best", which Google Play\'s metadata policy bans in '
                          'titles and short descriptions', found)
            self.assertIn('vi/short-description.txt: uses "miễn phí", which Google Play\'s metadata policy bans in '
                          'titles and short descriptions', found)
            self.assertIn("en-US/release-notes.txt: missing", found)

    def test_every_listing_gets_4_to_8_shots(self):
        for locale in ("en-US", "vi"):
            count = sum(1 for _, _, locales in sa.SHOTS if locale in locales)
            self.assertTrue(4 <= count <= 8, "%s has %d shots" % (locale, count))

    def test_the_listing_quotes_the_apps_own_labels(self):
        res = REPO / "shellx-android/app/src/main/res"
        if not (res / "values" / "strings.xml").is_file():
            self.skipTest("no generated Android strings in this checkout")
        self.assertEqual([], sa.quoted_label_problems(res))


@unittest.skipUnless(TOOLS, "needs rsvg-convert and sips")
class GraphicsTest(unittest.TestCase):
    def test_the_icon_is_a_512_px_32_bit_png_under_1_mib(self):
        with tempfile.TemporaryDirectory() as tmp:
            icon = sa.render_icon(REPO / "design/shellx-logo.svg", Path(tmp))
            self.assertEqual("icon-512.png", icon.name)
            self.assertEqual((512, 512, 6), sa.png_info(icon.read_bytes()))
            self.assertLess(icon.stat().st_size, 1024 * 1024)

    def test_adding_alpha_keeps_every_pixel(self):
        rgb = subprocess.run(["rsvg-convert"], input=(
            b'<svg xmlns="http://www.w3.org/2000/svg" width="9" height="7"><rect width="9" height="7" fill="#1C1438"/>'
            b'<rect x="3" width="3" height="7" fill="#7DF7BE"/></svg>'), capture_output=True, check=True).stdout
        self.assertEqual((9, 7, 2), sa.png_info(rgb))
        rgba = sa.png_add_alpha(rgb)
        self.assertEqual((9, 7, 6), sa.png_info(rgba))
        rows = zlib.decompress(b"".join(body for kind, body in sa.png_chunks(rgba) if kind == b"IDAT"))
        dark, mint = (0x1C, 0x14, 0x38, 255), (0x7D, 0xF7, 0xBE, 255)
        for y in range(7):
            row = rows[y * 37:(y + 1) * 37]  # a filter byte, then 9 RGBA pixels
            self.assertEqual(0, row[0])
            self.assertEqual([dark] * 3 + [mint] * 3 + [dark] * 3,
                             [tuple(row[1 + 4 * x:5 + 4 * x]) for x in range(9)])

    def test_feature_graphics_are_1024_by_500_jpegs_without_alpha(self):
        with tempfile.TemporaryDirectory() as tmp:
            for locale in ("en-US", "vi"):
                tagline = (LISTING / locale / "feature-graphic-tagline.txt").read_text(encoding="utf-8").strip()
                path = sa.render_feature_graphic(REPO / "release/mobile/play/feature-graphic.svg", tagline, locale, Path(tmp))
                self.assertEqual("feature-graphic-%s.jpg" % locale, path.name)
                self.assertEqual((1024, 500, 3), sa.jpeg_info(path.read_bytes()))

    def test_screenshots_become_jpegs_per_theme_and_locale(self):
        with tempfile.TemporaryDirectory() as tmp:
            src, out = Path(tmp) / "src", Path(tmp) / "out"
            src.mkdir()
            png = svg_png(1080, 1920)
            for nn, slug, _locales in sa.SHOTS:
                for theme in ("light", "dark"):
                    for lang in ("en", "vi"):
                        (src / ("store-%s-%s-%s-%s.png" % (nn, slug, theme, lang))).write_bytes(png)
            (src / "launch-dark-en.png").write_bytes(png)  # other render tests are ignored
            written, problems = sa.prepare_screenshots(src, out)
            self.assertEqual([], problems)
            names = {str(p.relative_to(out)) for p in written}
            for nn, slug, locales in sa.SHOTS:
                for theme in ("light", "dark"):
                    for locale in ("en-US", "vi"):
                        path = "screenshots/%s/%s/%s-%s.jpg" % (theme, locale, nn, slug)
                        self.assertEqual(locale in locales, path in names, path)
            self.assertEqual(2 * sum(len(locales) for _, _, locales in sa.SHOTS), len(written))
            self.assertEqual((1080, 1920, 3), sa.jpeg_info((out / "screenshots/light/vi/01-home.jpg").read_bytes()))

    def test_screenshots_refuse_a_wrong_size_and_a_short_set(self):
        with tempfile.TemporaryDirectory() as tmp:
            src = Path(tmp) / "src"
            src.mkdir()
            (src / "store-01-home-dark-en.png").write_bytes(svg_png(1179, 2556))
            _written, problems = sa.prepare_screenshots(src, Path(tmp) / "out")
            self.assertIn("store-01-home-dark-en.png is 1179x2556, expected 1080x1920", problems)
            self.assertIn("missing store-02-permission-dark-en.png", problems)
            self.assertIn("dark/en-US has 0 screenshots, Google Play needs 4 to 8 (store promotion needs 4)", problems)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run them to see them fail**

  Run: `python3 -m unittest discover -s release/mobile/tests -t release/mobile/tests -p 'test_store_assets.py'`

  Expected: `FAILED (errors=1)`, with `ModuleNotFoundError: No module named 'store_assets'`.

- [ ] **Step 3: Commit the failing tests**

  ```bash
  git add release/mobile/tests/test_store_assets.py
  git commit -m "test(release): Google Play listing limits, icon, feature graphics and screenshots"
  ```

- [ ] **Step 4: Write the listing copy and the feature graphic template, exactly**

  Each block is one file: its lines, then one newline. Title ≤ 30, short description ≤ 80, full description ≤ 4000, release notes ≤ 500 characters (the test counts them).

  `release/mobile/play/listing/en-US/title.txt`:

```text
ShellX: AI Agents & Terminal
```

  `release/mobile/play/listing/en-US/short-description.txt`:

```text
Answer your AI coding agents and use your Mac's terminal from your phone.
```

  `release/mobile/play/listing/en-US/full-description.txt`:

```text
ShellX puts the AI coding agents and terminals running on your Mac in your pocket. When Claude Code, Codex or another command-line agent needs your permission, an answer or a decision on its plan, your phone tells you, and you reply in a few taps, without walking back to your desk.

WHAT YOU CAN DO
• See every workspace on your Macs at a glance: what needs you, what is running, what just finished.
• Answer permission requests: Allow, Deny or Always allow.
• Answer an agent's questions: pick one of its options or type your own answer.
• Review a plan, then approve it, send it back with feedback or reject it.
• Chat with an agent: read its replies, its thinking and each tool step; send messages, photos and files; stop it.
• Hold the mic and talk instead of typing, in English or Vietnamese.
• Open the real terminal of a workspace and type with your phone's keyboard, Vietnamese Telex included.
• Get a notification the moment an agent needs you.
• Rename and close workspaces and tabs, start a new workspace, and manage your paired Macs.

HOW IT WORKS
1. Install ShellX on your Mac (free, from shellx.pro).
2. Sign in with Google on the Mac and on your phone.
3. On the Mac, choose Pair Phone… and scan the QR code with your phone.

Your phone and your Mac talk through the ShellX relay over an end-to-end encrypted channel (the Noise protocol). The relay only forwards encrypted data and cannot read your sessions. No ports to open, no VPN, no static IP.

PRIVACY
• Sign in with Google. ShellX stores only what it needs to run your account, such as your email, your devices and your pairings.
• Agent conversations, attachments and terminal content are end-to-end encrypted between your phone and your own Mac.
• Notifications carry only the names of the agent and the workspace, never what the agent asks.
• No ads, no analytics, no tracking.
• Delete your account at any time: Settings › Account › Delete Account…

TRY IT WITHOUT A MAC
Tap “Try without an account” on the first screen to explore a sample Mac with workspaces, agents and requests waiting for you. Nothing is sent anywhere.

REQUIREMENTS
• A Mac with ShellX installed (macOS 14 or later).
• Android 8.0 or later.
```

  `release/mobile/play/listing/en-US/release-notes.txt` (the first release; edit it for each upload):

```text
First release of ShellX for Android: pair with your Mac, answer your AI agents, chat, talk and use the terminal from your phone.
```

  `release/mobile/play/listing/en-US/feature-graphic-tagline.txt`:

```text
AI agents and terminal on your phone
```

  `release/mobile/play/listing/vi/title.txt`:

```text
ShellX: Agent AI và terminal
```

  `release/mobile/play/listing/vi/short-description.txt`:

```text
Trả lời agent lập trình AI và dùng terminal của Mac ngay trên điện thoại.
```

  `release/mobile/play/listing/vi/full-description.txt`:

```text
ShellX đưa các agent lập trình AI và terminal đang chạy trên Mac vào túi của bạn. Khi Claude Code, Codex hay một agent dòng lệnh khác cần bạn cho phép, cần câu trả lời hay cần bạn quyết định về kế hoạch của nó, điện thoại sẽ báo cho bạn, và bạn trả lời chỉ bằng vài lần chạm, không cần quay lại bàn làm việc.

BẠN LÀM ĐƯỢC GÌ
• Xem nhanh mọi workspace trên các Mac: việc gì cần bạn, việc gì đang chạy, việc gì vừa xong.
• Trả lời yêu cầu xin quyền: Cho phép, Từ chối hoặc Luôn cho phép.
• Trả lời câu hỏi của agent: chọn một phương án của nó hoặc tự gõ câu trả lời.
• Xem kế hoạch rồi duyệt, gửi lại kèm góp ý hoặc từ chối.
• Trò chuyện với agent: đọc câu trả lời, phần suy nghĩ và từng bước dùng tool; gửi tin nhắn, ảnh và file; dừng agent.
• Giữ mic để nói thay vì gõ, bằng tiếng Việt hoặc tiếng Anh.
• Mở terminal thật của một workspace và gõ bằng bàn phím điện thoại, kể cả kiểu gõ Telex.
• Nhận thông báo ngay khi agent cần bạn.
• Đổi tên, đóng workspace và tab, mở workspace mới, quản lý các Mac đã ghép cặp.

CÁCH HOẠT ĐỘNG
1. Cài ShellX trên Mac (miễn phí, tại shellx.pro).
2. Đăng nhập Google trên Mac và trên điện thoại.
3. Trên Mac, chọn Ghép cặp điện thoại… rồi dùng điện thoại quét mã QR.

Điện thoại và Mac nói chuyện với nhau qua relay của ShellX bằng một kênh mã hoá đầu cuối (giao thức Noise). Relay chỉ chuyển tiếp dữ liệu đã mã hoá và không đọc được phiên làm việc của bạn. Không cần mở cổng, không cần VPN, không cần IP tĩnh.

QUYỀN RIÊNG TƯ
• Đăng nhập bằng Google. ShellX chỉ lưu những gì cần để chạy tài khoản, như email, thiết bị và các lần ghép cặp của bạn.
• Cuộc trò chuyện với agent, tệp đính kèm và nội dung terminal được mã hoá đầu cuối giữa điện thoại và chính Mac của bạn.
• Thông báo chỉ mang tên agent và tên workspace, không bao giờ mang nội dung agent hỏi.
• Không quảng cáo, không phân tích, không theo dõi.
• Xoá tài khoản bất cứ lúc nào: Cài đặt › Tài khoản › Xoá tài khoản…

XEM THỬ KHÔNG CẦN MAC
Chạm “Xem thử không cần tài khoản” ở màn hình đầu tiên để xem một Mac mẫu với workspace, agent và các yêu cầu đang chờ bạn. Không có gì được gửi đi.

YÊU CẦU
• Một Mac đã cài ShellX (macOS 14 trở lên).
• Android 8.0 trở lên.
```

  `release/mobile/play/listing/vi/release-notes.txt`:

```text
Bản đầu tiên của ShellX cho Android: ghép cặp với Mac, trả lời agent AI, trò chuyện, nói và dùng terminal ngay trên điện thoại.
```

  `release/mobile/play/listing/vi/feature-graphic-tagline.txt`:

```text
Agent AI và terminal trên điện thoại
```

  `release/mobile/play/feature-graphic.svg` (the logo's chevrons and cursor from `design/shellx-logo.svg` at 0.52 scale, the wordmark, and `__TAGLINE__`, which `store_assets.py` replaces):

```xml
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 500" width="1024" height="500">
  <!-- Google Play feature graphic (1024 x 500). release/mobile/play/store_assets.py replaces __TAGLINE__. -->
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#1C1438"/>
      <stop offset="1" stop-color="#0B0716"/>
    </linearGradient>
    <radialGradient id="glow" cx="0.2" cy="0.5" r="0.5">
      <stop offset="0" stop-color="#4AF2A1" stop-opacity="0.16"/>
      <stop offset="1" stop-color="#4AF2A1" stop-opacity="0"/>
    </radialGradient>
    <linearGradient id="mint" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#7DF7BE"/>
      <stop offset="1" stop-color="#2FD98A"/>
    </linearGradient>
    <linearGradient id="lilac" x1="1" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#FFFFFF"/>
      <stop offset="1" stop-color="#CFC8EE"/>
    </linearGradient>
  </defs>
  <rect width="1024" height="500" fill="url(#bg)"/>
  <rect width="1024" height="500" fill="url(#glow)"/>
  <g transform="translate(64 116) scale(0.52)">
    <polyline points="384,122 290,234 384,346" fill="none" stroke="url(#lilac)" stroke-width="54" stroke-linecap="round" stroke-linejoin="round"/>
    <polyline points="128,122 222,234 128,346" fill="none" stroke="url(#mint)" stroke-width="54" stroke-linecap="round" stroke-linejoin="round"/>
    <rect x="300" y="398" width="84" height="26" rx="8" fill="url(#mint)"/>
  </g>
  <text x="340" y="245" font-family="Helvetica Neue, Helvetica, Arial, sans-serif" font-size="100" font-weight="700" fill="#FFFFFF">ShellX</text>
  <text x="344" y="305" font-family="Helvetica Neue, Helvetica, Arial, sans-serif" font-size="30" fill="#CFC8EE">__TAGLINE__</text>
</svg>
```

- [ ] **Step 5: Implement `release/mobile/play/store_assets.py`**

  Standard library plus the `rsvg-convert` and `sips` commands; `REPO = Path(__file__).resolve().parents[3]`.
  - **Constants:** `LIMITS` = title 30 ("Google Play allows 30"), short-description 80, full-description 4000, release-notes 500 ("Google Play allows <n>"), feature-graphic-tagline 40 ("the feature graphic fits 40"). `BANNED = {"en-US": ("best", "#1", "top", "free", "new", "sale", "discount", "cheap", "million"), "vi": ("tốt nhất", "số 1", "hàng đầu", "miễn phí", "mới", "giảm giá", "khuyến mãi")}`. `QUOTED_LABELS = {"en-US": ("Try without an account", "Settings", "Account", "Delete Account…"), "vi": ("Xem thử không cần tài khoản", "Cài đặt", "Tài khoản", "Xoá tài khoản…")}`. `SHOTS = (("01", "home", ("en-US", "vi")), ("02", "permission", ("en-US", "vi")), ("03", "terminal", ("en-US", "vi")), ("04", "agent", ("vi",)), ("05", "plan", ("vi",)), ("06", "first-mac", ("en-US", "vi")), ("07", "settings", ("en-US",)))`: shots 04 and 05 show the demo's Vietnamese chat and plan text (Spec note 4).
  - **`listing_problems`**: for each locale and file, in that order: `<locale>/<file>: missing`; then on the text without its one trailing newline: `<locale>/<file>: <n> characters, <limit text>`; `<locale>/<file>: not in composed form (NFC)`; `<locale>/<file>: contains an emoji` (a code point in U+1F000–U+1FAFF or U+2600–U+27BF, or U+FE0F); and, for the title and the short description only, each `BANNED` word of the locale matched case-insensitively and as a whole word (`(?<![\w#])` + word + `(?!\w)`): `<locale>/<file>: uses "<word>", which Google Play's metadata policy bans in titles and short descriptions`.
  - **`quoted_label_problems(res)`**: the text of every `<string>` in `res/values/strings*.xml` (en-US) and `res/values-vi/strings*.xml` (vi), with `\'` and `\"` unescaped; each `QUOTED_LABELS` entry missing from its locale gives `the <locale> listing quotes "<label>", which is not an app string in <folder>`.
  - **PNG and JPEG headers:** `png_info` reads `IHDR`; `jpeg_info` walks the markers after `FFD8` (skipping standalone markers `D0`–`D7` and `01`) to the first `C0`, `C1` or `C2` frame header (`>BHHB`: precision, height, width, components). Anything else raises `ValueError`.
  - **`png_add_alpha`:** returns RGBA input unchanged; refuses anything but 8-bit RGB without interlace (`ValueError`). Decode: concatenate `IDAT`, `zlib.decompress`, and undo each row's filter (0 none, 1 sub, 2 up, 3 average, 4 Paeth; `a` = left, `b` = up, `c` = up-left byte at 3 bytes per pixel, 0 outside the row; Paeth picks `a`, `b` or `c`, whichever is nearest to `a + b − c`, ties in that order). Encode: rows of filter byte 0 and RGBA pixels with alpha 255, `zlib.compress(…, 9)`, and the chunks `IHDR` (colour type 6), `IDAT`, `IEND`, each with its CRC-32 over type and data.
  - **`render_icon`:** take `design/shellx-logo.svg`, drop the line containing `stroke-opacity="0.09"` (the border), remove every ` rx="114"` (full bleed: Google Play rounds the corners and adds the shadow itself), render with `rsvg-convert -w 512 -h 512 -f png` from stdin, then `png_add_alpha` (Play asks for a 32-bit PNG; `rsvg-convert` writes RGB when the image is opaque).
  - **`render_feature_graphic`:** XML-escape the tagline (`&`, `<`, `>`), replace `__TAGLINE__`, render 1024×500 with `rsvg-convert` into a temporary PNG, then `sips -s format jpeg -s formatOptions 95 <png> --out <out_dir>/feature-graphic-<locale>.jpg` (Play takes JPEG or 24-bit PNG without alpha).
  - **`prepare_screenshots`:** for every shot of `SHOTS`, theme (`light`, `dark`) and language (`en` → `en-US`, `vi` → `vi`) whose locale the shot lists: the input is `store-<NN>-<slug>-<theme>-<lang>.png` in `src` (`missing <file>`); it must be 1080×1920 (`<file> is <w>x<h>, expected 1080x1920`); it becomes `out/screenshots/<theme>/<locale>/<NN>-<slug>.jpg` with the same `sips` command. Other files in `src` are ignored. Then every theme and locale must have 4 to 8 files: `<theme>/<locale> has <n> screenshots, Google Play needs 4 to 8 (store promotion needs 4)`.
  - **`main`:** `listing` runs `listing_problems` on `release/mobile/play/listing` and, when `shellx-android/app/src/main/res/values/strings.xml` exists, `quoted_label_problems`.

- [ ] **Step 6: Run the tests to see them pass**

  Run: `python3 -m unittest discover -s release/mobile/tests -t release/mobile/tests -v && /usr/bin/python3 -m unittest discover -s release/mobile/tests -t release/mobile/tests`

  Expected: `Ran 56 tests`, `OK`, twice (the generated Android strings exist, so nothing is skipped).

- [ ] **Step 7: If `test_the_listing_quotes_the_apps_own_labels` fails**

  A plan named a label differently. Change the listing and `QUOTED_LABELS` to the app's own string exactly (in both the full description and the release notes when they quote it), and nothing else; rerun Step 6. Report the change in the hand-off.

- [ ] **Step 8: Render the graphics and look at them**

  ```bash
  python3 release/mobile/play/store_assets.py listing
  python3 release/mobile/play/store_assets.py graphics
  for f in icon-512.png feature-graphic-en-US.jpg feature-graphic-vi.jpg; do sips -s format jpeg -s formatOptions 50 -Z 600 "build/release/android/play/$f" --out "build/release/android/play/preview-$f.jpg" >/dev/null; done
  ```

  Expected: `listing ok: en-US, vi`; then `…/icon-512.png 512x512 PNG RGBA`, `…/feature-graphic-en-US.jpg 1024x500 JPEG`, `…/feature-graphic-vi.jpg 1024x500 JPEG`. Open the three `preview-*.jpg` files (previews avoid the image-size limit of the file reader). The icon: the mint ">" and lilac "<" chevrons and the mint cursor on the dark square, edge to edge, with no border line. Each feature graphic: the chevrons left of a white "ShellX", the tagline below it in lilac, entirely inside the image with at least 40 px to spare on the right. If the tagline is clipped, change `font-size="30"` to `font-size="26"` in the template and render again.

- [ ] **Step 9: Commit**

  ```bash
  git add release/mobile/play
  git commit -m "feat(release): Google Play listing in English and Vietnamese, icon and feature graphics"
  ```

---

### Task 6: Store screenshots from the demo

**Files:**
- Create: `shellx-android/app/src/testDebug/kotlin/com/shellx/app/screenshots/StoreScreenshotsRenderTest.kt`
- Modify (only by Step 5's rule): `release/mobile/play/store_assets.py` (`SHOTS`)

**Interfaces:**
- Consumes: plan 3A's `ShellXSnapshots.capture(name: String, content: @Composable () -> Unit): List<Snapshot>` (light-en, dark-en, light-vi, dark-vi; `Snapshot.theme`, `language`, `width`, `height`, `argb`); the render tests of plans 3D, 3E and 3G (`*RenderTest` in `com.shellx.app.screenshots`); Task 5's `SHOTS`.
- Produces: render-test PNGs `store-<NN>-<slug>-<light|dark>-<en|vi>.png` at 1080×1920 px (360×640 dp at xxhdpi, Google Play's 9:16 portrait size).

- [ ] **Step 1: Find the source of each shot**

  Each shot renders the same screen, with the same sample data, as that screen's existing render test. Find them:

  ```bash
  cd shellx-android/app/src/testDebug/kotlin/com/shellx/app/screenshots
  for c in WorkspaceListScreen WorkspaceListView PendingCardView PendingListView TerminalPane AgentScreen AgentView PlanReviewSheet FirstMacView SettingsScreen; do echo "== $c"; grep -ln "$c(" *.kt; done
  cd -
  ```

  | Shot | Screen (ledger row) | The shot must show |
  | --- | --- | --- |
  | `store-01-home` | Home, `WorkspaceListView` (6.1-5) | the groups Needs you, Running and a Mac's workspaces |
  | `store-02-permission` | Needs you, `PendingListView` / `PendingCardView` (6.1-11) | a permission card for `Bash` with Allow and Deny |
  | `store-03-terminal` | Shell pane, `TerminalPane` (6.1-9) | a prompt and some command output |
  | `store-04-agent` | Agent chat, `AgentView` (6.1-10) | text, a collapsed thinking entry and a tool step |
  | `store-05-plan` | Plan sheet, `PlanReviewSheet` (6.1-11) | the plan with Approve, Revise and Reject |
  | `store-06-first-mac` | "No Mac yet", `FirstMacView` (6.1-4) | the pair button and "Try with a sample Mac" |
  | `store-07-settings` | Settings, `SettingsScreen` (3D's name for the iPhone's `SettingsView`; 6.1-13) | the Account, Appearance, Voice and Notifications sections |

  When a screen has no render test that shows this state, build its state from the demo the way that render test builds its own (3C's `com.shellx.core.demo.DemoEnvironment`, `DemoScript.setUp()` and `step(0)`…`step(2)`). If that is not possible for a shot, leave the shot out (remove its line from `SHOTS`), as long as each locale keeps at least 4 shots; otherwise stop and report.

- [ ] **Step 2: Write `StoreScreenshotsRenderTest.kt`**

```kotlin
// shellx-android/app/src/testDebug/kotlin/com/shellx/app/screenshots/StoreScreenshotsRenderTest.kt
package com.shellx.app.screenshots

import androidx.compose.runtime.Composable
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Google Play phone screenshots (plan 3H): 1080 x 1920 px, in light and dark, English and Vietnamese.
 * `dev.sh screenshots record <dir>` writes them as store-<NN>-<slug>-<theme>-<lang>.png, and
 * release/mobile/play/store_assets.py turns them into the listing's JPEGs. Each shot renders the same screen and
 * sample data as that screen's own render test.
 */
@RunWith(AndroidJUnit4::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = StoreScreenshotsRenderTest.STORE_QUALIFIERS)
class StoreScreenshotsRenderTest {
    companion object {
        const val STORE_QUALIFIERS = "w360dp-h640dp-xxhdpi"
    }

    private fun shoot(name: String, content: @Composable () -> Unit) {
        val shots = ShellXSnapshots.capture(name, content)
        assertEquals(listOf("light-en", "dark-en", "light-vi", "dark-vi"), shots.map { "${it.theme}-${it.language}" })
        for (shot in shots) {
            assertEquals(1080, shot.width)
            assertEquals(1920, shot.height)
        }
        assertFalse(shots[0].argb.contentEquals(shots[1].argb))
    }

    @Test fun store01Home() { shoot("store-01-home") { /* Step 1's source for 6.1-5 */ } }
    @Test fun store02Permission() { shoot("store-02-permission") { /* 6.1-11, permission card */ } }
    @Test fun store03Terminal() { shoot("store-03-terminal") { /* 6.1-9 */ } }
    @Test fun store04Agent() { shoot("store-04-agent") { /* 6.1-10 */ } }
    @Test fun store05Plan() { shoot("store-05-plan") { /* 6.1-11, plan sheet */ } }
    @Test fun store06FirstMac() { shoot("store-06-first-mac") { /* 6.1-4 */ } }
    @Test fun store07Settings() { shoot("store-07-settings") { /* 6.1-13 */ } }
}
```

  Fill each content lambda from Step 1's source, copying its setup (the class-level `@Config` stays). When a capture comes out smaller than the screen, wrap that content in `Box(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background)) { … }`.

- [ ] **Step 3: Run the render tests**

  Run: `shellx-android/scripts/dev.sh test screenshots`

  Expected: seven `StoreScreenshotsRenderTest > store0… PASSED` lines (one per shot left in `SHOTS`), every other render test still `PASSED`, and `==> test screenshots: passed`.

- [ ] **Step 4: Record and convert them**

  ```bash
  shellx-android/scripts/dev.sh screenshots record build/release/android/play/render
  python3 release/mobile/play/store_assets.py screenshots --from build/release/android/play/render
  for f in build/release/android/play/screenshots/dark/*/*.jpg; do sips -s format jpeg -s formatOptions 40 -Z 800 "$f" --out "${f%.jpg}.preview.jpg" >/dev/null; done
  ```

  Expected: `screenshots written to …/render`; then one path per shot, theme and listing locale (with today's `SHOTS`: 22 files), and status 0.

- [ ] **Step 5: Look at every dark preview and apply the language rule**

  Open each `*.preview.jpg` under `build/release/android/play/screenshots/dark/`. Each must show its row's state from Step 1, legible, with no "Demo · Exit" banner, no debug label and nothing cut off. Language rule: a shot in `en-US` must not show a Vietnamese sentence (chat text, a question, a plan); names of Macs, workspaces and sessions do not count. When one does, remove `"en-US"` from that shot's locales in `SHOTS`. `test_every_listing_gets_4_to_8_shots` must still pass; if it cannot, stop and tell the user which shots carry Vietnamese text. Rerun Step 4 after any change, then delete the previews: `find build/release/android/play/screenshots -name '*.preview.jpg' -delete`.

- [ ] **Step 6: Commit**

  ```bash
  git add shellx-android/app/src/testDebug/kotlin/com/shellx/app/screenshots/StoreScreenshotsRenderTest.kt release/mobile/play/store_assets.py
  git commit -m "test(shellx-android): Google Play screenshots of the demo at 1080 x 1920"
  ```

---

### Task 7: Open-source licence notices (Settings › About › Licenses)

Decided in the Android cross-review: Android shows the notices of the libraries it ships inside the app, where the iPhone's "Licenses" row only opens https://shellx.pro. This is an Android-only difference (Step 15).

**Files:**
- Create: `release/mobile/tests/test_android_licence_checks.py`
- Modify: `release/mobile/check_android_bundle.py`
- Modify: `shellx-android/settings.gradle.kts`, `shellx-android/app/build.gradle.kts`, `shellx-android/gradle/libs.versions.toml`, `shellx-android/app/gradle.lockfile` (through `dev.sh lock`), `scripts/shellx/android-license-allowlist.txt` (through plan 3A Task 3 Step 6)
- Create: `shellx-android/app/src/main/kotlin/com/shellx/app/ui/settings/Licences.kt`
- Modify: `shellx-android/app/src/main/kotlin/com/shellx/app/ui/settings/AboutSection.kt` (plan 3D's)
- Test: `shellx-android/app/src/testDebug/kotlin/com/shellx/app/ui/settings/LicencesRowTest.kt`
- Modify: `docs/superpowers/ledgers/shellx-android-parity.md` (one new `A-` row)
- Fallback path only (Step 9 decides): Create `shellx-android/scripts/generate-licences.py`, `shellx-android/scripts/tests/test_generate_licences.py`, `shellx-android/app/src/main/assets/licenses/third_party_licenses.txt` (generated), `shellx-android/app/src/main/kotlin/com/shellx/app/ui/settings/LicencesActivity.kt`; Modify `shellx-android/app/src/main/AndroidManifest.xml`, `shellx-android/scripts/dev.sh` (`run_checks`), `release/mobile/android.sh` (one source check) and `release/mobile/tests/test_android_sh.py` (one test)

**Interfaces:**
- Consumes: Task 2's checker and its `bundle` command (the bundles of Tasks 2 and 3's tests already carry the two resource names below); Task 4's signed build and `release/mobile/android.sh --check-aab`; plan 3D's `AboutSection` and its "Licenses" row; the generated string `settings_about_license` ("Licenses" / "Giấy phép", from the iPhone's `settings.about.license`); plan 3A's `ShellXTheme` and the Material 3 colour schemes and typography it builds; plan 3A's allowlist procedure (3A Task 3 Step 6) and `dev.sh lock`.
- Produces:

```python
# release/mobile/check_android_bundle.py
LICENCE_NAMES = (b"third_party_licenses", b"third_party_license_metadata")   # resource names in resources.pb
LICENCE_ASSET_ENTRY = "base/assets/licenses/third_party_licenses.txt"        # the fallback's file
LICENCE_PLACEHOLDER = b"Debug License Info"
def licence_notice_problems(resources: bytes, res_files: dict[str, bytes], asset: bytes | None) -> list[str]
```

```kotlin
// shellx-android/app/src/main/kotlin/com/shellx/app/ui/settings/Licences.kt
/** What Settings › About › Licenses does on Android: opens the open-source licence notices (plan 3H). */
fun openLicences(context: Context)
```

- [ ] **Step 1: Write the failing tests**

  Create `release/mobile/tests/test_android_licence_checks.py`:

```python
"""Tests for the open-source licence notice check of release/mobile/check_android_bundle.py (plan 3H, Task 7).

Run: python3 -m unittest discover -s release/mobile/tests -t release/mobile/tests -v
"""
from __future__ import annotations

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO / "release" / "mobile"))
import check_android_bundle as cab  # noqa: E402
import test_android_bundle_checks as bt  # noqa: E402  (its bundle and command-line fixtures)

NAMES = b"\x22\x14third_party_licenses\x2a\x1cthird_party_license_metadata"
LICENCES = b"Apache License, Version 2.0 https://www.apache.org/licenses/LICENSE-2.0\n"
METADATA = b"0:71 OkHttp\n"
MISSING = ("the bundle has no open-source licence notices: neither the resources raw/third_party_licenses and "
           "raw/third_party_license_metadata (Google's OSS licences plugin) nor assets/licenses/third_party_licenses.txt")


class LicenceNoticeTest(unittest.TestCase):
    def test_googles_licence_resources_pass(self):
        files = {"base/res/raw/third_party_licenses": LICENCES, "base/res/raw/third_party_license_metadata": METADATA}
        self.assertEqual([], cab.licence_notice_problems(NAMES, files, None))

    def test_shortened_resource_paths_still_pass(self):
        self.assertEqual([], cab.licence_notice_problems(NAMES, {"base/res/Ab.bin": LICENCES}, None))

    def test_the_debug_placeholder_is_refused(self):
        files = {"base/res/raw/third_party_licenses": b"Licenses are only provided in build variants (e.g. release)",
                 "base/res/raw/third_party_license_metadata": b"0:59 Debug License Info\n"}
        self.assertEqual(["base/res/raw/third_party_license_metadata holds the licences plugin's debug placeholder "
                          "(\"Debug License Info\"): the plugin did not see the release dependencies"],
                         cab.licence_notice_problems(NAMES, files, None))

    def test_the_fallback_asset_passes(self):
        self.assertEqual([], cab.licence_notice_problems(b"", {}, b"OkHttp (com.squareup.okhttp3:okhttp:5.1.0)\n"))

    def test_a_bundle_without_notices_is_refused(self):
        self.assertEqual([MISSING], cab.licence_notice_problems(b"\x22\x14third_party_licenses", {}, None))
        self.assertEqual([MISSING], cab.licence_notice_problems(b"", {}, b""))

    def test_the_bundle_command_refuses_a_bundle_without_notices(self):
        with tempfile.TemporaryDirectory() as tmp:
            d = Path(tmp)
            files = {"manifest.xml": bt.MANIFEST, "config.json": bt.CONFIG_16K, "rules.txt": "2026-08-31 36\n",
                     "permissions.txt": "\n".join(bt.PERMS) + "\n", "google-services.json": bt.GOOGLE_SERVICES,
                     "google_oauth.xml": bt.oauth_xml(bt.WEB_ID)}
            for name, text in files.items():
                (d / name).write_text(text, encoding="utf-8")
            aab = bt.make_aab(d, resources=b"\x0a\x20" + bt.APP_ID.encode() + b"\x12" + bt.WEB_ID.encode()
                              + b"\x1a\x0bic_google_g")
            r = subprocess.run([sys.executable, "-I", str(REPO / "release/mobile/check_android_bundle.py"), "bundle",
                                "--google-services", str(d / "google-services.json"),
                                "--google-oauth", str(d / "google_oauth.xml"), "--aab", str(aab),
                                "--manifest-xml", str(d / "manifest.xml"), "--bundle-config", str(d / "config.json"),
                                "--version-name", "1.2.3", "--version-code", "105", "--catalog-target-sdk", "36",
                                "--play-rules", str(d / "rules.txt"), "--permissions", str(d / "permissions.txt"),
                                "--today", "2026-11-07"], capture_output=True, text=True)
            self.assertEqual(1, r.returncode, r.stdout + r.stderr)
            self.assertEqual(["violation: " + MISSING], r.stdout.splitlines())


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run them to see them fail**

  Run: `python3 -m unittest discover -s release/mobile/tests -t release/mobile/tests`

  Expected: `FAILED (failures=1, errors=5)`: the five tests that call `licence_notice_problems` error with `AttributeError`, and `test_the_bundle_command_refuses_a_bundle_without_notices` fails; the other 56 tests pass.

- [ ] **Step 3: Commit the failing tests**

  ```bash
  git add release/mobile/tests/test_android_licence_checks.py
  git commit -m "test(release): the Android bundle must carry its open-source licence notices"
  ```

- [ ] **Step 4: Implement the check in `release/mobile/check_android_bundle.py`**
  - `licence_notice_problems`: a non-empty `asset` (the fallback) → `[]`. Otherwise, when `resources` contains both `LICENCE_NAMES` (Google's plugin; a resource name is never shortened, a file path may be): the first `res_files` entry, in name order, whose bytes contain `LICENCE_PLACEHOLDER` → `["<entry> holds the licences plugin's debug placeholder (\"Debug License Info\"): the plugin did not see the release dependencies"]`, and none → `[]`. Otherwise → `["the bundle has no open-source licence notices: neither the resources raw/third_party_licenses and raw/third_party_license_metadata (Google's OSS licences plugin) nor assets/licenses/third_party_licenses.txt"]`.
  - `bundle`: after the resource checks, add `licence_notice_problems(<the concatenated */resources.pb bytes>, <every base/res/… entry>, <the LICENCE_ASSET_ENTRY bytes, or None>)`. The success line does not change.

- [ ] **Step 5: Run the tests to see them pass**

  Run: `python3 -m unittest discover -s release/mobile/tests -t release/mobile/tests -v && /usr/bin/python3 -m unittest discover -s release/mobile/tests -t release/mobile/tests`

  Expected: `Ran 62 tests`, `OK`, twice.

- [ ] **Step 6: Commit**

  ```bash
  git add release/mobile/check_android_bundle.py
  git commit -m "feat(release): refuse an Android bundle without its open-source licence notices"
  ```

- [ ] **Step 7: Look up Google's licences tooling (read-only)**

  Open https://developers.google.com/android/guides/opensource. On 2026-11-07 it says:
  - plugin id `com.google.android.gms.oss-licenses-plugin`, which has no plugin marker: `settings.gradle.kts` resolves it in `pluginManagement` (whose `repositories` must hold `google()`, as 3A's does) with
    ```kotlin
    resolutionStrategy {
        eachPlugin {
            if (requested.id.id == "com.google.android.gms.oss-licenses-plugin") {
                useModule("com.google.android.gms:oss-licenses-plugin:0.13.0")
            }
        }
    }
    ```
  - in the app module, `id("com.google.android.gms.oss-licenses-plugin")` under the Android application plugin, and `implementation("com.google.android.gms:play-services-oss-licenses:17.5.3")`;
  - the screen `com.google.android.gms.oss.licenses.v2.OssLicensesMenuActivity`, started with `startActivity(Intent(this, OssLicensesMenuActivity::class.java))`; `OssLicensesMenuActivity.setActivityTitle(…)` sets its title and, for Material 3, `OssLicensesMenuActivity.setTheme(lightColorScheme, darkColorScheme, typography)` its theme.

  The plugin writes the raw resources `third_party_licenses` and `third_party_license_metadata`; in a build where the Android Gradle plugin gives it no dependency list (debug builds), it writes one placeholder entry, "Debug License Info". Take the newest versions with 3A Task 0 Step 4's `latest`: `latest https://dl.google.com/dl/android/maven2/com/google/android/gms/oss-licenses-plugin/maven-metadata.xml` and `latest https://dl.google.com/dl/android/maven2/com/google/android/gms/play-services-oss-licenses/maven-metadata.xml`. If the page now names another id, artifact, class or setup, follow the page and say so in the hand-off.

- [ ] **Step 8: Add the plugin and the library**
  - `shellx-android/settings.gradle.kts`: the `resolutionStrategy` block of Step 7 inside the existing `pluginManagement { … }`, with Step 7's plugin version and the comment `// Google's open-source licences plugin has no plugin marker; it is resolved by module (plan 3H).`
  - `shellx-android/gradle/libs.versions.toml`: `playServicesOssLicenses = "<version>"` under `[versions]` and `play-services-oss-licenses = { module = "com.google.android.gms:play-services-oss-licenses", version.ref = "playServicesOssLicenses" }` under `[libraries]`.
  - `shellx-android/app/build.gradle.kts`: `id("com.google.android.gms.oss-licenses-plugin")` in `plugins`, after the Android application plugin, and `implementation(libs.play.services.oss.licenses)`.
  - Run `shellx-android/scripts/dev.sh lock`, then `bash scripts/shellx/check-android-license.sh`. Add each artefact it reports by plan 3A Task 3 Step 6; the library itself is `com.google.android.gms:play-services-oss-licenses  ship  Google-SDK  # Android Software Development Kit License`. Repeat until `check-android-license: ok`. An artefact whose licence the procedure does not allow: stop and report it.

- [ ] **Step 9: Decide between Google's plugin and the fallback**

  ```bash
  export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk"
  shellx-android/gradlew -p shellx-android --console=plain :app:bundleRelease 2>&1 | grep -E 'BUILD|FAILURE|What went wrong|oss' | head -20
  python3 -I -c 'import sys, zipfile; z = zipfile.ZipFile(sys.argv[1]); n = z.namelist(); r = b"".join(z.read(x) for x in n if x.endswith("/resources.pb")); print("names", b"third_party_licenses" in r and b"third_party_license_metadata" in r); print("placeholder", any(b"Debug License Info" in z.read(x) for x in n if x.startswith("base/res/")))' shellx-android/app/build/outputs/bundle/release/app-release.aab
  ```

  Without `SHELLX_ANDROID_KEY_PROPERTIES` the bundle is unsigned, which is enough here.
  - **Plugin path:** Gradle prints `BUILD SUCCESSFUL` and the script prints `names True` and `placeholder False`. Go to Step 10.
  - `names False` after `BUILD SUCCESSFUL`: the resource shrinker may have dropped the two raw resources. Create `shellx-android/app/src/main/res/raw/keep_licences.xml` holding `<resources xmlns:tools="http://schemas.android.com/tools" tools:keep="@raw/third_party_licenses,@raw/third_party_license_metadata" />` and run the two commands again: `names True` and `placeholder False` → plugin path (keep the file); anything else → fallback path.
  - **Fallback path:** the plugin is incompatible with the Android Gradle plugin version 3A pins: Gradle fails because of it (an error naming `oss-licenses`, `OssLicensesTask`, `LicensesTask` or `DependencyTask`, or an Android Gradle plugin class or method it cannot find), or the script prints `placeholder True`. Do Step 14 instead of Steps 10–13.

- [ ] **Step 10 (plugin path): Write the failing UI test**

```kotlin
// shellx-android/app/src/testDebug/kotlin/com/shellx/app/ui/settings/LicencesRowTest.kt
package com.shellx.app.ui.settings

import android.app.Application
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.R
import com.shellx.app.ui.theme.ShellXTheme
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf

/** Settings › About › Licenses opens the open-source licence notices, not shellx.pro (plan 3H; parity ledger). */
@RunWith(AndroidJUnit4::class)
class LicencesRowTest {
    @get:Rule val compose = createComposeRule()

    @Test
    fun licensesOpensTheOpenSourceLicenceNotices() {
        val app = ApplicationProvider.getApplicationContext<Application>()
        compose.setContent { ShellXTheme { AboutSection(/* the arguments plan 3D's Settings render test passes */) } }
        compose.onNodeWithText("shellx.pro").assertDoesNotExist()
        compose.onNodeWithText(app.getString(R.string.settings_about_license)).performClick()
        assertEquals(LICENCES_SCREEN, shadowOf(app).nextStartedActivity?.component?.className)
    }

    private companion object {
        /** On the fallback path (Step 14): "com.shellx.app.ui.settings.LicencesActivity". */
        const val LICENCES_SCREEN = "com.google.android.gms.oss.licenses.v2.OssLicensesMenuActivity"
    }
}
```

  Fill `AboutSection(…)` with the arguments plan 3D's own render test of the Settings screen gives it (`grep -rn 'AboutSection(' shellx-android/app/src`).

- [ ] **Step 11: Run it to see it fail**

  Run: `shellx-android/scripts/dev.sh test app`

  Expected: `LicencesRowTest > licensesOpensTheOpenSourceLicenceNotices FAILED`: `assertDoesNotExist` finds the row's "shellx.pro" value, or the started intent opens the website instead of the licences screen (`but was:<null>`); `==> test app: FAILED`.

- [ ] **Step 12: Implement**
  - `Licences.kt`, `openLicences(context)`: `OssLicensesMenuActivity.setActivityTitle(context.getString(R.string.settings_about_license))`; `OssLicensesMenuActivity.setTheme(<the light ColorScheme>, <the dark ColorScheme>, <the Typography>)` with the objects 3A's `ShellXTheme` builds from `ShellXColors` (if the resolved library has no `setTheme`, leave this call out and say so in the hand-off); then `context.startActivity(Intent(context, OssLicensesMenuActivity::class.java))`.
  - `AboutSection.kt`: the "Licenses" row's action becomes `openLicences(LocalContext.current)`; it no longer shows the "shellx.pro" value and no longer opens the website. The label, the version row and the accessibility labels stay.

- [ ] **Step 13: Run the tests to see them pass**

  Run: `shellx-android/scripts/dev.sh test app && shellx-android/scripts/dev.sh test screenshots`

  Expected: `LicencesRowTest > licensesOpensTheOpenSourceLicenceNotices PASSED`, `==> test app: passed`, `==> test screenshots: passed`. Go to Step 15.

- [ ] **Step 14 (fallback path only): A bundled licence list and a Compose screen**
  1. Remove what Step 8 added: the `resolutionStrategy` block, the plugin id, the library and its two catalog lines, and the allowlist lines added in Step 8; run `shellx-android/scripts/dev.sh lock` and `bash scripts/shellx/check-android-license.sh` (expected: `check-android-license: ok`).
  2. Create `shellx-android/scripts/tests/test_generate_licences.py`:

```python
"""Tests for shellx-android/scripts/generate-licences.py (plan 3H Task 7, fallback path only).

Run: python3 -m unittest discover -s shellx-android/scripts/tests -v
"""
from __future__ import annotations

import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "generate-licences.py"
APACHE = ("The Apache Software License, Version 2.0", "https://www.apache.org/licenses/LICENSE-2.0.txt")
LOCK = ("com.squareup.okhttp3:okhttp:5.1.0=debugRuntimeClasspath,releaseRuntimeClasspath\n"
        "androidx.core:core:1.16.0=releaseRuntimeClasspath\n"
        "junit:junit:4.13.2=debugUnitTestRuntimeClasspath\n"
        "com.shellx.link:link-core:1.0=releaseRuntimeClasspath\n"
        "empty=\n")


def pom(name=None, licences=(), parent=None):
    parts = ['<project xmlns="http://maven.apache.org/POM/4.0.0">']
    if parent:
        parts.append("<parent><groupId>%s</groupId><artifactId>%s</artifactId><version>%s</version></parent>" % parent)
    if name:
        parts.append("<name>%s</name>" % name)
    if licences:
        parts.append("<licenses>%s</licenses>" % "".join(
            "<license><name>%s</name><url>%s</url></license>" % l for l in licences))
    return "".join(parts) + "</project>\n"


class GenerateLicencesTest(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.cache = self.tmp / "cache"
        self.lock = self.tmp / "gradle.lockfile"
        self.out = self.tmp / "assets" / "licenses" / "third_party_licenses.txt"
        self.lock.write_text(LOCK, encoding="utf-8")
        self.put("com.squareup.okhttp3", "okhttp", "5.1.0", pom("okhttp", [APACHE]))
        self.put("androidx.core", "core", "1.16.0", pom("Core", [APACHE]))

    def put(self, g, a, v, text):
        folder = self.cache / g / a / v / "0123abcd"
        folder.mkdir(parents=True, exist_ok=True)
        (folder / ("%s-%s.pom" % (a, v))).write_text(text, encoding="utf-8")

    def run_script(self, *extra):
        return subprocess.run([sys.executable, "-I", str(SCRIPT), "--lockfile", str(self.lock), "--gradle-cache",
                               str(self.cache), "--out", str(self.out), *extra], capture_output=True, text=True)

    def test_lists_release_dependencies_with_their_pom_licences(self):
        r = self.run_script()
        self.assertEqual(0, r.returncode, r.stdout + r.stderr)
        self.assertEqual("generate-licences: wrote 2 libraries to %s\n" % self.out, r.stdout)
        self.assertEqual("Open-source software in ShellX for Android\n\n"
                         "Core (androidx.core:core:1.16.0)\n"
                         "License: The Apache Software License, Version 2.0 https://www.apache.org/licenses/LICENSE-2.0.txt\n\n"
                         "okhttp (com.squareup.okhttp3:okhttp:5.1.0)\n"
                         "License: The Apache Software License, Version 2.0 https://www.apache.org/licenses/LICENSE-2.0.txt\n\n",
                         self.out.read_text(encoding="utf-8"))

    def test_a_licence_from_the_parent_pom(self):
        self.put("androidx.core", "core", "1.16.0", pom("Core", parent=("androidx", "parent", "1")))
        self.put("androidx", "parent", "1", pom(licences=[("MIT", "https://opensource.org/licenses/MIT")]))
        self.assertEqual(0, self.run_script().returncode)
        self.assertIn("Core (androidx.core:core:1.16.0)\nLicense: MIT https://opensource.org/licenses/MIT\n",
                      self.out.read_text(encoding="utf-8"))

    def test_check_reports_a_stale_file(self):
        self.assertEqual(1, self.run_script("--check").returncode)
        self.assertEqual(0, self.run_script().returncode)
        r = self.run_script("--check")
        self.assertEqual((0, "generate-licences: ok (2 libraries)\n"), (r.returncode, r.stdout))
        self.lock.write_text(LOCK.replace("1.16.0", "1.17.0"), encoding="utf-8")
        self.put("androidx.core", "core", "1.17.0", pom("Core", [APACHE]))
        r = self.run_script("--check")
        self.assertEqual((1, "generate-licences: stale; run python3 shellx-android/scripts/generate-licences.py\n"),
                         (r.returncode, r.stdout))

    def test_a_missing_pom_or_licence_is_an_error(self):
        self.lock.write_text("org.example:gone:1.0=releaseRuntimeClasspath\n", encoding="utf-8")
        r = self.run_script()
        self.assertEqual(1, r.returncode)
        self.assertIn("no POM for org.example:gone:1.0", r.stderr)
        self.put("org.example", "gone", "1.0", pom("Gone"))
        r = self.run_script()
        self.assertEqual(1, r.returncode)
        self.assertIn("no licence in the POM of org.example:gone:1.0 or its parents", r.stderr)


if __name__ == "__main__":
    unittest.main()
```

     Run: `python3 -m unittest discover -s shellx-android/scripts/tests`. Expected: `FAILED (failures=4)`: the four new tests fail because `generate-licences.py` does not exist. Commit it: `git add shellx-android/scripts/tests/test_generate_licences.py` and `git commit -m "test(shellx-android): open-source licence notices built from the lockfile and the POMs"`.
  3. Create `shellx-android/scripts/generate-licences.py` (Python 3.9 standard library, `from __future__ import annotations`; `--check`, `--lockfile` default `shellx-android/app/gradle.lockfile`, `--gradle-cache` default `~/.gradle/caches/modules-2/files-2.1`, `--out` default `shellx-android/app/src/main/assets/licenses/third_party_licenses.txt`, all relative to the script's `shellx-android/` folder):
     - the libraries: every lockfile line `group:artifact:version=<configurations>` whose configurations include `releaseRuntimeClasspath`, except groups starting with `com.shellx.`; blank lines, `#` comments and `empty=` are skipped; sorted by `group:artifact`;
     - each one's POM: the first, in name order, of `<cache>/<group>/<artifact>/<version>/*/<artifact>-<version>.pom`; none → exit with `generate-licences: no POM for <g:a:v> in <cache>: run shellx-android/scripts/dev.sh lock and a build first` (`SystemExit` with that text: stderr, status 1);
     - read with `xml.etree.ElementTree`, ignoring XML namespaces: the project's `name` (else the artifact id) and each `licenses/license` with a `name` (and its `url`). No licence → the same from its `<parent>` POM (`groupId`, `artifactId`, `version`), up to 5 parents; still none → exit with `generate-licences: no licence in the POM of <g:a:v> or its parents`;
     - the text (UTF-8, `\n`): `Open-source software in ShellX for Android`, a blank line, then for each library `<name> (<group>:<artifact>:<version>)`, one line `License: <licence name> <url>` per licence (no trailing space when there is no URL), and a blank line;
     - without `--check`: write the file (creating its folder) and print `generate-licences: wrote <n> libraries to <path>`; with `--check`: print `generate-licences: ok (<n> libraries)` and exit 0 when the file holds exactly that text, else print `generate-licences: stale; run python3 shellx-android/scripts/generate-licences.py` and exit 1.

     Run the tests again: `Ran 36 tests`, `OK` (3A's 32 and these 4), under `python3` and `/usr/bin/python3`.
  4. Run `python3 shellx-android/scripts/generate-licences.py`. Expected: `generate-licences: wrote <n> libraries to …/third_party_licenses.txt`, with `<n>` the number of non-ShellX `releaseRuntimeClasspath` lines of the lockfile.
  5. Write Step 10's `LicencesRowTest` with `LICENCES_SCREEN = "com.shellx.app.ui.settings.LicencesActivity"` and run `shellx-android/scripts/dev.sh test app`: it fails as in Step 11. Then `LicencesActivity.kt` in `com.shellx.app.ui.settings`: `class LicencesActivity : ComponentActivity()` whose `onCreate` calls `super.onCreate(savedInstanceState)`, `enableEdgeToEdge()` and `setContent { ShellXTheme { LicencesScreen(assets.open("licenses/third_party_licenses.txt").bufferedReader().use { it.readText() }) } }`. `@Composable fun LicencesScreen(text: String)`: a `Scaffold` whose `topBar` is a `TopAppBar` titled `stringResource(R.string.settings_about_license)`, around a `LazyColumn` (the Scaffold's padding, 16 dp at the sides, 8 dp between items) with one `Text` in `MaterialTheme.typography.bodyMedium` per block of `text.split("\n\n")`. System Back closes it. Declare it in `AndroidManifest.xml` inside `<application>`: `<activity android:name=".ui.settings.LicencesActivity" android:exported="false" />`. `openLicences(context)` is `context.startActivity(Intent(context, LicencesActivity::class.java))`, and `AboutSection.kt` changes as in Step 12.
  6. `shellx-android/scripts/dev.sh`, `run_checks`: after the strings check, when `app/src/main/assets/licenses/third_party_licenses.txt` exists, `note "licence notices"` and `python3 "$ANDROID_DIR/scripts/generate-licences.py" --check`.
  7. `release/mobile/android.sh`, `cmd_build` step 5, right after `run_checker sources …`: when `shellx-android/app/src/main/assets/licenses/third_party_licenses.txt` exists, `python3 -I "$ANDROID_DIR/scripts/generate-licences.py" --check` (failure → `the licence notices are stale; run python3 shellx-android/scripts/generate-licences.py`). Its test, added to `AndroidShTest` in `release/mobile/tests/test_android_sh.py` before `test_usage_and_no_upload_path`:

```python
    def test_refuses_stale_fallback_licence_notices(self):
        write(self.f.repo / "shellx-android/app/src/main/assets/licenses/third_party_licenses.txt", "old\n")
        write(self.f.repo / "shellx-android/scripts/generate-licences.py",
              "import sys\nprint('generate-licences: stale; run python3 shellx-android/scripts/generate-licences.py')\n"
              "sys.exit(1)\n")
        self.f.commit_and_push("stale licence notices")
        self.assertRefused(self.f.run(), "the licence notices are stale")
        self.assertFalse((self.f.tmp / "gradle.log").exists())
```

  8. Run `python3 -m unittest discover -s release/mobile/tests -t release/mobile/tests` (expected: `Ran 63 tests`, `OK`), then Step 13's commands (expected: `LicencesRowTest > licensesOpensTheOpenSourceLicenceNotices PASSED`, `==> test app: passed`, `==> test screenshots: passed`).

- [ ] **Step 15: Record the Android-only difference**

  Append to "Android-only differences" in `docs/superpowers/ledgers/shellx-android-parity.md`, with the next free `A-` number, in the format of the rows there:

  `| A-<n> | Settings › About › Licenses opens the open-source licence notices of the libraries in the app (Google's licences screen, or the bundled list of the fallback path), not shellx.pro | The app ships third-party libraries, whose notices belong in the app (Android cross-review, plan 3H) | app:ui/settings/AboutSection.kt, app:ui/settings/Licences.kt | 3H | differs (3H): by design |`

- [ ] **Step 16: Check the signed bundle again**

  Skip when Task 0 Step 6 recorded the key as pending. Otherwise run Task 4 Step 6's two commands. Expected: `bundle checks passed: …` with no licence violation; the only violations allowed are Task 4 Step 7's waits (plan 1D's Web client id, plan 3D's G). A permission that the licences library adds is handled by Task 4 Step 7's permission rules.

- [ ] **Step 17: Commit**

  Plugin path:

  ```bash
  git add shellx-android/settings.gradle.kts shellx-android/app/build.gradle.kts shellx-android/gradle/libs.versions.toml \
    shellx-android/app/gradle.lockfile scripts/shellx/android-license-allowlist.txt shellx-android/app/src/main \
    shellx-android/app/src/testDebug/kotlin/com/shellx/app/ui/settings/LicencesRowTest.kt docs/superpowers/ledgers/shellx-android-parity.md
  git commit -m "feat(shellx-android): Settings › About › Licenses opens Google's open-source licence notices"
  ```

  Fallback path: the same `git add` without the three Gradle files and with `shellx-android/scripts/generate-licences.py shellx-android/scripts/dev.sh release/mobile/android.sh release/mobile/tests/test_android_sh.py`, and the message `feat(shellx-android): Settings › About › Licenses shows the bundled open-source licence notices`.

---

### Task 8: The README — Android release, Play Console runbook (USER), Data safety, listing, device checklist

**Files:**
- Modify: `release/mobile/README.md`
- Modify: `shellx-android/README.md` (section "Releasing")
- Modify: `docs/superpowers/ledgers/shellx-android-parity.md` (only the "The user's phone" row, when Task 0 Step 8 got a new answer)

**Interfaces:**
- Consumes: Tasks 3–7; Task 0's facts; Task 4's `UPLOAD_SHA256` and `UPLOAD_SHA1`.
- Produces: README sections that Task 9's hand-off points at, by these exact headings: "Android: every release", "Android: what android.sh refuses", "Android: upload key and tools", "Google Play Console" (steps Play 1–Play 10), "Google Play: Data safety", "Google Play: store listing and graphics", "Android: device checklist" (D1–D13) and "Google Play: facts".

- [ ] **Step 1: Confirm the code facts behind the Data safety answers**

  ```bash
  grep -rn 'signInWithGoogle(' shellx-android/app/src/main/kotlin | head -3
  grep -rn -E 'Build\.MODEL|Build\.MANUFACTURER|DEVICE_NAME' shellx-android/app/src/main/kotlin | head -3
  grep -rn -E 'FirebaseAnalytics|Crashlytics|AdvertisingIdClient' shellx-android/app/src/main shellx-android/core/src/main | head -3
  grep -rln -E 'RelayApi|okhttp3' shellx-android/core/src/main/kotlin/com/shellx/core/demo
  grep -rn -E 'createOnDeviceSpeechRecognizer|createSpeechRecognizer' shellx-android/app/src/main/kotlin | head -3
  grep -rln 'cleartextTrafficPermitted="true"' shellx-android/app/src/main shellx-android/app/src/release
  ```

  Expected: the sign-in call site and the device name it passes; no analytics, crash or advertising code; no network class in the demo; at least one speech recognizer; no cleartext. Write `DEVICE_NAME_FACT`: "the phone's model name" when the device name comes from `Build.MODEL` or `Build.MANUFACTURER`, "the phone's name from Android settings" when it comes from `DEVICE_NAME`, "the phone's name from Android settings, or its model name when none is set" when it takes `DEVICE_NAME` first and `Build.MODEL` as the fallback (plan 3D's `DeviceName.current`), otherwise the literal text it uses. If any other line differs from the expectation, stop and report it: the answers below would be wrong.

- [ ] **Step 2: Edit the iPhone part of `release/mobile/README.md`**

  Keep every iPhone sentence as it is on `develop` (plan 1C changed some). Only:
  - the title becomes `# Mobile release (iPhone and Android)`;
  - in the first paragraph, replace the sentence "There is no Android app; the Flutter app and its `android.sh` are gone." with: "The native Android app [`shellx-android/`](../../shellx-android) (also `com.shellx.prod`, "ShellX") is built and signed the same way; `android.sh` never uploads: the maintainer uploads its bundle in Play Console.";
  - the headings `## Every release`, `## App Store Connect` and `## One-time setup` become `## iPhone: every release`, `## iPhone: App Store Connect` and `## iPhone: one-time setup`;
  - append the five rows below to the existing command table (its header is repeated here only to show the columns):

    | Command | Does | Output |
    |---|---|---|
    | `release/mobile/android.sh` | Signed release bundle (R8 on), every Android check | `build/release/android/ShellX-<version>-<code>.aab`, `.mapping.txt` and `.source` |
    | `release/mobile/android.sh --check-aab <file.aab> [<mapping.txt>]` | Only the checks, on a built bundle | |
    | `release/mobile/android.sh --mark-uploaded` | Records that the checked bundle of the current version was uploaded in Play Console | `ShellX-<version>-<code>.uploaded` |
    | `python3 release/mobile/play/store_assets.py listing\|graphics\|screenshots` | Store listing checks, icon, feature graphics, screenshots | `build/release/android/play/` |
    | `shellx-android/scripts/dev.sh build-release` | Unsigned release build and its checks (also part of `test all`) | |

- [ ] **Step 3: Append the Android sections to `release/mobile/README.md`, exactly**

  Fill the placeholders: `<UPLOAD_SHA256>` and `<UPLOAD_SHA1>` (Task 4 Step 6; `pending (USER)` when Task 4 Step 6 was skipped), `<DEVICE_NAME_FACT>` (Step 1), and `<ACCOUNT_TYPE>`, `<ACCOUNT_CREATED>`, `<HIGHEST_CODE>` (Task 0 Step 7; `pending (USER)` when unknown).

````markdown
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
- a failing `scripts/shellx/check-android-license.sh`; a release `google-services.json` that is missing or not
  for `com.shellx.prod` of project `shellxpro`; a `google_web_client_id`
  (`shellx-android/app/src/main/res/values/google_oauth.xml`) that is still the placeholder or that differs from
  the Web client id in `docs/superpowers/ledgers/shellx-signin-rollout.md` (contracts §16); an analytics,
  advertising or crash-reporting SDK on the release classpath (Firebase Analytics, Crashlytics, Performance,
  In-App Messaging; Play services measurement, ads, analytics, App Set); `cleartextTrafficPermitted="true"` in
  `app/src/main` or `app/src/release`;
- a bundle that `jarsigner` cannot verify, that is signed with an Android debug key, or whose signer is not the
  upload key (SHA-256 compared with `keytool`);
- in the bundle's manifest: an application id other than `com.shellx.prod`; a versionCode or versionName other
  than `version.properties`; a minSdk other than 26; a targetSdk other than the catalog's `androidTargetSdk` or
  below Google Play's rule of the day; `android:debuggable`, `android:testOnly` or
  `android:usesCleartextTraffic` set to true; backup not off (`android:allowBackup="false"`); the debug-only
  activities of Compose tooling; permissions other than exactly `release/mobile/android-permissions.txt`, and
  always `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` (S3 §7.4c) and `com.google.android.gms.permission.AD_ID`. A
  change to that list changes the Data safety answers or needs a Play declaration: update "Google Play: Data
  safety" in the same commit;
- debug-only code in the dex files or the R8 mapping: test libraries (JUnit, Robolectric, Roborazzi,
  kotlin-test, AndroidX Test, Compose UI test, coroutines test, MockWebServer), OkHttp's logging interceptor,
  LeakCanary, Compose tooling (its `@Preview` annotations excepted), the packages `com.shellx.core.testing`,
  `com.shellx.app.testing`, `com.shellx.app.screenshots` and `com.shellx.app.debug`, the test fakes
  `FakeRelayAccount`, `FakeIdentityProvider`, `InMemorySecretStore`, `FakeTranscriber` and
  `FakeVoicePermissions`, and `SHELLX_DEMO`. The in-app demo (`com.shellx.core.demo`, "Try without an account")
  ships on purpose;
- a native library of any ABI with a LOAD segment aligned below 16 KB, or whose GNU_RELRO segment ends inside a
  16 KB page shared with writable data; native libraries while the bundle config does not ask for 16 KB zip
  alignment (`PAGE_ALIGNMENT_16K`). Every `.so` must be 16 KB aligned, always: Google Play requires 16 KB support
  for new apps and updates that target Android 15 or later since 2025-11-01;
- a bundle without dex files, without its R8 mapping or with one that differs from `mapping.txt`, or whose
  resources lack the Firebase app id, the Google web client id or Google's "G" (`drawable/ic_google_g`, plan 3D);
- a bundle without the open-source licence notices behind Settings › About › Licenses: the resources
  `raw/third_party_licenses` and `raw/third_party_license_metadata` of Google's licences plugin, without its debug
  placeholder ("Debug License Info"), or, on plan 3H Task 7's fallback path, `assets/licenses/third_party_licenses.txt`,
  which must be up to date (`python3 shellx-android/scripts/generate-licences.py --check`).

## Android: upload key and tools

- The upload key that signed the Flutter bundles is `~/.shellx-release/shellx-upload.jks`, with
  `~/.shellx-release/key.properties` (`storeFile`, `storePassword`, `keyAlias`, `keyPassword`; mode 600; outside
  the repo). `storeFile` may be absolute, start with `~/`, or be relative to the properties file. Upload key
  certificate: SHA-256 `<UPLOAD_SHA256>`, SHA-1 `<UPLOAD_SHA1>`.
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

  You can also sign in with any Google account. That creates a new, empty ShellX account, and the next screen offers "Try with a sample Mac".

  To delete an account: Settings › Account › Delete Account…
  ```

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
`==> upload key:` line of `android.sh` (`<UPLOAD_SHA256>`). Write both SHA-256s into "Google Play: facts" and
the App signing **SHA-1** into the rollout ledger (client 5's row and "Hand-off to 3D / 3H"). Then, in the
Google Cloud project `shellxpro`:

1. **The third Android OAuth client.** Google sign-in on Android uses three Android OAuth clients, each one
   package and one SHA-1 (contracts §16): `ShellX Android (dev)` (`com.shellx.dev` + this Mac's debug SHA-1),
   `ShellX Android (upload key)` (`com.shellx.prod` + the upload key SHA-1, `<UPLOAD_SHA1>`) and
   `ShellX Android (Play signing)` (`com.shellx.prod` + the **App signing** SHA-1). Plan 1D creates the first two
   and leaves the third `pending (3H)` until the first upload exists. Create it: Google Auth Platform → Clients →
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
- Account creation methods: **OAuth** (Sign in with Google).
- Delete account URL: **https://shellx.pro/privacy#delete-account**.
- Do you provide a way for users to request that some or all of their data is deleted, without requiring them to
  delete their account? **No**.
- Shared with third parties: **nothing**. Google (Firebase Cloud Messaging) and the server host process data on
  ShellX's behalf, which Play does not count as sharing.

| Data type | Collected | Processed ephemerally | Required or optional | Purposes | Fact |
| --- | --- | --- | --- | --- | --- |
| Personal info › Email address | Yes | No | Required | App functionality, Account management | Sign in with Google; the relay stores the account's email and the apps show it. |
| Personal info › Name | Yes | Yes | Required | Account management | The Google ID token the app sends carries the Google profile name; the relay reads only the email and the account ID, and stores no name. |
| Personal info › User IDs | Yes | No | Required | App functionality, Account management | The Google account ID (`sub`) and the ShellX account and device IDs. |
| Device or other IDs | Yes | No | Required | App functionality | The Firebase Cloud Messaging token and the Firebase installation ID (registered after sign-in, whether or not notifications are allowed), and the phone's ShellX device ID, Link public key and device name (<DEVICE_NAME_FACT>), which the user's Mac shows. The IP address is used only in memory, to limit sign-in attempts. |
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
- **D2. Install and first launch.** The launcher shows "ShellX" (not "ShellX Dev") with the ShellX icon. The app
  opens on the logo, then the sign-in screen, in the phone's light or dark mode. Settings › About shows the
  uploaded version and code.
- **D3. Demo.** On the sign-in screen, "Try without an account" opens the demo with the "Demo · Exit" banner:
  workspaces, running agents and requests show; Allow on a permission card removes it; Exit returns to sign-in.
  Turn on airplane mode and repeat: the demo works the same.
- **D4. Sign-in.** "Continue with Google" opens Google's account sheet; after choosing the account the app is
  signed in, and Settings › Account shows its email. A developer error or an immediate failure means the
  `ShellX Android (Play signing)` client is missing (Play 8). Once, for S1 §2.1 criterion 2 (plan 1D leaves it to
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
- **D11. Delete account** (last, with a throwaway Google account). Sign out (it asks first), sign in with the
  throwaway account, Settings › Account › Delete Account…: the dialog says what is deleted, Google asks for the
  account again, and the app returns to sign-in with no Mac. Signing in again with that account starts an empty
  account. Sign back in with your own account, and pair again if the Mac is gone.
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
| Developer account type | <ACCOUNT_TYPE> | Play 1 |
| Account created after 2023-11-13 (path B) | <ACCOUNT_CREATED> | Play 1 |
| Highest versionCode uploaded before the native app | <HIGHEST_CODE> | Play 2 |
| Upload key certificate SHA-256 | <UPLOAD_SHA256> | `android.sh` |
| App signing key certificate SHA-256 | pending (USER, Play 8) | Play 8 |
| Internal testing opt-in link | pending (USER, Play 7) | Play 7 |
| Closed test: day the 12th tester opted in (path B) | pending (USER, Play 10) | Play 10 |
````

- [ ] **Step 4: Update `shellx-android/README.md`**

  Replace the body of its "Releasing" section with: "Google Play bundles are built and signed on the maintainer's Mac with `release/mobile/android.sh`, never in CI and never uploaded by a script. [release/mobile/README.md](../release/mobile/README.md) has the checks, the Play Console steps, the Data safety answers, the store listing and the device checklist. `dev.sh build-release` is the unsigned check that every `dev.sh test all` runs; `dev.sh` never signs with the upload key."

- [ ] **Step 5: Record the phone**

  When Task 0 Step 8 got the phone from the user, write maker, model, Android version and API level into the ledger row "The user's phone" (its last column `yes` when `OEM_HOLDS_PUSH` is yes).

- [ ] **Step 6: Check**

  ```bash
  grep -c -E '^### Play ([1-9]|10)\. USER' release/mobile/README.md
  grep -c -E '^- \*\*D([1-9]|1[0-3])\.' release/mobile/README.md
  grep -n -E '<(UPLOAD_SHA256|UPLOAD_SHA1|DEVICE_NAME_FACT|ACCOUNT_TYPE|ACCOUNT_CREATED|HIGHEST_CODE)>' release/mobile/README.md
  grep -c 'There is no Android app' release/mobile/README.md
  ```

  Expected: `10`, `13`, no output, `0`.

- [ ] **Step 7: Commit**

  ```bash
  git add release/mobile/README.md shellx-android/README.md docs/superpowers/ledgers/shellx-android-parity.md
  git commit -m "docs(release): Android release, Play Console runbook, Data safety, store listing and device checklist"
  ```

---

### Task 9: Verify and hand off

**Files:** `shellx-android/version.properties` (Step 2); after landing, only the facts of Step 7.

- [ ] **Step 1: Bring the branch up to date with `develop`**

  ```bash
  git -C /Users/lehuuphu/Documents/myProjects/shellx pull --ff-only origin develop   # the main checkout is on develop
  git merge --no-edit develop
  python3 shellx-android/scripts/import-strings.py --check || python3 shellx-android/scripts/import-strings.py
  ```

  If `pull --ff-only` fails because `develop` diverged, stop and ask the user. If the importer refuses new iPhone keys, follow plan 3A Task 11 Step 1 (the iPhone-only list or an Android override), and commit with `git add shellx-android/app/src/main/res shellx-android/scripts/strings-ios-only.txt docs/superpowers/ledgers/shellx-android-parity.md` and `git commit -m "feat(shellx-android): import the iPhone strings added on develop"`.

- [ ] **Step 2: Set the first Google Play version (contracts §7)**

  Run: `grep -E '^VERSION_(NAME|CODE)=' shellx-android/version.properties; grep MARKETING_VERSION shellx-ios/Config/Version.xcconfig`

  `VERSION_NAME` must equal the iPhone's `MARKETING_VERSION`; `VERSION_CODE` stays 100 unless Task 0 Step 7's `HIGHEST_CODE` is 100 or more (then `HIGHEST_CODE + 1`). Change only those values, then:

  ```bash
  git add shellx-android/version.properties
  git commit -m "release(shellx-android): first Google Play version <VERSION_NAME> (<VERSION_CODE>)"
  ```

  Skip the commit when nothing changed.

- [ ] **Step 3: Run the full verification**

  ```bash
  python3 -m unittest discover -s release/mobile/tests -t release/mobile/tests
  /usr/bin/python3 -m unittest discover -s release/mobile/tests -t release/mobile/tests
  bash -n release/mobile/android.sh && echo syntax-ok
  python3 release/mobile/play/store_assets.py listing
  shellx-android/scripts/dev.sh test all
  bash scripts/shellx/check-android-license.sh
  bash scripts/shellx/check-ios-license.sh | tail -1
  python3 scripts/verify-local.py
  git status --short
  ```

  Expected: `Ran 62 tests` (63 on Task 7's fallback path) and `OK` twice; `syntax-ok`; `listing ok: en-US, vi`; `==> test all: passed` (with `StoreScreenshotsRenderTest` and `LicencesRowTest` passing and `release checks passed` on the way); `check-android-license: ok`; `check-ios-license: ok`; `verify-local.py` ending with a line that starts with `PASSED:`; and no `git status` output. If a `verify-local.py` check fails, rerun it in the main checkout on `develop` with `--only <check>`: the same failure there is pre-existing; record it in the hand-off and do not fix it.

- [ ] **Step 4: Get a review**

  Follow `skills/cmux-review/SKILL.md` (the default pre-merge review). Give a fresh review subagent this plan's goal, the base `$(git merge-base develop HEAD)`, the head `HEAD` and `git diff develop...HEAD`. Ask for correctness first (a release script that can let a wrong or unsigned bundle through, leak a password or remove the wrong file), then this plan's Global Constraints. Fix concrete findings, rerun Step 3, and get a second review of the repair when the fixes were not trivial.

- [ ] **Step 5: Land the branch (contracts §1)**

  In the main checkout, on `develop`:

  ```bash
  git -C /Users/lehuuphu/Documents/myProjects/shellx status --short | grep -v '^??' || true   # expect no output
  git -C /Users/lehuuphu/Documents/myProjects/shellx merge --no-ff --no-edit feat/shellx-android-3h-release
  git -C /Users/lehuuphu/Documents/myProjects/shellx push origin develop
  ```

  Expected: no tracked changes, a merge commit, a successful push. Never merge to `main`.

- [ ] **Step 6: Build the release candidate and the store assets in the main checkout**

  Skip the bundle when the upload key is pending (Task 0 Step 6), or the Web client id still waits for plan 1D, or Google's G still waits for plan 3D's USER step (Task 4 Step 7), and say so in the hand-off. Otherwise:

  ```bash
  cd /Users/lehuuphu/Documents/myProjects/shellx
  release/mobile/android.sh
  python3 release/mobile/play/store_assets.py graphics
  shellx-android/scripts/dev.sh screenshots record build/release/android/play/render
  python3 release/mobile/play/store_assets.py screenshots --from build/release/android/play/render
  ```

  Expected: `bundle checks passed: com.shellx.prod <VERSION_NAME> (<VERSION_CODE>) …`, `==> build/release/android/ShellX-<VERSION_NAME>-<VERSION_CODE>.aab (and .mapping.txt, .source)` and `Not uploaded. …`; then the three graphics and the screenshot paths. The build refuses uncommitted changes of the user's in `shellx-android/`, `shellx-link/` or `release/mobile/`: never stash or commit them; report and let the user decide.

- [ ] **Step 7: Facts the user gives now**

  When the user does Play 1, Play 2, Play 7 or Play 8 during this session, record the answers in a docs-only follow-up: `git -C .worktrees/android-3h-release switch -c feat/shellx-android-3h-facts develop`; edit the table "Google Play: facts" of `release/mobile/README.md` and, for Play 8, `docs/superpowers/ledgers/shellx-signin-rollout.md` (client 5's SHA-1 and client ID, the "Firebase" section, and "Hand-off to 3D / 3H": each `pending (3H)` item done). When the user ran D4 and D5 as S1 §2.1 criterion 2 (a Google account new to ShellX signs in on the Android app first, then on the Mac, then pairs by QR), also add that row to the rollout ledger's "Live checks" (criterion 2, `com.shellx.prod <VERSION_NAME>` from internal testing, the result, the seconds to signed in, the date), replacing its `pending (3H: Android first, then desktop)`; commit with `docs(release): Google Play facts`; then in the main checkout `git merge --no-ff --no-edit feat/shellx-android-3h-facts` and `git push origin develop`. SHA-1 and SHA-256 fingerprints and client IDs are not secrets; passwords and keys never go there.

- [ ] **Step 8: Hand off**

  Report to the user in Vietnamese:
  - which licence path Task 7 took (Google's plugin, or the fallback and why) and the parity ledger row it added;
  - what landed (the merge commit) and where the release candidate and the store assets are (`build/release/android/…`), or why they wait (upload key, plan 1D's Web client id, Google's G from plan 3D's USER step);
  - whether `RELAY_LIVE` and `MAC_1_8_0` (Task 0 Step 9) are `done`: while either is not, the device checklist's D4–D9 and D11 wait for plan 1D (D7 also needs the first desktop release with the phone terminal, contracts §7);
  - `UPLOAD_SHA256` and `UPLOAD_SHA1`, and every `pending (USER)` fact;
  - the USER steps, in this order, each with its README section: Play 1–Play 2 (if not answered), Play 3 (App content, Data safety after its website check), Play 4–Play 6 (store settings, listing, pricing), Play 7 (internal testing upload, then `release/mobile/android.sh --mark-uploaded`), Play 8 (the App signing SHA-1 for the third Android OAuth client `ShellX Android (Play signing)` and the Firebase API key; contracts §16 and plan 1D), Play 9 (pre-launch report), the device checklist D1–D13 on the phone recorded in Task 0 Step 8, then Play 10 (path A or path B to production; path B needs 12 testers opted in for 14 continuous days);
  - the localization audit: no app string changed; the store listing is checked in English and Vietnamese by `store_assets.py listing`;
  - this plan's "Contract additions" (for the contracts file) and "Spec notes".

---

## Spec notes

1. **More checks than S3 §8 names.** S3 §8 asks `android.sh` for the app id, versionCode, target SDK, no debug code and 16 KB alignment. The brief adds the dirty-tree and origin refusals, the licence check, the R8 mapping and the Firebase file; contracts §16 adds the Google web client id. 3H also refuses anything that would make the Data safety answers false: an extra permission, an analytics, advertising or crash SDK, cleartext traffic, backup. Because the build refuses unpushed commits, the release candidate is built after landing, in the main checkout (Task 9); before landing, Task 4 checks a Gradle-built signed bundle with `--check-aab`.
2. **16 KB pages.** S3 §5 asks for 16 KB alignment when the app has `.so` files. The Android cross-review settled the rule: every `.so` in the bundle, of every ABI, must be 16 KB aligned, always (Google Play requires 16 KB support for new apps and updates that target Android 15 or later since 2025-11-01). 3H also checks Google's GNU_RELRO rule (the segment ends on a 16 KB page, or together with its LOAD segment) and that the bundle asks for 16 KB zip alignment. Google's guidance speaks of 64-bit devices, so a dependency's 32-bit library aligned to 4 KB, which Play itself would accept, stops the release (Task 4 Step 7). Compose and CameraX bring native libraries, so the check runs from the first build (plan 3A Spec note 14).
3. **Target API.** On 2026-11-07 Google Play requires API 36 for new apps and updates (since 2026-08-31; extensions ended 2026-11-01), matching S3 §5. The yearly change becomes a refusal through `release/mobile/android-play-target-sdk.txt` rather than something to remember.
4. **The demo speaks Vietnamese in places.** Plan 3C copies the iPhone demo verbatim: a Mac named "Mac giả", Vietnamese chat text, questions and plans. The Google Play reviewer's demo shows that text, and the English listing leaves out the shots that carry it (Task 6). Localizing the demo's sample data would be a change for plans 1C and 3C together; 3H does not make it.
5. **Data safety beyond S3 §10's list.** The Google ID token the app sends carries the profile name, so "Name" is declared as processed ephemerally; the FCM token is registered after sign-in whether or not notifications are allowed (3C `PushRegistration`), so "Device or other IDs" is required. Two answers are the maintainer's to confirm, as the iPhone's App Privacy answers were: the app version (declared as Diagnostics, the cautious answer) and voice (not collected by ShellX: the phone's speech service hears it).
6. **Android OAuth clients.** S1 §10 says "Android × 2" with three SHA-1s; contracts §16 and plan 1D settle three clients. The Play signing client can exist only after the first upload, so plan 1D leaves it `pending (3H)`, and Play 8 creates it with the user.
7. **Target audience.** Play Console offers age groups; 3H answers "18 and over" only. The privacy policy says the service is not for anyone under 16, which this respects.
8. **OEMs that hold notifications.** S3 §7.4c names Xiaomi, OPPO and vivo; the device checklist also runs its late-notification test on realme, OnePlus and iQOO, which use the same software families.
9. **The listing says "Mac".** Only the Mac app pairs phones: `windows/` has no phone pairing.
10. **The store icon** is the full-bleed logo at full scale (like the iPhone's App Store icon), not the adaptive icon's two-thirds glyphs; Play rounds the corners itself. It is written as RGBA because Play asks for a 32-bit PNG and `rsvg-convert` writes RGB for an opaque image.
11. **Firebase API key.** Contracts §12 and plan 1D restrict only the key's application restrictions and leave its API restrictions unchanged; Play 8 adds only the Play signing entry.
12. **VERSION_NAME.** Contracts §7 ties it to the iPhone's marketing version for the first upload; later builds only print a note when they differ.
13. **No key inside the repository.** The Flutter build read `android/key.properties` as a fallback and debug-signed without a key. The native build has neither: without `SHELLX_ANDROID_KEY_PROPERTIES` the release build is unsigned.
14. **Licence notices.** S3 §6.1 has About › "Giấy phép" open shellx.pro, as the iPhone does. The Android cross-review decided that Android shows the notices of the libraries it ships inside the app: Google's open-source licences screen (`play-services-oss-licenses`, a Google SDK listed by name as S3 §5 allows; its plugin runs only at build time), or, when that plugin does not work with the Android Gradle plugin 3A pins, a bundled list built from the lockfile and each artifact's POM (Task 7). It is an Android-only difference in the parity ledger; the iPhone does not change.

## Contract additions

Add these to the contracts file; this plan does not edit it.

1. **`release/mobile/android.sh` (owner 3H; consumers: every later Android release).** Commands: build (no argument), `--check-aab <file.aab> [<mapping.txt>]`, `--mark-uploaded`. Outputs `build/release/android/ShellX-<VERSION_NAME>-<VERSION_CODE>.aab`, `.mapping.txt`, `.source`, `.uploaded`, logs in `build/release/android/logs/`. It builds only a clean commit on `origin/develop` or `origin/main`, refuses a versionCode marked uploaded, prints `==> upload key: SHA-256 … (SHA-1 …)`, and never uploads.
2. **Release signing.** `shellx-android/app/build.gradle.kts` signs release builds only with the properties file named by `SHELLX_ANDROID_KEY_PROPERTIES` (`storeFile` absolute, `~/…` or relative to that file); without it the release build is unsigned. `dev.sh` unsets the variable. Signed Gradle runs pass `--no-configuration-cache`.
3. **Release data files.** `release/mobile/android-permissions.txt` is the exact, sorted permission set of the release build; a plan that adds a permission updates it and README "Google Play: Data safety" in the same commit, with the user's agreement. `release/mobile/android-play-target-sdk.txt` holds Google Play's target API rules; the build refuses when its newest line is more than 365 days old.
4. **Never in a release build** (checked in the dex files and the R8 mapping): the packages `com.shellx.core.testing`, `com.shellx.app.testing`, `com.shellx.app.screenshots`, `com.shellx.app.debug`, test libraries, Compose tooling (except `@Preview`), OkHttp's logging interceptor, LeakCanary, and the names `FakeRelayAccount`, `FakeIdentityProvider`, `InMemorySecretStore`, `FakeTranscriber`, `FakeVoicePermissions`, `SHELLX_DEMO`. The demo package `com.shellx.core.demo` ships. Debug-only app code goes in `app/src/debug` or `com.shellx.app.debug`.
5. **No analytics, advertising or crash SDK** on the release classpath (Firebase Analytics, Crashlytics, Performance, In-App Messaging; Play services measurement, ads, analytics, App Set), no `com.google.android.gms.permission.AD_ID`, no `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`, no cleartext traffic (`usesCleartextTraffic` or `cleartextTrafficPermitted="true"` in `app/src/main` or `app/src/release`), backup off.
6. **Contracts §16 enforcement.** `google_web_client_id` must match `^[0-9]+-[a-z0-9]+\.apps\.googleusercontent\.com$`, equal the client id of row "ShellX Web (Android sign-in)" in `docs/superpowers/ledgers/shellx-signin-rollout.md` when that cell is filled, and appear in the bundle's resources. The bundle's resource table must also hold Google's G (`drawable/ic_google_g`, plan 3D Contract additions 10).
7. **Store assets.** `release/mobile/play/` holds `store_assets.py`, `feature-graphic.svg` and `listing/<en-US|vi>/{title,short-description,full-description,release-notes,feature-graphic-tagline}.txt`; outputs go to `build/release/android/play/`. Store screenshots are `StoreScreenshotsRenderTest` captures named `store-<NN>-<slug>` at `w360dp-h640dp-xxhdpi`, listed in `SHOTS`. The listing quotes the app labels "Try without an account", "Settings", "Account", "Delete Account…" (and their Vietnamese strings): a plan that renames one updates the listing.
8. **Google Play facts.** `release/mobile/README.md` "Google Play: facts" holds the account type and path, the highest versionCode, the upload and app signing SHA-256s, the internal testing link and the closed-test date. SHA-1s and OAuth client IDs stay in plan 1D's rollout ledger; 3H's Play 8 fills its `pending (3H)` items (client 5, the Firebase key's Play signing entry).
9. **Tests.** `release/mobile/tests/` (unittest) runs in `dev.sh test all`.
10. **Licence notices (owner 3H; consumers: any plan that changes Settings › About or the dependencies).** Settings › About › Licenses calls `com.shellx.app.ui.settings.openLicences(context)`, which opens Google's `com.google.android.gms.oss.licenses.v2.OssLicensesMenuActivity` (plugin `com.google.android.gms.oss-licenses-plugin`, library `com.google.android.gms:play-services-oss-licenses`, both resolved from Google's Maven) or, on Task 7's fallback path, `com.shellx.app.ui.settings.LicencesActivity` over `assets/licenses/third_party_licenses.txt`, written by `shellx-android/scripts/generate-licences.py` (`dev.sh` and `android.sh` refuse a stale file). `check_android_bundle.licence_notice_problems` refuses a release bundle without the notices. `MainActivity` stays the only launcher activity; the licence screen's activity is not a launcher.
