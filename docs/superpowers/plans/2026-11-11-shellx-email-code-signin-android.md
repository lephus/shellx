# ShellX Email Code Sign-in, Android Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Execution (decided):** one implementer runs Tasks 0–11 in order on branch `feat/shellx-email-code-signin-android` (worktree `.worktrees/email-code-signin-android`, from `develop`), commits per task with the failing test first, and stops after Task 11. One whole-branch review follows. The implementer never merges, pushes, or touches the phone.

**Goal:** The Android app signs in with an email address and a 6-digit code next to "Continue with Google", shows "Email code" in Settings › Account, and deletes an email account by a mailed code.

**Architecture:** `link-account` gains the relay's three calls and `EmailChallenge`. `:core` gains `AccountAuthMethod` (stored with the session), five `SignInException` cases, four `AppCoordinator` calls, and `EmailSignInModel`: a main-confined step holder (idle → email → sending → code → verifying → done) whose resend countdown is read from the injected `Clock`. `:app` adds an "or" line and "Continue with email" to the sign-in screen's button column; the email and code steps replace that column in the same screen, under a small logo and the title. Settings reuses the model, without auto-submit, for deletion by code.

**Tech Stack:** Kotlin 2.4, kotlinx-coroutines, kotlinx-serialization-json, OkHttp 5 (`link-account`); Jetpack Compose 1.11 with Material 3, lifecycle-viewmodel-compose, activity-compose (`:app`). Tests: JUnit 5 + mockwebserver3 (link), JUnit 5 + kotlinx-coroutines-test (`:core`), JUnit 4 + Robolectric + Compose UI test + Roborazzi (`:app`). No new dependency.

**Spec:** `docs/superpowers/specs/2026-11-10-shellx-email-code-sign-in-design.md` (Vietnamese): §3, §4, §7 ("Chung", the strings paragraph, **Android**), the Android lines of §8–§10. §11 is answered: all four apps; link by verified email (relay side, nothing on the phone); default sender; every small default stands. Conventions: `docs/superpowers/plans/2026-11-07-shellx-mobile-contracts.md` §5, §14, §22, §24–§26; the header of `docs/superpowers/plans/2026-11-07-shellx-android-3d-ui-shell.md`. The sign-in screen this plan changes is the animated one merged in `5b2751237f` (report and review: `.superpowers/sdd/2026-11-11-android-phone-check-followups/signin-intro-android-{report,review}.md` in the main checkout).

## Global Constraints

- Relay API, the only source of truth for shapes and codes (spec §4). Errors are `{"error":{"code","message"}}`; a relay without the feature answers `404 not_found`.

  ```
  POST /v1/auth/email/code     {email, locale?: "en"|"vi"}
    -> 202 {challenge_id, expires_in: 600, resend_in: 60, email}      email normalized (trim, lowercase)
       400 invalid_email | 400 disposable_email | 429 rate_limited
       503 email_sign_in_disabled | 502 email_send_failed
  POST /v1/auth/email/verify   {challenge_id, code, device}           device as /v1/auth/google
    -> 200 {user_id, device_id, token, email}
       401 invalid_code | 410 code_expired | 409 switch_from_signed_in_device
       400 invalid_device | 429 rate_limited
  DELETE /v1/account           bearer + {challenge_id, code}
    -> 204; 401 invalid_code | 410 code_expired | 401 reauth_required
  ```
- Code: 6 digits, lives 600 s, 5 guesses, one live code per address; "Resend code" is locked for `resend_in` (60 s). "Continue with email" is always shown; no discovery call.
- Tests script the relay (`ApiServer`, `FakeRelayAccount`, `ScriptedRelay`). Nothing here needs a running relay, a real email or a key.
- Never log or print a token, the code, the `challenge_id` or an email address: every new type holding one prints `<redacted>` in `toString()`; logs go through `CoreLog` with event names only.
- Application id stays `com.shellx.prod`. No developer-account, signing or Firebase console action. No new dependency: no lockfile and no allowlist change.
- Never `gradlew --stop`. Every Gradle, test and git command runs through `toknix run`.
- The phone (Pixel 3, serial `93BX1XMU7`) is in the user's hand: never an adb command that could reach it. An emulator only in Task 10 Step 4, with `-s <emulator serial>` on every adb call.
- Licence boundary (3A): only `shellx-android/`, `shellx-link/kotlin/`, `shellx-ios/ShellX/Localizable.xcstrings` and the contracts file of Task 11. Never copy from `ios/`, `Packages/`, `Sources/`, `cmux-tui/` or `shellx-core/`; never write the upstream company name.
- Strings: every visible string comes from the generated `strings.xml` or `strings_android.xml`; generated files are never hand-edited. Catalog keys are the spec's names; the catalog is shared with the iPhone, so Task 1's table is the iPhone plan's (Ruling 21).
- Look: `ShellXTheme` colours only, no gradient, accent text `ShellXTheme.colors.accentText`, errors `StatusTone.ERROR.color()`, touch targets ≥ 48 dp, waits drawn with `Spinner` (`LocalSpinner`: renders need a still one).
- Threading: `:core` models are main-confined; the vault does its own `io`.
- Commits: failing tests first (`test(shellx-android): …`, `test(shellx-link): …`), then the code (`feat(…)`), always `git add <paths>`. Never commit this plan on the branch.

## Review Focus

Inputs most likely to bite a person here, each pinned by a test in its owning task:

1. **A pasted code with spaces or other text** ("123 456", "Your ShellX sign-in code is 123456", full-width digits): only its first six digits count, and it signs in. Task 6 `aPastedCodeKeepsItsDigits`; Task 7 `theCodeFieldShowsOnlySixDigits`; Task 10 smoke test types "123 456".
2. **A code typed after it expired** (or after five wrong tries): the relay's 410 says so under the field, the field goes off, and Resend is open at once, also mid-countdown. Task 6 `anExpiredCodeOpensResendAtOnce`; Task 8 `anExpiredCodeOffersResendAtOnce`.
3. **A double tap on Verify, or a tap right after the sixth digit auto-submitted:** one request. Task 5 `aSecondVerifyWhileOneRunsJoinsIt`; Task 6 `verifyTappedTwiceVerifiesOnce`; Task 8 `aCodeSignsInOnceAndAutoSubmits`.
4. **Leaving the app to read the email and coming back:** the step, the address and the digits are there; the countdown shows the real time left; if Android killed the app meanwhile, it comes back to the code step (to the email step with "expired" after 10 minutes). Task 6 `timeAwayCountsEvenWhenNothingTicked`, `aKilledAppComesBackToTheCodeStep`; Task 7 `aKilledAppComesBackToTheCodeStepWithTheTimeLeft`; Task 8 `aSavedCodeStepIsShownAtOnce`; Task 10 Step 4 (emulator, "Don't keep activities").
5. **Rotation in the code step:** nothing is asked or sent again. Task 8 `theCodeStepSurvivesARotation`.
6. **A very long email address:** the field stops at 254 characters; the "sent to" line wraps inside the window and the code field stays reachable. Task 6 `aLongEmailIsCutAt254`; Task 8 `aVeryLongEmailWrapsInsideTheWindow`.
7. **Offline:** the step stays with "Can't reach ShellX." and what was typed; Verify works on a second tap without retyping, and nothing retries by itself. Task 6 `offlineKeepsTheCodeForAnotherTry`; Task 8 `offlineKeepsWhatWasTyped`.
8. **The sixth digit in the deletion dialog:** it never deletes by itself; only a tap on Delete Account does. Task 6 `withoutAutoSubmitSixDigitsWait`; Task 9 `deletingAnEmailAccountAsksForACodeAndNeedsATap`.

## Rulings

Where the spec and the code disagree the plan follows the code; where the spec is silent the plan decides.

1. **Autofill API.** The spec says `autofillHints`; Compose 1.11.4 has `Modifier.semantics { contentType = … }` (`androidx.compose.ui.autofill.ContentType`). Email field: `ContentType.Username + ContentType.EmailAddress`. Code field: `ContentType.SmsOtpCode + ContentType("emailOTPCode")` (no email constant exists; the app's `androidx.autofill` 1.0.0 has none either). Best effort: Android does not read codes out of emails, so paste is the path that must work.
2. **`deleteAccountWithEmailCode`.** Kotlin cannot overload `deleteAccount(idToken, nonce, token)` on parameter names (the Swift name is `deleteAccount(challengeID:code:)`).
3. **No sign-in-method row exists on Android.** For an `email` session the e-mail row's label is `settings_account_method_email` ("Email code") and its value the address; a Google session keeps "Email".
4. **Stored key `auth_method`,** the iPhone's key (`AccountVault` uses the iPhone's key names). Absent → `google` (spec); an unknown value → the session is unreadable, as on the iPhone.
5. **404 and 503.** `503 email_sign_in_disabled` and any 404 on one of the three email calls (the relay's `not_found`, or a proxy's 404 with no JSON) → `ProviderUnavailable`. The Google paths' 404 mapping is unchanged.
6. **One code field** (spec §10), `KeyboardType.Number`: paste and autofill work, TalkBack reads one field.
7. **Auto-submit only for sign-in.** The deletion dialog needs a tap.
8. **After a wrong code** the field is cleared (six new digits submit again); after `code_expired` the field is off and Resend opens; after any other failure (but Ruling 23's) the digits stay for another tap.
9. **Countdown time base:** `Clock.nowMs()`, not `Clock.monotonic`: the deadlines must survive the process, a monotonic mark cannot. The count is advice; the relay enforces the limit (429).
10. **Process death.** The email, the `challenge_id` and its two deadlines go into the activity's saved state (above the NavHost: `RootSync` replaces the restored `sign_in` entry at start, so entry-scoped state would be lost). The typed code is never saved. Security: the `challenge_id` alone cannot sign in (it needs the mailed code, five tries).
11. **The intro while an email step shows:** small logo (72 dp) and the title only: no taglines, no subtitle, no steps; top-aligned; the same with the keyboard up or down. The intro's clock keeps running (the logo's cursor and glow).
12. **The screen's room is measured without the keyboard** (`systemBars ∪ displayCutout`, then `imePadding()` on the scroll container). With `safeDrawing` the layout rule would switch while the keyboard moves, and on a foldable could flip between one and two columns, dropping the field's focus (intro review, Minor 8).
13. **The taller button column needs room** (measured on the intro's renders: 48 dp spare on the Pixel 3 at font scale 1.3 in English, about 93 dp needed). In one column the subtitle now needs 800 dp of height (was 700) and the three steps 660 dp (was 400). Two-column windows keep 700 and 400. The Pixel 3 (713 dp) loses the subtitle; a 360 × 592 dp window loses the steps.
14. **Button order:** Google, "or", Continue with email, Try without an account. In the email step the demo link stays (spec); in the code step it is not shown.
15. **"Session expired" and a Google failure** show on the first step only. An email failure shows under its field.
16. **Back:** code step → email step → first step; ignored while a request is on the relay.
17. **Spam hint** (spec §9) has no key in the spec's list: it is the second sentence of `signin.email.sentTo %@` (the iPhone plan decided the same).
18. **Deletion dialog for an email session** keeps `settings_account_delete_message` ("…you sign in once more") on its first step, has Resend with the sign-in strings, and is not restored after process death. `401 reauth_required` there keeps its existing words.
19. **`signin_subtitle` (Android override)** now names both ways in; it said "Google account" only.
20. **No relay URL override for a manual test** (spec §10): the emulator check sends nothing to the relay (orchestrator's ruling, 2026-11-11: no test traffic to production).
21. **One catalog, one table.** The 18 keys, their values and comments are the iPhone plan's (`2026-11-11-shellx-email-code-signin-ios.md`, Task 1). Its two format keys carry their argument in the key (`signin.email.sentTo %@`, `signin.email.resendIn %lld`), as 42 keys of this catalog do; the importer drops the signature, so the Android names are the spec's (`signin_email_sent_to`, `signin_email_resend_in`).
22. **The Mac words a few of these differently** in its own catalog (`2026-11-11-shellx-email-code-signin-core-mac.md`, String table: "Xác minh" for Verify, other sentences for an invalid address and a dead code). The phones follow the phone catalog; evening the words out is the orchestrator's call.
23. **A 409 `switch_from_signed_in_device` on verify** returns to the email step with its words (the iPhone plan's rule): that address cannot go on.
24. **`deleteAccount()` on an email session** throws `Server("code_required")` and calls nothing (the iPhone plan's rule): Google's sheet never opens for an email account.
25. **No Cancel button in the email step** (the iPhone plan adds one): on Android the system's Back is the way back (Ruling 16).

## Conventions

- **Path prefixes.** `link/` = `shellx-link/kotlin/link-account/src/main/kotlin/com/shellx/link/account/`; `link-test/` = the same under `src/test/`; `core/` = `shellx-android/core/src/main/kotlin/com/shellx/core/`; `core-test/` = the same under `src/test/`; `app/` = `shellx-android/app/src/main/kotlin/com/shellx/app/`; `res/` = `shellx-android/app/src/main/res/`; `app-test/` = `shellx-android/app/src/test/kotlin/com/shellx/app/` (runs in debug and release); `app-ui-test/` = `shellx-android/app/src/testDebug/kotlin/com/shellx/app/` (Compose UI and render tests).
- **Commands.** Paste at the start of every shell call that uses them:

  ```bash
  export JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home ANDROID_HOME="$HOME/Library/Android/sdk"
  R="$(git rev-parse --show-toplevel)"
  ga() { toknix run "$R/shellx-android/gradlew" -p "$R/shellx-android" --console=plain "$@"; }      # :core, :app
  gl() { toknix run "$R/shellx-link/kotlin/gradlew" -p "$R/shellx-link/kotlin" --console=plain "$@"; }  # link
  ```

  One class: `gl :link-account:test --tests 'com.shellx.link.account.<Class>'`, `ga :core:test --tests 'com.shellx.core.<…>'`, `ga :app:testDebugUnitTest --tests 'com.shellx.app.<…>'`. **Red** ends with `BUILD FAILED` and the named compile error or failing test; **green** ends with `BUILD SUCCESSFUL` and no `FAILED`. Full runs: `toknix run shellx-android/scripts/dev.sh test link|core|app` (`==> test <which>: passed`). Git commands go through `toknix run` too (`toknix run git commit -m …`); the steps below show them bare.
- **Test styles.** link: JUnit 5, `runBlocking`, `ApiServer` (`AccountTestSupport.kt`). `:core`: JUnit 5 + `kotlin.test`, `runTest` block bodies, long-lived objects in `backgroundScope`, `assertSameCase` for exceptions, `ManualClock`, `Gate`. `:app`: JUnit 4, `@RunWith(AndroidJUnit4::class)`; Compose tests use `createAndroidComposeRule<ComponentActivity>()`; a test that needs the still intro wraps itself in `ShellXSnapshots.withoutAnimations { }`; renders are `assertRenders("<name>") { }` (light-en, dark-en, light-vi, dark-vi) and never focus a field.
- **Test blocks below** give each test's name, its inputs and its assertions with the exact values; the implementer writes the bodies.

## File map

| Area | Files | Task |
| --- | --- | --- |
| Strings | `shellx-ios/ShellX/Localizable.xcstrings`, `res/values*/strings_android.xml`, generated `res/values*/strings.xml` | 1 |
| Relay calls | `link/ApiModels.kt`, `link/RelayApi.kt` | 2 |
| Session | `core/account/{AccountAuthMethod,StoredSession,AccountVault,AppPhase,AppCoordinator}.kt` | 3 |
| Errors, relay interface | `core/account/{SignInException,RelayAccountCalling,RelayAccountClient}.kt`, `core/demo/DemoRelay.kt`, `app/ui/signin/SignInErrorText.kt`, fakes | 4 |
| Coordinator | `core/account/AppCoordinator.kt` | 5 |
| Step model | `core/account/{EmailCodeActions,EmailSignInModel}.kt` | 6 |
| Step components | `app/ui/signin/{EmailSteps,EmailSignInButton,EmailSignInHolder}.kt` | 7 |
| Sign-in screen | `app/ui/signin/SignInView.kt`, `app/ui/nav/ShellXNavHost.kt` | 8 |
| Settings | `app/ui/settings/{AccountSection,DeleteAccountDialog,SettingsScreen}.kt`, `app/ui/nav/ShellXNavHost.kt` | 9 |
| Whole app | `app-ui-test/{ShellXAppSmokeTest,ShellXAppHostTest}.kt` | 10 |
| Docs | `docs/superpowers/plans/2026-11-07-shellx-mobile-contracts.md` | 11 |

---

### Task 0: Worktree, preconditions, baseline

**Files:** none.

- [ ] **Step 1: Create the worktree.** `git worktree add .worktrees/email-code-signin-android -b feat/shellx-email-code-signin-android develop`. Work only there. Read this plan and the spec from the main checkout (`/Users/richard/Documents/helper/shellx/docs/superpowers/…`) if the worktree lacks them.
- [ ] **Step 2: Check what this plan builds on.**

  ```bash
  S=shellx-android/app/src/main/kotlin/com/shellx/app/ui
  grep -q 'object SignInIntro' $S/signin/SignInView.kt && grep -q 'fun TapOutsideHidesKeyboard' $S/components/TapOutsideKeyboard.kt \
    && grep -q '"signin.guide.1"' shellx-ios/ShellX/Localizable.xcstrings && echo ready
  ```

  Expected: `ready`. Otherwise stop and report "the sign-in intro (5b2751237f) must be on develop".
- [ ] **Step 3: Read** `app/ui/signin/*.kt`, `app-ui-test/ui/signin/{SignInViewTest,SignInFitTest}.kt`, `app-test/ui/signin/SignInLayoutTest.kt`, `app/ui/components/TapOutsideKeyboard.kt`, `app/ui/settings/{AccountSection,DeleteAccountDialog}.kt`, `core/account/*.kt`, `link/{RelayApi,ApiModels}.kt`, `app-test/testing/ScriptedRelay.kt`, `app-ui-test/ui/CompactHeightTest.kt` (how it hands the window a keyboard inset). If a name this plan uses from the sign-in screen (`SignInLayout`, `SignInContent`, `Hero`, `Actions`, the tags) changed in a later fix on `develop`, use the real one and list it in your report.
- [ ] **Step 4: Baseline.** `toknix run shellx-android/scripts/dev.sh test all`. Expected: `==> test all: passed`. If it fails before any change, stop and report.

---

### Task 1: Strings

**Files:**
- Modify: `shellx-ios/ShellX/Localizable.xcstrings`, `res/values/strings_android.xml`, `res/values-vi/strings_android.xml`
- Generate: `res/values/strings.xml`, `res/values-vi/strings.xml`
- Test: `app-test/StringsTest.kt`

**Interfaces:**
- Produces: the Android names below (`R.string.<name>`); `signin_email_sent_to` takes `%1$s`, `signin_email_resend_in` takes `%1$d`. Keys, values and comments are those of the iPhone plan's table (`docs/superpowers/plans/2026-11-11-shellx-email-code-signin-ios.md`, Task 1), character for character: one catalog serves both phones (Ruling 21).

| Catalog key | Android name | en | vi |
| --- | --- | --- | --- |
| `signin.email.continue` | `signin_email_continue` | Continue with email | Tiếp tục với email |
| `signin.email.or` | `signin_email_or` | or | hoặc |
| `signin.email.field` | `signin_email_field` | Email address | Địa chỉ email |
| `signin.email.send` | `signin_email_send` | Send code | Gửi mã |
| `signin.email.sentTo %@` | `signin_email_sent_to` | We sent a 6-digit code to %@. If it isn't there in a minute, check your spam folder. | Đã gửi mã 6 chữ số tới %@. Nếu sau một phút chưa thấy, hãy xem cả thư rác. |
| `signin.email.code` | `signin_email_code` | 6-digit code | Mã 6 chữ số |
| `signin.email.verify` | `signin_email_verify` | Verify | Xác nhận |
| `signin.email.resend` | `signin_email_resend` | Resend code | Gửi lại mã |
| `signin.email.resendIn %lld` | `signin_email_resend_in` | Resend code in %lld s | Gửi lại mã sau %lld giây |
| `signin.email.change` | `signin_email_change` | Use a different email | Dùng email khác |
| `signin.error.invalidEmail` | `signin_error_invalid_email` | That doesn't look like an email address. | Địa chỉ email này chưa đúng. |
| `signin.error.disposableEmail` | `signin_error_disposable_email` | Temporary email addresses can't be used. Try another address. | Không dùng được địa chỉ email tạm thời. Hãy dùng địa chỉ khác. |
| `signin.error.invalidCode` | `signin_error_invalid_code` | That code isn't right. Check the email and try again. | Mã chưa đúng. Xem lại email rồi thử lại. |
| `signin.error.codeExpired` | `signin_error_code_expired` | That code no longer works. Send a new one. | Mã này không còn dùng được. Hãy gửi mã mới. |
| `signin.error.emailSendFailed` | `signin_error_email_send_failed` | Couldn't send the email. Try again in a moment. | Chưa gửi được email. Thử lại sau giây lát. |
| `settings.account.method.email` | `settings_account_method_email` | Email code | Mã qua email |
| `settings.account.delete.codeIntro` | `settings_account_delete_code_intro` | We sent a 6-digit code to this account's email address. Enter it to delete the account. | Đã gửi mã 6 chữ số tới địa chỉ email của tài khoản này. Nhập mã để xoá tài khoản. |
| `settings.account.delete.codeField` | `settings_account_delete_code_field` | Code from the email | Mã trong email |

Android override (both `strings_android.xml` files; Ruling 19): `signin_subtitle` → "Use the Google account or the email address you use with ShellX on your Mac." / "Dùng tài khoản Google hoặc địa chỉ email bạn dùng với ShellX trên Mac."

- [ ] **Step 1: See where the catalog stands.** `python3 shellx-android/scripts/import-strings.py --check` (expected `import-strings: ok (N strings, 1 plurals)`; note N). List which of the 18 keys the catalog already has (another part may have landed them). For a key that exists, keep its value and use it; add only the missing ones. Report every value that differs from the table. Then compare the table with the iPhone plan's as it stands now: where they differ, the iPhone plan's key, value and comment win; report each difference.
- [ ] **Step 2: Write the failing test** (add to `StringsTest`; `text(id, language)` is its helper; a formatted string is `ApplicationProvider.getApplicationContext<Context>().getString(id, arg)` after `RuntimeEnvironment.setQualifiers("+$language")`):

```kotlin
// theEmailSignInStringsCameOver:
//   en: signin_email_continue == "Continue with email"; signin_email_resend_in with 42 == "Resend code in 42 s";
//       signin_email_sent_to with "phu@example.com" starts with "We sent a 6-digit code to phu@example.com."; settings_account_method_email == "Email code"
//   vi: signin_email_or == "hoặc"; signin_email_resend_in with 42 == "Gửi lại mã sau 42 giây"; signin_email_verify == "Xác nhận"
//   each of the 18 names: the en and vi texts are not empty and differ
// theSubtitleNamesBothWaysIn: signin_subtitle contains "email" in en and in vi, and "Google" in both
```

- [ ] **Step 3: Run (red).** `ga :app:testDebugUnitTest --tests 'com.shellx.app.StringsTest'`. Expected: `Unresolved reference` to `signin_email_continue` (or another new name).
- [ ] **Step 4: Commit the test.** `git add shellx-android/app/src/test/kotlin/com/shellx/app/StringsTest.kt`; `git commit -m "test(shellx-android): email sign-in strings"`.
- [ ] **Step 5: Add the keys to the catalog** with a Python snippet: load the JSON, insert each missing key right after the last existing key with the same first two segments (`signin.email`, `signin.error.*`, `settings.account.*`), each as `{"comment": "<the iPhone plan's comment for the key>", "extractionState": "manual", "localizations": {"en": {"stringUnit": {"state": "translated", "value": …}}, "vi": {…}}}`, and write `json.dumps(catalog, indent=2, ensure_ascii=False) + "\n"` (the file round-trips with exactly this). Then edit the two `signin_subtitle` overrides.
- [ ] **Step 6: Generate and check.** `python3 shellx-android/scripts/import-strings.py && python3 shellx-android/scripts/import-strings.py --check && python3 shellx-ios/scripts/check-strings.py`. Expected: `import-strings: ok (N+18 strings, 1 plurals)` (291 when N was 273) and `check-strings: ok (… keys)`.
- [ ] **Step 7: Run (green).** The Step 3 command: PASS.
- [ ] **Step 8: Commit.** `git add shellx-ios/ShellX/Localizable.xcstrings shellx-android/app/src/main/res`; `git commit -m "feat(shellx-mobile): email sign-in strings (shared catalog, Android import)"`.

---

### Task 2: link-account: the three relay calls

**Files:**
- Modify: `link/ApiModels.kt`, `link/RelayApi.kt`
- Test: `link-test/RelayApiEmailTest.kt` (new)

**Interfaces:**
- Produces (`com.shellx.link.account`):

```kotlin
/** What the relay answers to a code request. Neither the challenge nor the email prints. */
data class EmailChallenge(val challengeId: String, val expiresIn: Int, val resendIn: Int, val email: String)
    // toString(): "EmailChallenge(expiresIn=…, resendIn=…, <redacted>)"

// on RelayApi; each throws RelayApiException or the transport's IOException, like its neighbours
suspend fun requestEmailCode(email: String, locale: String): EmailChallenge            // POST /v1/auth/email/code, no bearer
suspend fun signInWithEmailCode(challengeId: String, code: String, deviceName: String, clientKey: ByteArray): AccountSignIn  // POST /v1/auth/email/verify, no bearer
suspend fun deleteAccountWithEmailCode(challengeId: String, code: String, token: String)   // DELETE /v1/account, bearer
```

  Reading the 202: `challenge_id` must be 1–128 characters of the base64url alphabet (the rule `nonce()` has), `expires_in` in 1..86 400, `resend_in` in 0..86 400; otherwise `RelayApiException.BadResponse`. The `device` object and the `{user_id, device_id, token, email}` reply are `signInWithGoogle`'s: share them through two private helpers.

- [ ] **Step 1: Write the failing tests.**

```kotlin
class RelayApiEmailTest {   // ApiServer, clientKey = ByteArray(32) { (0x20 + it).toByte() }, challenge = "aB3_-".repeat(8) + "xyz"
    // requestEmailCodeSendsTheEmailAndTheLocale: reply(202, {"challenge_id":challenge,"expires_in":600,"resend_in":60,"email":"foo@bar.com"})
    //   → EmailChallenge(challenge, 600, 60, "foo@bar.com"); request POST /v1/auth/email/code, no Authorization,
    //   body == {"email":"Foo@Bar.com","locale":"vi"} for requestEmailCode("Foo@Bar.com", "vi")
    // theChallengeNeverPrints: toString() contains neither the challenge id nor "foo@bar.com"
    // aCodeReplyNeedsEveryFieldInRange: BadResponse for: no email; "challenge_id":7; "challenge_id":"has space"; "" ; 129 chars;
    //   "expires_in":0; "expires_in":"600"; "resend_in":-1; "resend_in":86401
    // codeRequestErrorsSurface: (400,"invalid_email"), (400,"disposable_email"), (429,"rate_limited"), (503,"email_sign_in_disabled"),
    //   (502,"email_send_failed"), (404,"not_found") → RelayApiException.Http(status, code)
    // signInWithEmailCodeSendsTheAndroidDevice: reply(200, {"user_id":"u1","device_id":"d1","token":"tok-secret","email":"a@b.c"})
    //   → AccountSignIn(AccountSession("u1","d1","tok-secret"), "a@b.c"); POST /v1/auth/email/verify, no Authorization;
    //   body keys == {challenge_id, code, device}; challenge_id == "c-1"; code == "123456"; device ==
    //   {kind: mobile, name: "Pixel 9", platform: android, public_key: "ICEiIyQlJicoKSorLC0uLzAxMjM0NTY3ODk6Ozw9Pj8"}
    // verifyNeedsEveryReplyField: the three bad replies of RelayApiAccountTest.signInNeedsEveryReplyField → BadResponse
    // verifyErrorsSurface: (401,"invalid_code"), (410,"code_expired"), (409,"switch_from_signed_in_device"), (400,"invalid_device"), (429,"rate_limited")
    // deleteAccountWithEmailCodeSendsTheChallengeAndTheCode: reply(204) → DELETE /v1/account, "Bearer tok",
    //   body == {"challenge_id":"c-1","code":"123456"}; then (401,"invalid_code"), (410,"code_expired"), (401,"reauth_required") surface
}
```

- [ ] **Step 2: Run (red).** `gl :link-account:test --tests 'com.shellx.link.account.RelayApiEmailTest'`. Expected: `Unresolved reference: requestEmailCode`.
- [ ] **Step 3: Commit the tests.** `git add shellx-link/kotlin/link-account/src/test`; `git commit -m "test(shellx-link): email code request, verify and deletion calls"`.
- [ ] **Step 4: Implement** `EmailChallenge` and the three calls; update the `// Account` comment in `RelayApi.kt` ("no password login, no Apple sign-in and no Google link").
- [ ] **Step 5: Run (green).** The Step 2 command (8 tests), then `toknix run shellx-android/scripts/dev.sh test link`: `==> test link: passed`.
- [ ] **Step 6: Commit.** `git add shellx-link/kotlin/link-account/src/main`; `git commit -m "feat(shellx-link): relay calls for email code sign-in and deletion"`.

---

### Task 3: The session remembers how it signed in

**Files:**
- Create: `core/account/AccountAuthMethod.kt`
- Modify: `core/account/{StoredSession,AccountVault,AppPhase,AppCoordinator}.kt`
- Test: `core-test/account/AccountVaultTest.kt`, `core-test/account/AppCoordinatorGoogleTest.kt`

**Interfaces:**
- Produces (`com.shellx.core.account`):

```kotlin
/** How the stored session signed in; mirrors the relay's tokens.auth_method (Android never holds password or apple). */
enum class AccountAuthMethod(val wire: String) { GOOGLE("google"), EMAIL("email");
    companion object { fun ofWire(wire: String): AccountAuthMethod? } }
data class StoredSession(val userId: String, val deviceId: String, val token: String, val email: String,
                         val authMethod: AccountAuthMethod = AccountAuthMethod.GOOGLE)
// AppPhase
data class SignedIn(val email: String, val authMethod: AccountAuthMethod = AccountAuthMethod.GOOGLE) : AppPhase
```

  Vault format: the session JSON gains `"auth_method": "<wire>"` after the four existing keys (always written). Decoding: no `auth_method` → `GOOGLE`; a string `ofWire` knows → it; anything else → null (unreadable). `AppCoordinator.load()` sets `AppPhase.SignedIn(session.email, session.authMethod)`; `completeSignIn` gains a parameter `method: AccountAuthMethod` (Google passes `GOOGLE`) and stores and publishes it.

- [ ] **Step 1: Write the failing tests.**

```kotlin
// AccountVaultTest (raw bytes go in with store.write(bytes, SecretItem.SESSION))
// aSessionStoredBeforeAuthMethodsIsAGoogleSession: raw {"userID":"u1","deviceID":"d1","token":"t","email":"a@b.c"}
//   → session() == StoredSession("u1","d1","t","a@b.c", AccountAuthMethod.GOOGLE)
// theAuthMethodIsStoredUnderTheIPhonesKey: setSession(StoredSession("u1","d1","t","a@b.c", EMAIL)) → raw JSON has
//   "auth_method":"email" and still userID "u1", deviceID "d1", token "t", email "a@b.c"; session() equals what was set
// anUnknownAuthMethodIsUnreadable: raw with "auth_method":"passkey" → session() == null; with "auth_method":7 → null
// AppCoordinatorGoogleTest
// aGoogleSignInStoresAGoogleSession: after signInWithGoogle() → vault.session()?.authMethod == GOOGLE; phase == AppPhase.SignedIn("g@example.com", GOOGLE)
// anEmailSessionIsShownAsOneAfterARelaunch: vault.setSession(StoredSession("u1","d1","tok-old","e@example.com", EMAIL)); launch()
//   → phase == AppPhase.SignedIn("e@example.com", AccountAuthMethod.EMAIL)
```

- [ ] **Step 2: Run (red).** `ga :core:test --tests 'com.shellx.core.account.AccountVaultTest' --tests 'com.shellx.core.account.AppCoordinatorGoogleTest'`. Expected: `Unresolved reference: AccountAuthMethod`.
- [ ] **Step 3: Commit the tests.** `git add shellx-android/core/src/test`; `git commit -m "test(shellx-android): the stored session carries its sign-in method"`.
- [ ] **Step 4: Implement.** Update `AccountVault`'s format comment.
- [ ] **Step 5: Run (green).** The Step 2 command, then `toknix run shellx-android/scripts/dev.sh test core`: passed.
- [ ] **Step 6: Commit.** `git add shellx-android/core/src/main`; `git commit -m "feat(shellx-android): StoredSession.authMethod, stored as auth_method (absent: google)"`.

---

### Task 4: Failures in words, and the relay interface

**Files:**
- Modify: `core/account/{SignInException,RelayAccountCalling,RelayAccountClient}.kt`, `core/demo/DemoRelay.kt`, `app/ui/signin/SignInErrorText.kt`
- Modify (fakes): `core-test/testing/FakeRelayAccount.kt`, `core-test/link/MachineHubTest.kt` (`GatedGrantsRelay`), `app-test/testing/ScriptedRelay.kt`
- Test: `core-test/account/{SignInExceptionTest,RelayAccountClientTest}.kt`, `app-test/ui/signin/SignInErrorTextTest.kt`

**Interfaces:**
- Consumes: Task 2's calls and `EmailChallenge`; Task 1's `signin_error_*` names.
- Produces:

```kotlin
// SignInException: five new cases (no fields)
class InvalidEmail; class DisposableEmail; class InvalidCode; class CodeExpired; class EmailSendFailed
// of(error) gains, before `else -> Server(error.code)`:
//   Http(400,"invalid_email") → InvalidEmail; Http(400,"disposable_email") → DisposableEmail; Http(401,"invalid_code") → InvalidCode;
//   Http(410,"code_expired") → CodeExpired; Http(502,"email_send_failed") → EmailSendFailed; Http(503,"email_sign_in_disabled") → ProviderUnavailable
/** For the three email calls: any Http 404 → ProviderUnavailable (a relay without the feature); everything else as [of]. */
fun ofEmail(error: Throwable): SignInException

// RelayAccountCalling: three new members, same signatures as Task 2's RelayApi calls
suspend fun requestEmailCode(email: String, locale: String): EmailChallenge
suspend fun signInWithEmailCode(challengeId: String, code: String, deviceName: String, clientKey: ByteArray): AccountSignIn
suspend fun deleteAccountWithEmailCode(challengeId: String, code: String, token: String)
```

  Implementers: `RelayAccountClient` delegates to `api`; `DemoRelay` throws `REFUSAL`; `GatedGrantsRelay` delegates to `base`.
  - `FakeRelayAccount`: `Call.RequestEmailCode(email, locale)`, `Call.SignInWithEmailCode(challengeId, code, deviceName, clientKeyHex)`, `Call.DeleteAccountWithEmailCode(challengeId, code, token)`; `Function.REQUEST_EMAIL_CODE`, `SIGN_IN_WITH_EMAIL_CODE`, `DELETE_ACCOUNT_WITH_EMAIL_CODE`; `setEmailSignIn(result: Result<AccountSignIn>)` (default `AccountSignIn(AccountSession("user", "device", "token"), "user@example.com")`). A code request answers `EmailChallenge("challenge-<n>", 600, 60, email.trim().lowercase())`, n counting from 1.
  - `ScriptedRelay`: `@Volatile var emailCode: Result<EmailChallenge>? = null` (null: the same numbered challenge), `emailSignIn: Result<AccountSignIn>` (default as `signIn`), `deleteByCode: Result<Unit>`; records `"email:code:<email>:<locale>"`, `"email:verify:<challengeId>:<code>"`, `"delete:code:<challengeId>:<code>"`.
  - `SignInErrorText.message` (its `when` is exhaustive: `:app` does not compile until it has the five cases): `InvalidEmail` → `signin_error_invalid_email`, `DisposableEmail` → `signin_error_disposable_email`, `InvalidCode` → `signin_error_invalid_code`, `CodeExpired` → `signin_error_code_expired`, `EmailSendFailed` → `signin_error_email_send_failed`.

- [ ] **Step 1: Write the failing tests.**

```kotlin
// SignInExceptionTest.relayAndProviderErrorsMap: add the six `of` rows above.
// SignInExceptionTest.emailCallsReadA404AsNotAvailable: ofEmail(Http(404,"not_found")) and ofEmail(Http(404,"unknown")) → ProviderUnavailable;
//   ofEmail(Http(503,"email_sign_in_disabled")) → ProviderUnavailable; ofEmail(Http(401,"invalid_code")) → InvalidCode;
//   ofEmail(IOException("offline")) → Network; of(Http(404,"not_found")) stays Server("not_found")
// RelayAccountClientTest.everyCallReachesTheRelayApi: the dispatcher also answers "POST /v1/auth/email/code" with 202
//   {"challenge_id":"c1","expires_in":600,"resend_in":60,"email":"a@b.c"} and "POST /v1/auth/email/verify" with the Google reply;
//   after the existing calls: requestEmailCode("a@b.c","en") == EmailChallenge("c1",600,60,"a@b.c"); signInWithEmailCode("c1","123456","Pixel",ByteArray(32));
//   deleteAccountWithEmailCode("c1","123456","t1"); the seen list ends with "POST /v1/auth/email/code", "POST /v1/auth/email/verify", "DELETE /v1/account"
// SignInErrorTextTest.everyFailureHasItsOwnWords: the list gains the five new cases; 14 distinct texts (was 9)
```

- [ ] **Step 2: Run (red).** `ga :core:test --tests 'com.shellx.core.account.SignInExceptionTest'`. Expected: `Unresolved reference: InvalidEmail`.
- [ ] **Step 3: Commit the tests.** `git add shellx-android/core/src/test/kotlin/com/shellx/core/account shellx-android/app/src/test/kotlin/com/shellx/app/ui/signin/SignInErrorTextTest.kt`; `git commit -m "test(shellx-android): email sign-in failures and relay calls"`.
- [ ] **Step 4: Implement** the cases, the mapping, the interface, its implementers, the fakes and the five `SignInErrorText` branches. Update the doc comments of `RelayAccountCalling`, `DemoRelay`, `FakeRelayAccount` and `ScriptedRelay`.
- [ ] **Step 5: Run (green).** `ga :core:test --tests 'com.shellx.core.account.*'` and `ga :app:testDebugUnitTest --tests 'com.shellx.app.ui.signin.SignInErrorTextTest'`: PASS; then `toknix run shellx-android/scripts/dev.sh test core`: passed.
- [ ] **Step 6: Commit.** `git add shellx-android/core/src shellx-android/app/src`; `git commit -m "feat(shellx-android): email sign-in failures in words, and the relay's email calls behind RelayAccountCalling"`.

---

### Task 5: The coordinator signs in and deletes with a code

**Files:**
- Modify: `core/account/AppCoordinator.kt`
- Test: `core-test/account/AppCoordinatorEmailTest.kt` (new)

**Interfaces:**
- Consumes: Tasks 3 and 4.
- Produces (on `AppCoordinator`; each throws `SignInException`):

```kotlin
/** Asks the relay to mail a sign-in code. Refuses with LocalWipePending before any relay call while a wipe is owed. Detached, not joined. */
suspend fun requestEmailCode(email: String, locale: String): EmailChallenge
/** The mailed code: the relay's verify with the phone key, then Google's completion with AccountAuthMethod.EMAIL. Shares Google's
 *  one-at-a-time slot (`signingIn`): a call while a sign-in runs joins it. */
suspend fun signInWithEmailCode(challengeId: String, code: String)
/** Delete Account for an email session, step 1: mails a code to the stored session's address. Server("signed_out") without a session. */
suspend fun requestAccountDeletionCode(locale: String): EmailChallenge
/** Step 2: DELETE /v1/account with the code, then everything deleteAccount() does after its relay call. Shares its slot (`deleting`). */
suspend fun deleteAccountWithEmailCode(challengeId: String, code: String)
```

  Failures of the two code requests and of the verify map through `SignInException.ofEmail`. `deleteAccountWithEmailCode` fails through `endFailedAccountChange` (so a refused stored token signs out as expired, as today). Share `deleteAccount()`'s tail (stop the hub, forget local data, `SignedOut(false)`) in one private function. `deleteAccount()` itself, on a stored session whose `authMethod` is `EMAIL`, throws `SignInException.Server("code_required")` before any call (Ruling 24). Log event names only.

- [ ] **Step 1: Write the failing tests.**

```kotlin
class AppCoordinatorEmailTest {   // coordinatorRig(); FakeRelayAccount.Call / Function; assertSameCase
    // emailSignInVerifiesWithThePhoneKeyAndStoresAnEmailSession: relay.setEmailSignIn(success(AccountSignIn(AccountSession("u1","d1","tok-e"), "e@example.com")));
    //   launch(); requestEmailCode("E@Example.com", "vi") == EmailChallenge("challenge-1", 600, 60, "e@example.com");
    //   signInWithEmailCode("challenge-1", "123456") → calls == [RequestEmailCode("E@Example.com","vi"),
    //   SignInWithEmailCode("challenge-1","123456","Phu's Pixel", vault.phoneKey().publicKey.hex())];
    //   vault.session() == StoredSession("u1","d1","tok-e","e@example.com", EMAIL); phase == SignedIn("e@example.com", EMAIL); hub.value != null
    // codeRequestErrorsMap: with setError on REQUEST_EMAIL_CODE: Http(400,"invalid_email") → InvalidEmail; Http(400,"disposable_email") → DisposableEmail;
    //   Http(429,"rate_limited") → RateLimited; Http(503,"email_sign_in_disabled") → ProviderUnavailable; Http(502,"email_send_failed") → EmailSendFailed;
    //   Http(404,"not_found") → ProviderUnavailable; IOException("offline") → Network
    // verifyErrorsMapAndStoreNothing: on SIGN_IN_WITH_EMAIL_CODE: Http(401,"invalid_code") → InvalidCode; Http(410,"code_expired") → CodeExpired;
    //   Http(409,"switch_from_signed_in_device") → SwitchFromSignedInDevice; Http(400,"invalid_device") → Server("invalid_device"); Http(429,"x") → RateLimited;
    //   each time phase == SignedOut(false) and vault.session() == null
    // aPendingWipeBlocksTheCodeRequestBeforeAnyRelayCall: pendingSettings has PENDING_WIPE_KEY true and a FlakyWiper that fails
    //   → requestEmailCode throws LocalWipePending; relay.calls is empty
    // aSecondVerifyWhileOneRunsJoinsIt (RF3): a Gate hook on SIGN_IN_WITH_EMAIL_CODE; two async signInWithEmailCode("challenge-1","123456"); open
    //   → one SignInWithEmailCode call; both return
    // deletionByCodeMailsTheSessionsAddressThenDeletesAndWipes: stored StoredSession("u1","d1","tok-old","e@example.com", EMAIL); launch();
    //   requestAccountDeletionCode("en") → Call.RequestEmailCode("e@example.com","en"); deleteAccountWithEmailCode("challenge-1","654321")
    //   → Call.DeleteAccountWithEmailCode("challenge-1","654321","tok-old"); no Call.Nonce; identity never asked; phase == SignedOut(false);
    //   every SecretItem is absent; hub.value == null
    // aWrongOrExpiredDeletionCodeKeepsEverything: on DELETE_ACCOUNT_WITH_EMAIL_CODE: Http(401,"invalid_code") → InvalidCode; Http(410,"code_expired") → CodeExpired;
    //   Http(401,"reauth_required") → ReauthRequired; each time the session and the hub stay, phase is still SignedIn
    // deletionByCodeWithARefusedTokenSignsOutAsExpired: Http(401,"unauthorized") → throws Server("unauthorized"); phase == SignedOut(true)
    // deletionByCodeWithoutASessionIsSignedOut: no session → both deletion calls throw Server("signed_out"); relay.calls is empty
    // googlesDeletionRefusesAnEmailSession: the stored EMAIL session; deleteAccount() throws Server("code_required"); relay.calls is empty;
    //   identity never asked; the session and the hub stay
}
```

- [ ] **Step 2: Run (red).** `ga :core:test --tests 'com.shellx.core.account.AppCoordinatorEmailTest'`. Expected: `Unresolved reference: requestEmailCode`.
- [ ] **Step 3: Commit the tests.** `git add shellx-android/core/src/test`; `git commit -m "test(shellx-android): the coordinator signs in and deletes with an email code"`.
- [ ] **Step 4: Implement** the four calls and the guard. Update the class comment ("Google only").
- [ ] **Step 5: Run (green).** The Step 2 command (10 tests), then `toknix run shellx-android/scripts/dev.sh test core`: passed.
- [ ] **Step 6: Commit.** `git add shellx-android/core/src/main`; `git commit -m "feat(shellx-android): AppCoordinator email code sign-in and account deletion by code"`.

---

### Task 6: `EmailSignInModel`, the steps and the countdown

**Files:**
- Create: `core/account/EmailCodeActions.kt`, `core/account/EmailSignInModel.kt` (with `EmailSignInState`)
- Test: `core-test/account/EmailSignInModelTest.kt` (new)

**Interfaces:**
- Consumes: `EmailChallenge`, `SignInException`, `Clock` (`com.shellx.core.platform`).
- Produces (`com.shellx.core.account`):

```kotlin
/** The relay's two email-code calls as a screen uses them; both throw SignInException. */
class EmailCodeActions(
    val requestCode: suspend (email: String, locale: String) -> EmailChallenge,
    val verify: suspend (challengeId: String, code: String) -> Unit,
) { companion object { /** Both throw SignInException.ProviderUnavailable. */ val Unavailable: EmailCodeActions } }

data class EmailSignInState(
    val step: Step = Step.IDLE,
    val email: String = "",          // as typed; from the 202 on, the relay's spelling
    val code: String = "",           // ASCII digits, at most 6
    val resendInSeconds: Int = 0,    // code step: seconds until Resend is allowed; 0: allowed
    val resending: Boolean = false,
    val codeDead: Boolean = false,   // the relay said code_expired: only Resend or another address helps
    val error: SignInException? = null,
) {
    enum class Step { IDLE, EMAIL, SENDING, CODE, VERIFYING, DONE }
    val canSend: Boolean      // EMAIL and looksLikeEmail(email)
    val canVerify: Boolean    // CODE, 6 digits, not codeDead, not resending
    val canResend: Boolean    // CODE, resendInSeconds == 0, not resending
    val busy: Boolean         // SENDING, VERIFYING, DONE, or resending
    // toString(): the step and the flags only, never the email or the code
}

/** Main-confined. Every method returns at once; requests run in [scope]. */
class EmailSignInModel(
    private val actions: EmailCodeActions,
    private val clock: Clock,
    private val scope: CoroutineScope,
    private val autoSubmit: Boolean = true,
    private val sleep: suspend (Duration) -> Unit = { delay(it) },
    restored: Saved? = null,
) {
    val state: StateFlow<EmailSignInState>
    fun start(email: String? = null)   // IDLE → EMAIL; [email], when given, replaces the one kept from before; clears the error
    fun setEmail(text: String)         // EMAIL only: the text cut to MAX_EMAIL_LENGTH; clears the error
    fun send(locale: String)           // EMAIL and canSend → SENDING → CODE, or EMAIL with the failure
    fun setCode(text: String)          // CODE and not codeDead: digits(text); clears the error; with autoSubmit, a change to 6 digits verifies
    fun verify()                       // canVerify → VERIFYING → DONE, or CODE with the failure
    fun resend(locale: String)         // canResend → resending → a new challenge, or the failure
    fun changeEmail()                  // CODE → EMAIL: the address stays, the challenge, the digits and the error go
    fun back(): Boolean                // CODE → changeEmail(); EMAIL → IDLE; SENDING, VERIFYING → true and nothing; IDLE, DONE → false
    fun saved(): Saved?                // what a killed process needs; null in IDLE and DONE
    /** Never the typed code. toString() is redacted. [challengeId] null: the email step. */
    data class Saved(val email: String, val challengeId: String?, val expiresAtMs: Long, val resendAtMs: Long)
    companion object {
        const val CODE_LENGTH = 6
        const val MAX_EMAIL_LENGTH = 254
        /** Trimmed: an '@' that is not first, and after it a '.' that is neither right behind the '@' nor last. */
        fun looksLikeEmail(text: String): Boolean
        /** Every Unicode decimal digit of [text] as its ASCII digit (Character.digit(c, 10)), the first CODE_LENGTH of them. */
        fun digits(text: String): String
    }
}
```

  Rules the signatures do not settle:
  - `send` and `resend` pass `email.trim()`. On a 202: step CODE, `email = challenge.email`, `code = ""`, `codeDead = false`, `error = null`, `resendAtMs = clock.nowMs() + resendIn * 1000`, `expiresAtMs = clock.nowMs() + expiresIn * 1000`.
  - `resendInSeconds` is always computed from the clock: `ceil((resendAtMs − nowMs) / 1000)`, held to 0..600. One ticker coroutine per challenge recomputes it, then `sleep(1.seconds)`, while it is above 0; it never counts ticks.
  - Verify failures: `InvalidCode` → `code = ""`, the challenge stays; `CodeExpired` → `code = ""`, `codeDead = true`, `resendInSeconds = 0`; `SwitchFromSignedInDevice` → back to EMAIL with the address and the failure (Ruling 23); any other `SignInException` → the digits stay. A failure that is not a `SignInException` is `Server("unknown")`; a `CancellationException` is rethrown.
  - A failed `send` returns to EMAIL with the address kept; a failed `resend` keeps the code step as it was, with the failure.
  - `saved()`: EMAIL, SENDING, or a dead code → `Saved(email, null, 0, 0)`; CODE, VERIFYING → the challenge and both deadlines.
  - `restored`: a challenge whose `expiresAtMs` is still ahead → CODE with the countdown from `resendAtMs`; a challenge past it → EMAIL with the address and `CodeExpired`; no challenge → EMAIL with the address.

- [ ] **Step 1: Write the failing tests.**

```kotlin
class EmailSignInModelTest {
    // Rig: ManualClock (t0 = its wallMs); fake actions that record (email, locale) and (challengeId, code) and answer from a queue of
    // Result or wait on a Gate; default answers EmailChallenge("c1", 600, 60, "phu@example.com"), then "c2", …; the model in backgroundScope.
    // tick(n): repeat(n) { clock.advance(1.seconds); advanceTimeBy(1_000); runCurrent() }
    //
    // stepsGoFromIdleToDone: start() → EMAIL; setEmail(" Phu@Example.com ") → canSend; send("vi") with the request held → SENDING,
    //   requested ("Phu@Example.com","vi"); answer → CODE, email "phu@example.com", code "", resendInSeconds 60, error null;
    //   setCode("123456") with verify held → VERIFYING, verified ("c1","123456"); answer → DONE; saved() == null
    // sendIsOffUntilTheTextLooksLikeAnEmail: looksLikeEmail true for "a@b.c", " a@b.c "; false for "", "a@b", "@b.c", "a@.c", "a@b.", "a.b@c";
    //   send("en") with "a@b" requests nothing
    // aLongEmailIsCutAt254 (RF6): setEmail("a".repeat(300)) → state.email.length == 254
    // aPastedCodeKeepsItsDigits (RF1): digits("123 456") == "123456"; digits(" 12-34 56\n") == "123456";
    //   digits("Your ShellX sign-in code is 123456") == "123456"; digits("１２３４５６") == "123456"; digits("1234567") == "123456"; digits("12ab") == "12";
    //   setCode("123 456") verifies ("c1","123456") once
    // sendTappedTwiceSendsOnce: send held; send("en"); send("en") → 1 request
    // verifyTappedTwiceVerifiesOnce (RF3): verify held; setCode("123456"); verify(); verify() → 1 call
    // aWrongCodeClearsTheFieldAndKeepsTheChallenge: verify fails InvalidCode → CODE, code "", error InvalidCode, codeDead false, resendInSeconds 60;
    //   setCode("654321") → verified ("c1","654321")
    // anExpiredCodeOpensResendAtOnce (RF2): tick(10); verify fails CodeExpired → CODE, code "", codeDead, error CodeExpired, resendInSeconds 0,
    //   canResend, !canVerify; setCode("111111") changes nothing and verifies nothing; resend("vi") → requested ("phu@example.com","vi")
    //   → codeDead false, resendInSeconds 60, error null; setCode("222222") → verified ("c2","222222")
    // offlineKeepsTheCodeForAnotherTry (RF7): verify fails Network → CODE, code "123456", error Network, 1 call; verify() → 2 calls;
    //   a send that fails Network → EMAIL, the address kept, error Network
    // aFailedSendSaysWhy: ProviderUnavailable, InvalidEmail, DisposableEmail, EmailSendFailed, RateLimited → EMAIL with the same case;
    //   an IllegalStateException → Server("unknown")
    // theCountdownFollowsTheClock: resend("en") at 60 does nothing; tick(59) → resendInSeconds 1, !canResend; tick(1) → 0, canResend
    // timeAwayCountsEvenWhenNothingTicked (RF4): at 60: clock.advance(45.seconds) alone, then tick(1) → resendInSeconds 14
    // aFailedResendKeepsTheCodeStep: tick(60); resend fails RateLimited → CODE, resending false, error RateLimited, the digits typed before stay
    // anAddressThatMustSwitchGoesBackToTheEmailStep: verify fails SwitchFromSignedInDevice → EMAIL, email "phu@example.com", code "", error SwitchFromSignedInDevice
    // useADifferentEmailKeepsTheAddress: changeEmail() → EMAIL, email "phu@example.com", code "", error null;
    //   back(): CODE → EMAIL (true) → IDLE (true) → false; in SENDING and in VERIFYING back() is true and the step stays
    // withoutAutoSubmitSixDigitsWait (RF8): autoSubmit = false; setCode("123456") → no call, canVerify; verify() → 1 call
    // aKilledAppComesBackToTheCodeStep (RF4): in CODE, saved() == Saved("phu@example.com", "c1", t0 + 600_000, t0 + 60_000) and its toString() has
    //   neither the address nor "c1"; a new model with restored = that at t0 + 20 s → CODE, email kept, code "", resendInSeconds 40, no request;
    //   at t0 + 601 s → EMAIL, email kept, error CodeExpired; restored = Saved("a@b.c", null, 0, 0) → EMAIL, no error
    // theStateNeverPrintsTheEmailOrTheCode: toString() of a CODE state with "phu@example.com" and "123456" contains neither
}
```

- [ ] **Step 2: Run (red).** `ga :core:test --tests 'com.shellx.core.account.EmailSignInModelTest'`. Expected: `Unresolved reference: EmailSignInModel`.
- [ ] **Step 3: Commit the tests.** `git add shellx-android/core/src/test`; `git commit -m "test(shellx-android): the email sign-in steps, their countdown and what survives the process"`.
- [ ] **Step 4: Implement** `EmailCodeActions`, `EmailSignInState`, `EmailSignInModel`.
- [ ] **Step 5: Run (green).** The Step 2 command (18 tests), then `toknix run shellx-android/scripts/dev.sh test core`: passed.
- [ ] **Step 6: Commit.** `git add shellx-android/core/src/main`; `git commit -m "feat(shellx-android): EmailSignInModel, the email and code steps with a clock-read resend countdown"`.

---

### Task 7: The email and code steps as components

**Files:**
- Create: `app/ui/signin/EmailSteps.kt`, `app/ui/signin/EmailSignInButton.kt`, `app/ui/signin/EmailSignInHolder.kt`
- Test: `app-test/ui/signin/{EmailSignInHolderTest,EmailStepFieldsTest}.kt`, `app-ui-test/ui/signin/EmailStepsTest.kt`

**Interfaces:**
- Consumes: Task 6; Task 1's names; `PrimaryButton`, `Spinner`, `SignInErrorText`.
- Produces (`com.shellx.app.ui.signin`):

```kotlin
/** What the steps call; the defaults do nothing (renders). */
class EmailStepCalls(
    val start: () -> Unit = {}, val setEmail: (String) -> Unit = {}, val send: () -> Unit = {}, val setCode: (String) -> Unit = {},
    val verify: () -> Unit = {}, val resend: () -> Unit = {}, val changeEmail: () -> Unit = {},
)
object EmailStepFields {
    val EMAIL_KEYBOARD: KeyboardOptions   // KeyboardType.Email, capitalization None, autoCorrectEnabled false, ImeAction.Send
    val CODE_KEYBOARD: KeyboardOptions    // KeyboardType.Number, autoCorrectEnabled false, ImeAction.Done
    val EMAIL_CONTENT: ContentType        // ContentType.Username + ContentType.EmailAddress
    val CODE_CONTENT: ContentType         // ContentType.SmsOtpCode + ContentType("emailOTPCode")
}
/** The "or" line between two hairlines: tag "signin.or". */
@Composable fun OrDivider(modifier: Modifier = Modifier)
/** "Continue with email": a 48 dp pill like Google's, a soft accent tint (accent at 14 %), Icons.Outlined.Email 20 dp, 10 dp, the words
 *  in accentText; tag "signin.email". */
@Composable fun EmailSignInButton(onClick: () -> Unit, enabled: Boolean, modifier: Modifier = Modifier)
/** The six-digit field (sign-in and Delete Account). Tag from [modifier]. */
@Composable fun EmailCodeField(code: String, onCode: (String) -> Unit, label: String, enabled: Boolean, onDone: () -> Unit,
                               modifier: Modifier = Modifier, autoFocus: Boolean = false)
/** Resend code / Resend code in N s: tag from [modifier]; enabled when state.canResend. */
@Composable fun ResendCodeButton(state: EmailSignInState, onResend: () -> Unit, modifier: Modifier = Modifier)
@Composable internal fun EmailStep(state: EmailSignInState, calls: EmailStepCalls, startDemo: (() -> Unit)?, autoFocus: Boolean, modifier: Modifier = Modifier)
@Composable internal fun CodeStep(state: EmailSignInState, calls: EmailStepCalls, autoFocus: Boolean, modifier: Modifier = Modifier)

/** Keeps the steps across a rotation. [restored]: what a killed process left (Task 8 hands it in). */
internal class EmailSignInHolder(actions: EmailCodeActions, clock: Clock, restored: EmailSignInModel.Saved?) : ViewModel() {
    val model: EmailSignInModel   // EmailSignInModel(actions, clock, viewModelScope, restored = restored)
}
/** [email, challengeId or "", expiresAtMs, resendAtMs]; null stays null. */
val EmailSignInSaver: Saver<EmailSignInModel.Saved?, Any>
```

  What each step shows, top to bottom, 12 dp apart, full width:
  - **`EmailStep`** (EMAIL, SENDING): `OutlinedTextField` tag `signin.email.field`, label `signin_email_field`, one line, `EMAIL_KEYBOARD`, `EMAIL_CONTENT`, the IME's Send runs `calls.send`, enabled in EMAIL; the failure (tag `signin.email.error`, `bodyMedium`, error tone, polite live region) when `SignInErrorText.message(state.error)` has words; `PrimaryButton` tag `signin.email.send`, `signin_email_send`, enabled = `canSend`, in SENDING a 20 dp `Spinner` in place of the words with the words as content description; with `startDemo`, the `signin.demo` text button as on the first step, off while SENDING.
  - **`CodeStep`** (CODE, VERIFYING, DONE): the text `signin_email_sent_to` with `state.email` (tag `signin.email.sentTo`, `bodyMedium`, `onSurfaceVariant`, wraps, polite live region); `EmailCodeField` tag `signin.email.code`, label `signin_email_code`, enabled in CODE unless `codeDead`, Done runs `calls.verify`; the failure as above; `PrimaryButton` tag `signin.email.verify`, `signin_email_verify`, enabled = `canVerify`, the spinner in VERIFYING and DONE; `ResendCodeButton` tag `signin.email.resend`; a text button tag `signin.email.change`, `signin_email_change`, enabled in CODE and not resending.
  - **`EmailCodeField`:** `OutlinedTextField`, one line, `CODE_KEYBOARD`, `CODE_CONTENT`, `headlineSmall` in `FontFamily.Monospace` with 4 sp letter spacing.
  - **Field text (both fields).** The field keeps its own `TextFieldValue` in `remember` (never `rememberSaveable`: the code must not reach the saved state, and the address comes back from the model), sets it synchronously in `onValueChange` (the address cut to `MAX_EMAIL_LENGTH`, the code through `EmailSignInModel.digits`) and then reports it. When the value handed in differs from the field's own text (the model cleared the code, or took the relay's spelling), the field takes the handed value with the cursor at its end. A field fed straight from the StateFlow drops fast keystrokes.
  - **Focus.** With `autoFocus`, the field asks for the focus once when its step appears (`LaunchedEffect(Unit)`), never again: a tap outside must be able to put the keyboard down.

- [ ] **Step 1: Write the failing tests.**

```kotlin
// app-test: EmailSignInHolderTest (@RunWith(AndroidJUnit4::class): the ViewModel's scope is the main thread's; ManualClock;
//   actions that answer EmailChallenge("c1", 600, 60, "phu@example.com") at once)
// theSaverKeepsTheAddressTheChallengeAndTheDeadlines: Saved("phu@example.com","c1",1_700_000_600_000,1_700_000_060_000) saved and restored
//   through EmailSignInSaver is equal; Saved("a@b.c", null, 0, 0) too; null saves as null
// aKilledAppComesBackToTheCodeStepWithTheTimeLeft (RF4): holder A: start, setEmail, send("en") → CODE; saved = A.model.saved(); clock.advance(20.seconds);
//   EmailSignInHolder(actions, clock, saved).model.state.value → step CODE, email "phu@example.com", code "", resendInSeconds 40; 1 request in all
// app-test: EmailStepFieldsTest (plain JUnit)
// theFieldsAskForTheRightKeyboardsAndAutofill: EmailStepFields.EMAIL_KEYBOARD.keyboardType == KeyboardType.Email, imeAction == ImeAction.Send;
//   CODE_KEYBOARD.keyboardType == KeyboardType.Number, imeAction == ImeAction.Done;
//   EMAIL_CONTENT.contentHints.toSet() == setOf("username", "emailAddress"); CODE_CONTENT.contentHints.toSet() == setOf("smsOTPCode", "emailOTPCode")

// app-ui-test: EmailStepsTest (createAndroidComposeRule; ShellXTheme; a recording EmailStepCalls; string(id) = context.getString(id))
// theEmailStepSendsOnlyWhatLooksLikeAnEmail: EmailStep(EmailSignInState(step = EMAIL, email = "phu@")) → "signin.email.send" not enabled;
//   with email "phu@example.com" → enabled; a click → calls.send once; performImeAction on the field → calls.send again
// typingReportsTheAddressCutAt254: performTextInput("a".repeat(300)) on "signin.email.field" → the last setEmail has 254 characters
// theFieldsCarryTheirAutofillTypes: config[SemanticsProperties.ContentType].contentHints.toSet() of "signin.email.field" == setOf("username", "emailAddress");
//   of "signin.email.code" == setOf("smsOTPCode", "emailOTPCode")
// aFailureStandsUnderItsField: EmailStep(state with error InvalidEmail) → "signin.email.error" has string(signin_error_invalid_email), LiveRegion Polite,
//   and its top is at or below the bottom of "signin.email.field"; error ProviderUnavailable → string(signin_error_provider_unavailable)
// sendingShowsASpinnerAndTurnsTheStepOff: step SENDING → the field, "signin.email.send" and "signin.demo" are not enabled; an indeterminate progress node exists
// theCodeFieldShowsOnlySixDigits (RF1): CodeStep(state CODE, email "phu@example.com"); performTextInput("12 34-56 78") on "signin.email.code"
//   → the last setCode == "123456" and the field's EditableText == "123456"
// theCodeStepSaysWhereTheCodeWent: "signin.email.sentTo" text == context.getString(R.string.signin_email_sent_to, "phu@example.com")
// resendCountsDownThenOpens: resendInSeconds 42 → "signin.email.resend" has "Resend code in 42 s", not enabled; 0 → "Resend code", enabled, a click → calls.resend
// aDeadCodeTurnsTheFieldOffAndKeepsResend: codeDead = true, error CodeExpired → "signin.email.code" not enabled, "signin.email.verify" not enabled,
//   "signin.email.resend" enabled, "signin.email.error" has string(signin_error_code_expired)
// theModelsClearedCodeEmptiesTheField: state with code "123456" then recomposed with code "" → the field's EditableText == ""
// verifyingTurnsEverythingOff: step VERIFYING, code "123456" → field, verify, resend and change not enabled
```

- [ ] **Step 2: Run (red).** `ga :app:testDebugUnitTest --tests 'com.shellx.app.ui.signin.EmailSignInHolderTest' --tests 'com.shellx.app.ui.signin.EmailStepFieldsTest' --tests 'com.shellx.app.ui.signin.EmailStepsTest'`. Expected: `Unresolved reference: EmailSignInHolder`.
- [ ] **Step 3: Commit the tests.** `git add shellx-android/app/src/test shellx-android/app/src/testDebug`; `git commit -m "test(shellx-android): the email and code steps as components, and what a killed app keeps"`.
- [ ] **Step 4: Implement** the three files.
- [ ] **Step 5: Run (green).** The Step 2 command: 2, 1 and 11 tests.
- [ ] **Step 6: Commit.** `git add shellx-android/app/src/main`; `git commit -m "feat(shellx-android): email and code step components, the email button and the step holder"`.

---

### Task 8: The sign-in screen with the email button and its two steps

**Files:**
- Modify: `app/ui/signin/SignInView.kt`, `app/ui/nav/ShellXNavHost.kt`
- Create: `app-ui-test/testing/ImeInset.kt`, `app-ui-test/ui/signin/SignInEmailFitTest.kt`
- Test: `app-test/ui/signin/SignInLayoutTest.kt`, `app-ui-test/ui/signin/{SignInViewTest,SignInFitTest}.kt`, `app-ui-test/screenshots/SignInRenderTest.kt`

**Interfaces:**
- Consumes: Tasks 5, 6, 7; `TapOutsideHidesKeyboard`; `AppLanguage`; `AndroidClock`.
- Produces:

```kotlin
data class SignInLayout(val logoDp: Int, val subtitle: Boolean, val guide: Boolean, val sideBySide: Boolean, val tagline: Boolean = true) {
    companion object {
        const val COLUMN_SUBTITLE_MIN_HEIGHT_DP = 800   // one column; two columns keep SUBTITLE_MIN_HEIGHT_DP = 700
        const val COLUMN_GUIDE_MIN_HEIGHT_DP = 660      // one column; two columns keep GUIDE_MIN_HEIGHT_DP = 400
        /** [form]: an email step shows: the small logo, no subtitle, no steps, no taglines; sideBySide as without it. */
        fun of(widthDp: Float, heightDp: Float, form: Boolean = false): SignInLayout
    }
}
@Composable fun SignInView(
    expired: Boolean, signIn: suspend () -> Unit, startDemo: (() -> Unit)?, modifier: Modifier = Modifier,
    initialError: SignInException? = null,
    email: EmailCodeActions = EmailCodeActions.Unavailable,
    clock: Clock = AndroidClock,
    emailRestore: MutableState<EmailSignInModel.Saved?> = remember { mutableStateOf(null) },
)
@Composable internal fun SignInContent(
    expired: Boolean, error: SignInException?, busy: Boolean, continueWithGoogle: () -> Unit, startDemo: (() -> Unit)?,
    introMs: (() -> Long)?, modifier: Modifier = Modifier,
    email: EmailSignInState = EmailSignInState(), emailCalls: EmailStepCalls = EmailStepCalls(), autoFocus: Boolean = false,
)
/** testDebug: the soft keyboard as the system tells the window, [height] of room from the bottom (0.dp: it went down). CompactHeightTest's helper. */
fun AndroidComposeTestRule<*, ComponentActivity>.imeInset(height: Dp)
```

  **`SignInContent`.**
  - Room (Ruling 12): the `BoxWithConstraints` pads `WindowInsets.systemBars.union(WindowInsets.displayCutout)` in place of `safeDrawing`; both scrolling containers get `Modifier.imePadding()` before `verticalScroll`. `layout = SignInLayout.of(maxWidth.value, maxHeight.value, form = email.step != IDLE)`.
  - First step (`email.step == IDLE`): as today; the button column (12 dp apart) is `GoogleSignInButton`, `OrDivider()`, `EmailSignInButton(onClick = emailCalls.start, enabled = !busy)`, then the demo button.
  - An email step (Ruling 11): `Hero` draws the logo at `layout.logoDp` and the title, the taglines only when `layout.tagline`. One column: top-aligned (no `heightIn(min = room)`, no `SpaceBetween`), the hero, 24 dp, the step. Two columns: the `Row` is top-aligned, the hero left, the step right. The step is `EmailStep` in EMAIL and SENDING, `CodeStep` in CODE, VERIFYING and DONE. "Session expired" and the Google failure are not drawn.
  - Expected behaviour to pin, not to build: the scroll container keeps a focused field in view when the keyboard takes room. If `SignInEmailFitTest` shows a focused field under the keyboard, give the fields a `BringIntoViewRequester` and call `bringIntoView()` when `WindowInsets.isImeVisible` turns true.

  **`SignInView`.** `holder = viewModel { EmailSignInHolder(email, clock, emailRestore.value) }`; collects `holder.model.state`; `locale = AppLanguage.current().language`; `emailCalls` are the model's methods (`send = { model.send(locale) }`, `resend = { model.resend(locale) }`); `autoFocus = true`; a `LaunchedEffect(holder)` writes `emailRestore.value = holder.model.saved()` on every state; `BackHandler(enabled = step != IDLE && step != DONE) { holder.model.back() }`. `busy` for the first step is Google's, as today.

  **`ShellXNavHost`.** Above `NavHost`: `val emailRestore = rememberSaveable(stateSaver = EmailSignInSaver) { mutableStateOf<EmailSignInModel.Saved?>(null) }` (Ruling 10). The `sign_in` destination passes `email = remember(composition) { EmailCodeActions({ e, l -> composition.real.coordinator.requestEmailCode(e, l) }, { id, c -> composition.real.coordinator.signInWithEmailCode(id, c) }) }`, `clock = composition.clock`, `emailRestore = emailRestore`.

- [ ] **Step 1: Write the failing tests.**

```kotlin
// SignInLayoutTest: change three tests, add one.
// aPhoneInPortraitHasTheBigLogoAndTheSteps (was …TheSubtitleAndTheSteps): 393 × 713, 737, 785 → SignInLayout(96, subtitle = false, guide = true, sideBySide = false);
//   393 × 800, 852 → subtitle = true; of(393f, 799.5f).subtitle false; of(393f, 660f).guide true; of(393f, 659.5f).guide false
// aShorterPhoneLeavesTheSubtitleToTheTaglines: of(360f, 640f) == SignInLayout(96, false, guide = false, false)
// aWindowUnder600DpTallHasTheSmallLogo: of(360f, 592f) == SignInLayout(72, false, guide = false, false); the two logo boundaries stay
// (unchanged and still passing: the landscape, tablet and split-screen tests: two columns keep 700 and 400)
// whileAnEmailStepShowsOnlyTheSmallLogoAndTheTitleStay: for (w, h) in (393, 713), (393, 852), (737, 369), (1280, 752):
//   of(w, h, form = true) == SignInLayout(72, subtitle = false, guide = false, sideBySide = of(w, h).sideBySide, tagline = false); of(393f, 713f).tagline

// SignInFitTest: PORTRAIT becomes logo, title, tagline, guide.1–3, google, "signin.or", "signin.email", demo (no subtitle).
// The four Pixel 3 portrait tests and nothingMovesWhile… use it unchanged otherwise (whole on screen, in order, no scroll, 24 dp under the demo button).
// aTallPhoneKeepsTheSubtitle (new; "w393dp-h852dp-440dpi", and again with fontScale 1.3): PORTRAIT plus "signin.subtitle" after the tagline, whole on screen, stacked
// assertTheLandscapeScreenFits: also "signin.or" and "signin.email" whole on screen, stacked google, or, email, demo
// aShortPhoneHasTheSmallLogoAndNeitherSubtitleNorSteps (renamed): logo, title, tagline, google, or, email, demo whole on screen and stacked; no "signin.guide.1"
// aTabletInLandscapeKeepsTheStepsBesideTheLogo: PORTRAIT plus "signin.subtitle" whole on screen; stacked guide.1–3, google, or, email, demo

// SignInEmailFitTest (new; NATIVE graphics; SignInView with actions that answer EmailChallenge("c1", 600, 60, <the address>); steps reached by taps and typing)
//   PIXEL_3 = "w393dp-h713dp-440dpi", PIXEL_3_TURNED = "w737dp-h369dp-land-440dpi"; KEYBOARD = 300.dp (portrait Gboard: an estimate, Task 10 Step 4 measures it);
//   LANDSCAPE_KEYBOARD = 251.dp (measured, ledger A-36). "above the keyboard": whole inside the window with bottom <= window.bottom − the inset.
// onThePixel3TheEmailStepStandsAboveTheKeyboard (PIXEL_3; again with "vi-" and with fontScale 1.3): imeInset(KEYBOARD) → the logo is 72 dp;
//   "signin.email.field" and "signin.email.send" are above the keyboard; no "signin.tagline", "signin.subtitle", "signin.guide.1", "signin.google"
// theKeyboardMovesNothing (PIXEL_3): the bounds of logo, title, "signin.email.field", "signin.email.send" are equal before imeInset(KEYBOARD), with it, and after imeInset(0.dp)
// onThePixel3TheCodeStepStandsAboveTheKeyboard (PIXEL_3; again with "vi-"): imeInset(KEYBOARD) → "signin.email.sentTo", "signin.email.code", "signin.email.verify" above the keyboard
// largeTextInTheCodeStepKeepsTheFieldAboveTheKeyboard (PIXEL_3, fontScale 1.3): "signin.email.code" above the keyboard;
//   "signin.email.verify", "signin.email.resend", "signin.email.change" each performScrollTo().assertIsDisplayed()
// inLandscapeTheFocusedFieldComesAboveTheKeyboard (PIXEL_3_TURNED): email step, then code step, each with imeInset(LANDSCAPE_KEYBOARD):
//   the focused field is above the keyboard; the logo's right <= the field's left
// aVeryLongEmailWrapsInsideTheWindow (RF6; PIXEL_3): the address "a".repeat(60) + "@example-company-mail.com" → in the code step "signin.email.sentTo"
//   has right <= window.right; "signin.email.code" and "signin.email.verify" each performScrollTo().assertIsDisplayed()

// SignInViewTest: show() gains email: EmailCodeActions and clock; new tests (requests, verifies: recorded argument lists; `held`: a CompletableDeferred)
// continueWithEmailOpensTheEmailStepAndBackLeavesIt: click "signin.email" → "signin.email.field" exists and is focused; no "signin.google", "signin.tagline", "signin.guide.1";
//   rule.activity.onBackPressedDispatcher.onBackPressed() → "signin.google" is back; hasEnabledCallbacks() is false on the first step
// whileGoogleRunsTheEmailButtonIsOff: Google held → "signin.email" not enabled
// aCodeSignsInOnceAndAutoSubmits (RF3): verify held; type "Phu@Example.com", click "signin.email.send" → requests == [("Phu@Example.com", "en")];
//   "signin.email.code" is focused; type "123 456" → verifies == [("c1", "123456")] with no tap; the verify button is not enabled; release → still 1 verify
// aWrongCodeShowsItsWordsAndTakesANewOne: verify throws InvalidCode once → "signin.email.error" has string(signin_error_invalid_code); the code field is empty and enabled;
//   type "654321" → verifies.size == 2
// anExpiredCodeOffersResendAtOnce (RF2): verify throws CodeExpired → the code field is not enabled; "signin.email.resend" is enabled and reads "Resend code";
//   a click → requests.size == 2; the code field is enabled; "signin.email.resend" reads "Resend code in 60 s"
// anOldRelaySaysNotAvailableInThisBuild: requestCode throws ProviderUnavailable → still the email step with the address; "signin.email.error" has string(signin_error_provider_unavailable)
// offlineKeepsWhatWasTyped (RF7): requestCode throws Network → "signin.email.error" has string(signin_error_network); the field still has the address; send is enabled
// useADifferentEmailGoesBackWithTheAddress: click "signin.email.change" → "signin.email.field" has "phu@example.com"
// theCodeStepSurvivesARotation (RF5): in the code step type "123"; scenario.recreate() and set the same content → "signin.email.sentTo" exists,
//   "signin.email.code" has "123", requests.size == 1; with a verify held across a recreate → verifies.size == 1
// aSavedCodeStepIsShownAtOnce (RF4): emailRestore = mutableStateOf(Saved("phu@example.com", "c1", clock.nowMs() + 600_000, clock.nowMs() + 40_000))
//   → "signin.email.code" exists with no tap; "signin.email.resend" reads "Resend code in 40 s"; requests is empty
// theScreenWritesWhatAKilledAppNeeds: after the 202 → emailRestore.value?.challengeId == "c1"; after a verify that succeeds → emailRestore.value == null
// aTapOutsideTheFieldPutsTheKeyboardDownAndKeepsTheStep: the content inside TapOutsideHidesKeyboard with a counting LocalSoftwareKeyboardController;
//   in the email step with "phu@example.com" typed: a click on "signin.logo" → hides == 1, the field is not focused, it still has the address;
//   a click in the field → focused; a click on "signin.email.send" → hides is still 1 and requests.size == 1

// SignInRenderTest: new renders through SignInContent (introMs = null); the existing ones redraw with the new button.
// "signin-email" (EMAIL, empty), "signin-email-sending" (SENDING, "phu@example.com"), "signin-email-error" (EMAIL, error InvalidEmail),
// "signin-code" (CODE, "phu@example.com", code "123", resendInSeconds 42), "signin-code-error" (error InvalidCode),
// "signin-code-expired" (codeDead, error CodeExpired), "signin-code-verifying" (VERIFYING, code "123456"),
// "signin-code-pixel3-large-font" (qualifiers "w393dp-h713dp-xxhdpi", fontScale 1.3), "signin-code-landscape" ("w785dp-h393dp-land-xxhdpi", width 2355)
```

- [ ] **Step 2: Run (red).** `ga :app:testDebugUnitTest --tests 'com.shellx.app.ui.signin.*' --tests 'com.shellx.app.screenshots.SignInRenderTest'`. Expected: `BUILD FAILED` with `No value passed for parameter` or `Unresolved reference: imeInset` (compile).
- [ ] **Step 3: Commit the tests.** `git add shellx-android/app/src/test shellx-android/app/src/testDebug`; `git commit -m "test(shellx-android): the sign-in screen with the email button, its two steps and the keyboard up"`.
- [ ] **Step 4: Implement** `imeInset`, the layout rule, `SignInContent`, `SignInView` and the NavHost wiring. Update the comments of `SignInView.kt` that say "Google only" or name `safeDrawing`.
- [ ] **Step 5: Run (green).** The Step 2 command: PASS. If a Pixel 3 fit test misses by a few dp, lower the 24 dp gap between the hero and the steps to 16 dp in one column; never shrink a button, drop the "or" line or hide the steps on the Pixel 3; report it. Then `toknix run shellx-android/scripts/dev.sh test app`: `==> test app: passed`.
- [ ] **Step 6: Look at the renders.** `toknix run shellx-android/scripts/dev.sh screenshots record /Users/richard/Documents/helper/shellx/.superpowers/sdd/2026-11-11-shellx-email-code-signin-android/shots`. Open `signin-pixel3-large-font-light-vi`, `signin-light-en`, `signin-email-dark-vi`, `signin-code-light-en`, `signin-code-expired-light-vi`, `signin-code-landscape-dark-en`: nothing clipped or overlapping; the email button is a pill under the "or" line; the failure stands under its field.
- [ ] **Step 7: Commit.** `git add shellx-android/app/src`; `git commit -m "feat(shellx-android): Continue with email on the sign-in screen, with its email and code steps"`.

---

### Task 9: Settings: the account's label and deletion by code

**Files:**
- Modify: `app/ui/settings/{AccountSection,DeleteAccountDialog,SettingsScreen}.kt`, `app/ui/nav/ShellXNavHost.kt`
- Test: `app-ui-test/ui/settings/SettingsScreenTest.kt`, `app-ui-test/screenshots/SettingsRenderTest.kt`

**Interfaces:**
- Consumes: Tasks 3, 5, 6, 7 (`EmailCodeField`, `ResendCodeButton`).
- Produces (`com.shellx.app.ui.settings`):

```kotlin
class AccountActions(val signOut: suspend () -> Unit, val deleteAccount: suspend () -> Unit, val emailDeletion: EmailCodeActions? = null)
@Composable fun AccountSection(email: String, account: AccountActions?, authMethod: AccountAuthMethod = AccountAuthMethod.GOOGLE, clock: Clock = AndroidClock)
// SettingsScreen gains, after `settings`: authMethod: AccountAuthMethod = AccountAuthMethod.GOOGLE, clock: Clock = AndroidClock (passed to AccountSection)
/** The deletion's card for an email session, drawn from the model's state. */
@Composable fun DeleteAccountCodeCard(state: EmailSignInState, onDelete: () -> Unit, onCode: (String) -> Unit, onResend: () -> Unit,
                                      onCancel: () -> Unit, modifier: Modifier = Modifier, autoFocus: Boolean = false)
@Composable fun DeleteAccountCodeDialog(model: EmailSignInModel, onDismiss: () -> Unit)
// AccountProgress (internal) gains:
val codeDeletion: StateFlow<EmailSignInModel?>
fun openCodeDeletion(actions: EmailCodeActions, email: String, clock: Clock)   // EmailSignInModel(actions, clock, viewModelScope, autoSubmit = false).start(email); one already open stays
// closeDeletion() also closes the code card, unless its state is busy
```

  - **Label (Ruling 3).** The e-mail row's headline is `settings_account_method_email` when `authMethod == EMAIL`, else `signin_email`.
  - **Which deletion.** "Delete Account…" opens the code card when `authMethod == EMAIL && account.emailDeletion != null`, else today's card (the app always passes `emailDeletion` for the real account).
  - **`DeleteAccountCodeCard`** (the look of `DeleteAccountCard`: the warning, the title, Cancel and Delete Account; tags `delete.cancel`, `delete.confirm`, `delete.error`, `delete.working` as there):
    - EMAIL: `settings_account_delete_message`; the failure when there is one; Delete Account runs `onDelete`.
    - SENDING: the same, both buttons off, a 20 dp `Spinner` in place of the Delete Account words.
    - CODE: `settings_account_delete_code_intro` (tag `delete.code.intro`) and under it `state.email`; `EmailCodeField` (tag `delete.code.field`, label `settings_account_delete_code_field`, off when `codeDead`); the failure; `ResendCodeButton` (tag `delete.code.resend`); Delete Account enabled = `state.canVerify`, runs `onDelete`.
    - VERIFYING, DONE: the `delete.working` row (`Spinner`, `settings_account_delete_deleting`), both buttons off.
  - **`DeleteAccountCodeDialog`:** `BasicAlertDialog` around `TapOutsideHidesKeyboard { DeleteAccountCodeCard(…, autoFocus = true) }` (a dialog is its own window); with `locale = AppLanguage.current().language`, `onDelete` is `model.send(locale)` in EMAIL and `model.verify()` in CODE, and `onResend` is `model.resend(locale)`; a dismiss does nothing while `state.busy`.
  - **`ShellXNavHost`:** `AccountActions(…, emailDeletion = EmailCodeActions({ _, l -> active.coordinator.requestAccountDeletionCode(l) }, { id, c -> active.coordinator.deleteAccountWithEmailCode(id, c) }))`; `SettingsScreen(…, authMethod = (phase as? AppPhase.SignedIn)?.authMethod ?: AccountAuthMethod.GOOGLE, clock = composition.clock)`.

- [ ] **Step 1: Write the failing tests.**

```kotlin
// SettingsScreenTest: Screen() gains authMethod; account() gains emailDeletion built from recorded requests / verifies (answer EmailChallenge("c1", 600, 60, "phu@example.com"))
// anEmailSessionsRowIsLabelledEmailCode: authMethod EMAIL → a node with "Email code" and "phu@example.com"; GOOGLE → "Email"; the demo (account null) → "Email"
// deletingAnEmailAccountAsksForACodeAndNeedsATap (RF8): EMAIL; click "settings.delete", then "delete.confirm" → requests == [("phu@example.com", "en")];
//   "delete.code.intro" has string(settings_account_delete_code_intro); type "654 321" in "delete.code.field" → verifies is empty;
//   click "delete.confirm" → verifies == [("c1", "654321")]; "delete.working" is shown; deletes (the Google path) == 0
// aWrongDeletionCodeSaysSoAndKeepsTheCard: verify throws InvalidCode → "delete.error" has string(signin_error_invalid_code); "delete.code.field" is empty; "delete.confirm" not enabled
// aCodeThatCannotBeSentSaysSoOnTheQuestion: requestCode throws EmailSendFailed → "delete.error" has string(signin_error_email_send_failed); no "delete.code.field"
// theCodeCardStaysWhileItDeletes: verify held → a click on "delete.cancel" changes nothing ("delete.working" still shown)
// aGoogleSessionStillConfirmsWithGoogle: GOOGLE with emailDeletion set → "delete.confirm" → deletes == 1; requests is empty; no "delete.code.field"

// SettingsRenderTest: "settings-email" (Settings("phu@example.com", AccountActions({}, {}), authMethod EMAIL));
// "delete-account-code" (DeleteAccountCodeCard, CODE, "phu@example.com", code "123", resendInSeconds 42), "delete-account-code-error" (error InvalidCode),
// "delete-account-code-working" (VERIFYING)
```

- [ ] **Step 2: Run (red).** `ga :app:testDebugUnitTest --tests 'com.shellx.app.ui.settings.SettingsScreenTest' --tests 'com.shellx.app.screenshots.SettingsRenderTest'`. Expected: `Unresolved reference: DeleteAccountCodeCard`.
- [ ] **Step 3: Commit the tests.** `git add shellx-android/app/src/testDebug`; `git commit -m "test(shellx-android): the account's email label and deletion by code"`.
- [ ] **Step 4: Implement.** Update the comments that say an Android session is always Google.
- [ ] **Step 5: Run (green).** The Step 2 command: PASS (6 new tests, 4 new renders). Open `delete-account-code-light-vi` and `settings-email-dark-en` from a fresh `screenshots record` into the Task 8 folder: the address is readable, the field and Resend fit in the card.
- [ ] **Step 6: Commit.** `git add shellx-android/app/src/main`; `git commit -m "feat(shellx-android): Settings shows Email code, and an email account is deleted with a mailed code"`.

---

### Task 10: The whole app, and verification

**Files:**
- Test: `app-ui-test/ShellXAppSmokeTest.kt`, `app-ui-test/ShellXAppHostTest.kt`

**Interfaces:**
- Consumes: everything above; `mainComposition`, `ScriptedRelay`, `testEnvironment`.

- [ ] **Step 1: Write the tests** (they pass at once if Tasks 8 and 9 wired the NavHost; a failure here is a wiring bug to fix in this task).

```kotlin
// ShellXAppSmokeTest.signInWithAnEmailCodeAndSeeTheFirstMacScreen: start(mac) signed out; tap "Continue with email"; type "Phu@Example.com" in "signin.email.field";
//   tap "Send code"; wait for "signin.email.code"; type "123 456" (RF1) → wait for "Pair a Mac";
//   t.relay.calls contains "email:code:Phu@Example.com:en" and "email:verify:challenge-1:123456", and no "google:…";
//   AccountVault(t.secrets, Dispatchers.IO).session()?.authMethod == AccountAuthMethod.EMAIL
// ShellXAppHostTest.anEmailSessionDeletesItsAccountWithACode: as aDeletionSurvivesARecreatedWindow… builds its composition, with
//   StoredSession("u1", "d1", "tok-1", "phu@example.com", AccountAuthMethod.EMAIL) and a TestIdentity; open Settings → the row reads "Email code";
//   "settings.delete" → "delete.confirm" → wait for "delete.code.field"; relay.calls contains "email:code:phu@example.com:en";
//   type "654321"; recreate the window and set the same content → "delete.code.field" still shows "654321" and no second "email:code:" call;
//   click "delete.confirm" → wait for "Continue with Google"; relay.calls.count { it == "delete:code:challenge-1:654321" } == 1;
//   no "nonce" call and no other call that starts with "delete:"; the sign-in screen does not say signin_expired
```

- [ ] **Step 2: Run.** `ga :app:testDebugUnitTest --tests 'com.shellx.app.ShellXAppSmokeTest' --tests 'com.shellx.app.ShellXAppHostTest'`: PASS. Commit: `git add shellx-android/app/src/testDebug`; `git commit -m "test(shellx-android): email code sign-in and deletion through the whole app"` (with any wiring fix in a `fix(shellx-android): …` commit after it).
- [ ] **Step 3: Full verification.** `toknix run shellx-android/scripts/dev.sh test all` → `==> test all: passed` (link, `:core`, `:app` debug and release, scripts, the R8 release build with its checks). Then `python3 shellx-android/scripts/import-strings.py --check` and `python3 shellx-ios/scripts/check-strings.py`: both `ok`. Record the test counts.
- [ ] **Step 4: The real keyboard (API 36 emulator; the one thing Robolectric cannot show).** `shellx-android/scripts/dev.sh emulator --api 36 --headless` prints the emulator's serial; every adb call below is `"$ANDROID_HOME/platform-tools/adb" -s <that serial> …`, never without `-s`, never the phone's serial. Take screenshots with `exec-out screencap -p`.
  1. Continue with email: the email keyboard is up; the field and Send code are above it, in portrait and after a rotation to landscape (`shell settings put system user_rotation 1`, with `accelerometer_rotation 0`).
  2. Measure the portrait keyboard from the screenshot. If it takes less than 280 dp or more than 320 dp above the navigation bar, set `KEYBOARD` in `SignInEmailFitTest` to the measured value, rerun that class, and commit `test(shellx-android): the measured portrait keyboard height`.
  3. Do **not** tap Send code on the emulator: the debug build talks to the production relay and no test traffic goes there (orchestrator's ruling, 2026-11-11). The "not available in this build" path (404 / 503) is covered by the scripted-relay tests only; the live path is the USER's phone check.
  4. `shell settings put global always_finish_activities 1`; type an address, go Home (`shell input keyevent HOME`), open the app again: the email step is back with the address. Set it back to 0.
  5. Stop the emulator: `emu kill`. The code step with a real number pad is not reachable without a relay that has the feature: it is the USER's phone check after the relay part is deployed.
- [ ] **Step 5: Report** (to the orchestrator, not a file in the repo): commits, test counts, what Step 4 showed, every name that differed from this plan, and what stays unverified on a device: the number pad and paste in the code field, the keyboard after coming back from the mail app, the keyboard over the deletion dialog, TalkBack on the two steps, the Pixel 3 without the subtitle.

---

### Task 11: Contracts

**Files:**
- Modify: `docs/superpowers/plans/2026-11-07-shellx-mobile-contracts.md`

- [ ] **Step 1: Find the last numbered section.** The relay part appends "§29. Additions from the email-code sign-in plan, relay part" (the API, the codes). This part's section is the next free number; if another part took that number meanwhile, say so in the report and let the orchestrator renumber at the merge.
- [ ] **Step 2: Append `## <number>. Additions from the email-code sign-in plan, Android part`** with these lines, names checked against the branch tip (the API itself is the relay section's, or spec §4 while that has not landed):
  - `com.shellx.link.account`: `EmailChallenge(challengeId, expiresIn, resendIn, email)`; `RelayApi.requestEmailCode(email, locale)`, `signInWithEmailCode(challengeId, code, deviceName, clientKey)`, `deleteAccountWithEmailCode(challengeId, code, token)` (Kotlin cannot overload `deleteAccount` on names).
  - `com.shellx.core.account`: `AccountAuthMethod { GOOGLE, EMAIL }` (`wire`); `StoredSession.authMethod`, stored as `auth_method` (absent: google; unknown: unreadable); `AppPhase.SignedIn.authMethod`; `SignInException.{InvalidEmail, DisposableEmail, InvalidCode, CodeExpired, EmailSendFailed}` and `ofEmail` (any 404 and `503 email_sign_in_disabled` → `ProviderUnavailable`); the three `RelayAccountCalling` members; `AppCoordinator.requestEmailCode`, `signInWithEmailCode`, `requestAccountDeletionCode`, `deleteAccountWithEmailCode`; `EmailCodeActions`, `EmailSignInModel`, `EmailSignInState` (steps IDLE, EMAIL, SENDING, CODE, VERIFYING, DONE; the countdown reads `Clock.nowMs()`; `Saved` never holds the code).
  - App: `SignInView(…, email, clock, emailRestore)`; `SignInLayout.of(width, height, form)` with one-column thresholds 800 (subtitle) and 660 (steps); the room is measured without the keyboard; tags `signin.or`, `signin.email`, `signin.email.{field,send,error,sentTo,code,verify,resend,change}`, `delete.code.{intro,field,resend}`; `AccountActions.emailDeletion`; deletion by code never auto-submits; the code step is restored from saved state held above the NavHost.
  - Strings: the 18 catalog keys of Task 1 (spam hint inside `signin.email.sentTo %@`); Android's `signin_subtitle` names Google and email.
  - Behaviour the iPhone part shares: a 409 on verify goes back to the email step; `deleteAccount()` on an email session is `Server("code_required")`; a 410 opens Resend at once. Android-only: system Back instead of a Cancel button; the field stops at 254 characters.
  - Test support: `ScriptedRelay.emailCode`, `emailSignIn`, `deleteByCode` and its three call records; `imeInset`.
  - Not verified on a device: the list of Task 10 Step 5.
  - No parity-ledger row: the iPhone's email sign-in does not exist yet to differ from; the iPhone part compares at its landing.
- [ ] **Step 3: Commit.** `git add docs/superpowers/plans/2026-11-07-shellx-mobile-contracts.md`; `git commit -m "docs(shellx): contracts: Android email code sign-in"`. Stop here: no merge, no push, no install on the phone.
