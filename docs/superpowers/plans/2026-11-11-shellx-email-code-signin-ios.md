# ShellX iPhone: sign-in with an emailed code Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task: one implementer runs every task in order on one branch, and the branch is reviewed once as a whole at the end. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The iPhone app signs in with an email address and a 6-digit code the relay mails, next to Google and Apple, and an account signed in that way can be deleted in the app with a code.

**Architecture:** shellx-link's `RelayAPI` gains the three relay calls of spec §4. `ShellXAppCore` gains `AccountAuthMethod.email`, five `SignInError` cases, the coordinator's email calls (they finish through the existing `completeSignIn`) and `EmailSignInModel`, an `@Observable` state machine (idle → email → sending → code → verifying → done) whose Resend lock runs on an injected clock; the same model, made with other closures, runs the code step of Delete Account. The app target adds an "or" row and "Continue with email" to the sign-in screen of the animated intro, swaps the buttons for an email step and a code step in place, and gives `DeleteAccountSheet` a code branch.

**Tech Stack:** Swift 6.0 (strict concurrency), SwiftUI and Observation, iOS 17, XCTest, `swift test`, `shellx-ios/scripts/dev.sh`, Python 3 (catalog round trip, `check-strings.py`, Android's `import-strings.py`).

**Spec:** `docs/superpowers/specs/2026-11-10-shellx-email-code-sign-in-design.md` (Vietnamese): §3, §4, §7 "Chung", the strings paragraph and the **iPhone** bullet, and the iPhone lines of §8–§10. §11 is answered: all four apps; link by verified email (relay side); default sender; every small default stands. Shared names: `docs/superpowers/plans/2026-11-07-shellx-mobile-contracts.md`. Read `shellx-ios/README.md` before Task 1 (`ios/AGENTS.md` does not cover `shellx-ios/`).

## Global Constraints

- The relay contract is spec §4, nothing else:
  - `POST /v1/auth/email/code` `{email, locale}` (no bearer) → 202 `{challenge_id, expires_in: 600, resend_in: 60, email}`; 400 `invalid_email`, 400 `disposable_email`, 429 `rate_limited`, 503 `email_sign_in_disabled`, 502 `email_send_failed`; a relay from before this feature: 404 `not_found`.
  - `POST /v1/auth/email/verify` `{challenge_id, code, device}` (no bearer) → 200 `{user_id, device_id, token, email}`; 401 `invalid_code`, 410 `code_expired`, 409 `switch_from_signed_in_device`, 400 `invalid_device`, 429 `rate_limited`.
  - `DELETE /v1/account` bearer + `{challenge_id, code}` → 204; 401 `invalid_code`, 410 `code_expired`, 401 `reauth_required` (and the route's existing 429 `rate_limited`).
  - `device` is `{kind: "mobile", platform: "ios", name, public_key}` (base64url, no padding), as `signInWithGoogle` sends it.
- Values: 6 digits; the Resend lock is the reply's `resend_in` (60 s); `locale` is `vi` when the app shows Vietnamese, else `en`; the session is stored with `auth_method` `"email"`.
- Never log, print or put in a description an email address, a code or a challenge id (spec §2). Log lines carry event names and error types only.
- Simulator only, and only through `shellx-ios/scripts/dev.sh` (never bare `xcodebuild`, only the "ShellX Dev" simulator). No signing, provisioning or Apple developer account action of any kind: never `dev.sh device`, never `-allowProvisioningUpdates`, never `release/mobile/*.sh` by hand. The bundle id stays `com.shellx.prod`; this plan changes no xcconfig, `Info.plist`, entitlement or `project.pbxproj` (`ShellX/` and `ShellXTests/` are synchronized folders: a new Swift file needs no project edit).
- One `dev.sh test app|all|screenshots` on this Mac at a time: before starting one, `pgrep -fl xcodebuild` must show no ShellX run from another worktree (wait until it ends).
- Every test, build and check command runs through `toknix run <command>` (when its output ends with `[toknix: … toknix recall <id> …]` and the cut part is needed, `toknix recall <id>`).
- Never quit, launch or replace `/Applications/ShellX.app` or any cmux app.
- Swift 6 language mode, strict concurrency, Swift 6.0 syntax only, in the style the packages use: `@MainActor @Observable` models, `async throws` relay calls, `throws(SignInError)` on coordinator calls, `@ObservationIgnored` on what is not shown. New tests are XCTest, like their neighbours.
- Licence boundary (`shellx-ios/README.md`): Apple frameworks, the app's own code and shellx-link only; no new module import.
- Strings: every visible string is a key of `shellx-ios/ShellX/Localizable.xcstrings` with `en` and `vi` (`"state": "translated"`), `"extractionState": "manual"` and a `comment`, used through `String(localized:)` or `LocalizedStringResource` with a plain literal key. The key names of spec §7 are used verbatim. The catalog is shared with Android (`shellx-android/scripts/import-strings.py`): no new value may contain iPhone wording (iPhone, Apple, App Store, VoiceOver…), only `%@` and `%lld` formats, no leading, trailing or double space. Edit the catalog with a JSON round trip (load, change `catalog["strings"]`, write `json.dumps(catalog, ensure_ascii=False, indent=2) + "\n"`: this reproduces the file byte for byte), appending new keys.
- Nothing here needs a running relay, a real email or a key: link tests use `StubURLProtocol`, everything else `FakeRelayAccount`.
- Commits: two per task, the failing test first (`test(shellx-ios): …`), then the code that turns it green (`feat(shellx-ios): …`; `shellx-link` for Task 2). The executor stops before landing: no merge, no push.
- Tests are given as a name with its assertions (code in the tables); write them in the style of the neighbouring test file, one XCTest method per row.

## Rulings (where the spec and the code disagree, or the spec is silent)

1. `RelayAccountCalling` is in `shellx-ios/Packages/ShellXAppCore/Sources/ShellXAppCore/Account/`, not in shellx-link (spec §7 names it with the link package). The link package gets the `RelayAPI` methods; the protocol, its fake and the demo relay change in `ShellXAppCore`.
2. The link signatures carry what the wire needs: `signInWithEmailCode(challengeID:code:deviceName:clientKey:)` and `deleteAccount(challengeID:code:token:)`. The spec's shorter names are the coordinator's.
3. Format keys hold their argument in the key, as this catalog does everywhere: `signin.email.sentTo %@`, `signin.email.resendIn %lld` (Android's importer strips the signature: `signin_email_sent_to`, `signin_email_resend_in`).
4. Settings › Account on the iPhone has no "sign-in method" row (spec §3 describes the Mac's). The one email row gets the label `settings.account.method.email` ("Email code") instead of `signin.email` for an `email` session.
5. 404 `not_found` reads as `providerUnavailable` only in the email calls. `SignInError.init` keeps answering `.server(code: "not_found")`, so Google and Apple show today's words against an old relay. 503 `email_sign_in_disabled` is unambiguous and maps in `SignInError.init`.
6. One text field for the six digits (spec §10 leaves it open): autofill, paste, backspace and VoiceOver work as the system makes them.
7. The spec gives the email step no way back to Google and Apple. A text button `common.cancel` (existing key) returns to the buttons. "Try without an account" shows with the buttons and in the email step, not in the code step.
8. A 409 `switch_from_signed_in_device` on verify returns to the email step with its message: this address cannot go on.
9. A 410 `code_expired` ends the Resend lock at once and turns the code field off until a new code is sent: the code is dead (expired, used, or the fifth wrong try), and waiting or typing helps nobody.
10. Delete Account by code: the email is sent when the user presses "Delete Account", never when the sheet opens, and the sixth digit never deletes by itself (sign-in does submit on the sixth digit, spec §3).
11. Spec §9 promises a "check your spam folder" message but §7 lists no key for it: the sentence is part of `signin.email.sentTo %@`.
12. `EmailSignInModel` also runs the code step of Delete Account (same lock, same field rules), made by the coordinator with other closures.
13. An address over 254 bytes is refused on the phone as `invalidEmail` without a request.
14. `deleteAccount()` (no arguments) on an `email` session throws `.server(code: "code_required")` and calls nothing; the 401 `reauth_required` of the code path keeps `SignInError.reauthRequired` and its text.
15. Sign-in screen (the intro's `SignInLayout` changes): the button column is 86 points taller, so the logo is 72 under 688 points of height (was 600) and the subtitle shows from 788 (was 700); two columns are chosen from the width alone (500 points or more), because a keyboard changes only the height; while the email or the code step shows, the intro folds (Task 7).
16. `dev.sh` has `screenshots <dir>` (no `record` word) and no word for the link package: its tests are `swift test --package-path shellx-link`.
17. The "session expired" line, the Apple-link notice and a Google or Apple failure show with the buttons only; a step shows only its own failure, under its field (spec §3; the Android part rules the same).
18. A build from before this plan that reads a stored `"auth_method": "email"` treats the session as unreadable and shows sign-in (`testUnknownAuthMethodIsAnUnreadableSession`). Accepted: it needs a downgrade.

## Review Focus

Each line is pinned by the test named, in the task that owns the code.

1. A code pasted or autofilled with spaces, a dash or the mail's words around it ("123 456", "Your ShellX sign-in code is 123456") is verified once as `123456`, and the field shows six digits: Task 5 `testAPastedCodeIsCutToItsSixDigits`, Task 7 `testTheCodeFieldShowsOnlyDigitsAndAWrongCodeEmptiesIt`.
2. A code typed after it expired (or after five wrong tries) says so, empties the field and turns it and Verify off, and unlocks Resend at once: Task 5 `testAnExpiredCodeUnlocksResendAtOnce`.
3. A double tap on Verify, or the sixth digit and a tap together, send one request: Task 5 `testVerifyTwiceSendsOneRequest`.
4. Leaving the app to read the mail and coming back keeps the step, the digits typed and the challenge, and the countdown shows the time really left: Task 5 `testTheCountdownFollowsTheClockAlsoAfterTimeAway`. (After iOS ended the process the screen starts over: nothing is persisted, see Spec notes.)
5. Turning the phone in the code step keeps the digits and the keyboard: Task 7 `testTurningThePhoneInTheCodeStepKeepsTheDigitsAndTheKeyboard`.
6. A very long email: over 254 bytes it is refused without a request, and a long valid one wraps in the sentence above the code field without pushing the field off the screen: Task 5 `testTheEmailIsTrimmedAndOver254BytesIsRefusedWithoutARequest`, Task 7 `testALongEmailWrapsAndKeepsTheFieldOnTheScreen`.
7. Offline: the failure reads `signin.error.network`, what was typed stays, and the same button tries again: Task 5 `testOfflineKeepsWhatWasTypedAndTheSameTapRetries`.
8. A tall keyboard on a small phone (a third-party Vietnamese keyboard on an iPhone SE leaves less height than width) must not flip the screen to two columns: Task 6 `testTheKeyboardNeverTurnsTheScreenOnItsSide`, Task 7 `testAKeyboardOnASmallPhoneKeepsOneColumnAndTheFieldAboveIt`.

## File Structure

`…/` is `shellx-ios/Packages/ShellXAppCore/Sources/`; `…T/` is `shellx-ios/Packages/ShellXAppCore/Tests/ShellXAppCoreTests/`.

| File | Change | Responsibility |
| --- | --- | --- |
| `shellx-link/Sources/ShellXLinkAccount/RelayAPI+SignIn.swift` | modify | `EmailChallenge`, the three relay calls |
| `shellx-link/Tests/ShellXLinkAccountTests/RelayAPIEmailCodeTests.swift` | create | their wire tests |
| `…/ShellXAppCore/Account/StoredSession.swift`, `SignInError.swift`, `RelayAccountCalling.swift` | modify | `.email`; five error cases and their mapping; three protocol requirements |
| `…/ShellXAppCore/Account/AppCoordinator.swift` | modify | the email calls, deletion by code, `emailSignIn`, `makeDeleteAccountCode()` |
| `…/ShellXAppCore/Account/EmailSignInModel.swift` | create | the steps, the Resend lock, the failure to show; `EmailCodeLocale` |
| `…/ShellXAppTestSupport/FakeRelayAccount.swift`, `…/ShellXDemo/DemoRelay.swift` | modify | the three calls (recorded and preset; refused) |
| `…T/EmailSignInStringsTests.swift`, `AppCoordinatorEmailTests.swift`, `EmailSignInModelTests.swift` | create | catalog keys; coordinator; model |
| `…T/SignInErrorTests.swift`, `AccountVaultTests.swift`, `DemoRelayTests.swift`, `PairingModelTests.swift`, `MachineHubTests.swift`, `Support/CoordinatorRig.swift` | modify | new cases; the two private relay wrappers forward the new calls; the rig gets a `ManualClock` and locale `vi` |
| `shellx-ios/ShellX/Localizable.xcstrings`, `shellx-android/app/src/main/res/values{,-vi}/strings.xml` | modify | 18 keys; the regenerated Android strings |
| `shellx-ios/ShellX/UI/SignIn/SignInIntro.swift`, `SignInView.swift`, `SignInErrorText.swift` | modify | `SignInLayout`; the button column and the two steps; five messages |
| `shellx-ios/ShellX/UI/SignIn/EmailSignInButton.swift`, `EmailSignInPanel.swift`, `EmailCodeField.swift` | create | the pill and the "or" row; the email and code steps; the code field and the Resend row (shared with the delete sheet) |
| `shellx-ios/ShellX/UI/Settings/AccountSection.swift`, `AccountActions.swift`, `DeleteAccountSheet.swift`; `shellx-ios/ShellX/AppGraph.swift` | modify | the label and the code branch; `preview(relay:)` |
| `shellx-ios/ShellXTests/EmailSignInRenderTests.swift`, `EmailSignInViewTests.swift`, `Support/Bitmap.swift` | create | screenshots and geometry; fields, focus, rotation; the intro's `Bitmap`, moved |
| `shellx-ios/ShellXTests/SignInIntroTests.swift`, `SignInRenderTests.swift`, `AccountRenderTests.swift`, `DeleteAccountRenderTests.swift` | modify | the moved thresholds; the new messages, label and sheet steps |
| `docs/superpowers/plans/2026-11-07-shellx-mobile-contracts.md` | modify | the lines of this part (Task 9) |

---

### Task 0: Worktree, preconditions, baseline

- [ ] **Step 1: Worktree.** From the main checkout create branch `feat/shellx-email-code-signin-ios` from `develop` in `.worktrees/email-code-signin-ios` (`superpowers:using-git-worktrees`). Every later path is relative to that worktree. If this plan is missing there (it may be untracked in the main checkout), read it from `/Users/richard/Documents/helper/shellx/docs/superpowers/plans/`; never add it on this branch.
- [ ] **Step 2: The sign-in intro is on `develop`.** `grep -n "struct SignInLayout" shellx-ios/ShellX/UI/SignIn/SignInIntro.swift` must print a line. If it does not, stop and report: this plan builds on that screen. Then check the names this plan uses against the landed files: `SignInLayout(size:)` with `logoSize`, `showsSubtitle`, `showsGuide`, `sideBySide`; `SignInView.init(coordinator:expired:notice:startDemo:initialError:motion:introStart:)` with its `actions` column (12-point spacing); `SnapshotWriter.write(_:name:size:safeArea:settle:)`; the private `Bitmap` at the end of `ShellXTests/SignInRenderTests.swift` (`Colour`, `firstRowWithAWhiteRun()`, `isPlain(fromRow:)`, `darkSquareSide()`). Where a name landed differently, follow the landed code and note it in the report.
- [ ] **Step 3: Which strings are already there.** The Android part lands before this one and may have added the 18 keys of Task 1. Run `python3 -c 'import json; s=json.load(open("shellx-ios/ShellX/Localizable.xcstrings"))["strings"]; print(sorted(k for k in s if k.startswith(("signin.email.", "settings.account.method", "settings.account.delete.code")) or k in ("signin.error.invalidEmail", "signin.error.disposableEmail", "signin.error.invalidCode", "signin.error.codeExpired", "signin.error.emailSendFailed")))'` and keep the output for Task 1. If the relay part has landed, compare `relay/src/routes/email-sign-in.ts` with Global Constraints; a different route, field or code: stop and report.
- [ ] **Step 4: Baseline.** Run `toknix run swift test --package-path shellx-link` (`with 0 failures`), `bash scripts/shellx/check-link-license.sh` (exit 0), `toknix run shellx-ios/scripts/dev.sh test core` (`==> test core: passed`), `toknix run shellx-ios/scripts/dev.sh test app` (note the `Executed N tests` line and any failure; the hand-off's "Known noise" lists the tests that are red or flaky on `develop`). From here on, "green" means no failure beyond this baseline.

---

### Task 1: The 18 strings (shared with Android)

**Files:**
- Modify: `shellx-ios/ShellX/Localizable.xcstrings`, `shellx-android/app/src/main/res/values/strings.xml`, `shellx-android/app/src/main/res/values-vi/strings.xml` (generated)
- Test: Create `…T/EmailSignInStringsTests.swift`

**Interfaces:**
- Produces: the catalog keys below, used by Tasks 3, 6, 7 and 8 exactly as written (two of them carry their argument in the key).

| Key | en | vi | comment |
| --- | --- | --- | --- |
| `signin.email.continue` | Continue with email | Tiếp tục với email | Button under "or" on the sign-in screen: opens the email step. |
| `signin.email.or` | or | hoặc | Between the Google and Apple buttons and "Continue with email". |
| `signin.email.field` | Email address | Địa chỉ email | Placeholder and accessibility label of the email field. |
| `signin.email.send` | Send code | Gửi mã | Primary button of the email step. |
| `signin.email.sentTo %@` | We sent a 6-digit code to %@. If it isn't there in a minute, check your spam folder. | Đã gửi mã 6 chữ số tới %@. Nếu sau một phút chưa thấy, hãy xem cả thư rác. | Above the code field; the argument is the address as the relay normalized it. |
| `signin.email.code` | 6-digit code | Mã 6 chữ số | Placeholder and accessibility label of the code field. |
| `signin.email.verify` | Verify | Xác nhận | Primary button of the code step. |
| `signin.email.resend` | Resend code | Gửi lại mã | Text button of the code step once the 60-second lock is over. |
| `signin.email.resendIn %lld` | Resend code in %lld s | Gửi lại mã sau %lld giây | The same row while locked; the argument is the seconds left. |
| `signin.email.change` | Use a different email | Dùng email khác | Text button of the code step: back to the email step. |
| `signin.error.invalidEmail` | That doesn't look like an email address. | Địa chỉ email này chưa đúng. | Relay 400 invalid_email, or an address over 254 bytes. |
| `signin.error.disposableEmail` | Temporary email addresses can't be used. Try another address. | Không dùng được địa chỉ email tạm thời. Hãy dùng địa chỉ khác. | Relay 400 disposable_email. |
| `signin.error.invalidCode` | That code isn't right. Check the email and try again. | Mã chưa đúng. Xem lại email rồi thử lại. | Relay 401 invalid_code. |
| `signin.error.codeExpired` | That code no longer works. Send a new one. | Mã này không còn dùng được. Hãy gửi mã mới. | Relay 410 code_expired: expired, already used, or the fifth wrong try. |
| `signin.error.emailSendFailed` | Couldn't send the email. Try again in a moment. | Chưa gửi được email. Thử lại sau giây lát. | Relay 502 email_send_failed. |
| `settings.account.method.email` | Email code | Mã qua email | Settings › Account: label of the email row of a session that signed in with an emailed code. |
| `settings.account.delete.codeIntro` | We sent a 6-digit code to this account's email address. Enter it to delete the account. | Đã gửi mã 6 chữ số tới địa chỉ email của tài khoản này. Nhập mã để xoá tài khoản. | Delete Account for an email session, above the code field. |
| `settings.account.delete.codeField` | Code from the email | Mã trong email | Placeholder and accessibility label of the code field in the deletion sheet. |

- [ ] **Step 1: Write the failing test** (`#if os(macOS)`, like `StringsCatalogCheckTests`; `keys` is the first column of the table, in order):

```swift
final class EmailSignInStringsTests: XCTestCase {
    func testEveryKeyIsTranslatedAndKeepsItsArgument() throws {
        let url = ScriptRunner.repositoryRoot.appendingPathComponent("shellx-ios/ShellX/Localizable.xcstrings")
        let catalog = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let strings = try XCTUnwrap(catalog["strings"] as? [String: [String: Any]])
        XCTAssertEqual(Self.keys.count, 18)
        for key in Self.keys {
            let entry = try XCTUnwrap(strings[key], "missing \(key)")
            XCTAssertEqual(entry["extractionState"] as? String, "manual", key)
            XCTAssertFalse((entry["comment"] as? String ?? "").isEmpty, key)
            for language in ["en", "vi"] {
                let unit = ((entry["localizations"] as? [String: Any])?[language] as? [String: Any])?["stringUnit"] as? [String: Any]
                XCTAssertEqual(unit?["state"] as? String, "translated", "\(key) \(language)")
                let value = unit?["value"] as? String ?? ""
                XCTAssertFalse(value.isEmpty, "\(key) \(language)")
                for format in ["%@", "%lld"] {   // exactly the argument the key names, and no other
                    XCTAssertEqual(value.components(separatedBy: format).count - 1, key.hasSuffix(" " + format) ? 1 : 0, "\(key) \(language)")
                }
                XCTAssertNil(value.range(of: "iPhone|Apple|App Store|VoiceOver", options: .regularExpression), "\(key): Android imports this text")
            }
        }
    }
}
```

- [ ] **Step 2: Run it.** `toknix run swift test --package-path shellx-ios/Packages/ShellXAppCore --filter EmailSignInStringsTests`. Expected: FAIL with `missing signin.email.continue` (or the first key Task 0 Step 3 did not list). If Task 0 found all 18 keys under these exact names, the test passes at once: commit it alone, skip Steps 4–5 and say so in the report. A key that exists under another signature (for example `settings.account.delete.codeIntro %@`): stop and report, the two plans disagree.
- [ ] **Step 3: Commit the test.** `git add shellx-ios/Packages/ShellXAppCore/Tests/ShellXAppCoreTests/EmailSignInStringsTests.swift && git commit -m "test(shellx-ios): the email sign-in strings are in the catalog in English and Vietnamese"`
- [ ] **Step 4: Add the missing keys** from the table with the JSON round trip of Global Constraints. A key the catalog already has keeps the catalog's text (Android shows it already). Extend the `comment` of `signin.error.providerUnavailable` with "Also: the relay has no email sign-in (404 not_found, 503 email_sign_in_disabled)."; its text stays. Then regenerate Android's strings: `python3 shellx-android/scripts/import-strings.py`.
- [ ] **Step 5: Verify and commit.** The Step 2 command (PASS), `python3 shellx-ios/scripts/check-strings.py` (`check-strings: ok (N keys)`), `python3 shellx-android/scripts/import-strings.py --check` (`import-strings: ok (…)`). `git add shellx-ios/ShellX/Localizable.xcstrings shellx-android/app/src/main/res/values/strings.xml shellx-android/app/src/main/res/values-vi/strings.xml && git commit -m "feat(shellx-mobile): email sign-in strings (steps, errors, account label, deletion by code)"`

---

### Task 2: The relay calls in ShellXLinkAccount

**Files:**
- Modify: `shellx-link/Sources/ShellXLinkAccount/RelayAPI+SignIn.swift`
- Test: Create `shellx-link/Tests/ShellXLinkAccountTests/RelayAPIEmailCodeTests.swift`

**Interfaces:**
- Consumes: `RelayAPI.send(_:_:token:body:)`, `Empty`, the file's private `SignInReply` and `device(_:_:)`.
- Produces (public, module `ShellXLinkAccount`):

```swift
/// What the relay answers when it mails a code. `challengeID` signs in together with the mailed code, so descriptions
/// and the mirror leave it and the email out: "EmailChallenge(expiresIn: 600, resendIn: 60, <redacted>)".
public struct EmailChallenge: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var challengeID: String
    public var expiresIn: Int   // seconds
    public var resendIn: Int    // seconds
    public var email: String    // as the relay normalized it
    public init(challengeID: String, expiresIn: Int, resendIn: Int, email: String)
}
extension RelayAPI {
    public func requestEmailCode(email: String, locale: String) async throws -> EmailChallenge
    public func signInWithEmailCode(challengeID: String, code: String, deviceName: String, clientKey: Data) async throws -> AccountSignIn
    public func deleteAccount(challengeID: String, code: String, token: String) async throws
}
```

Rules: `requestEmailCode` sends `email` as given (the relay normalizes) and accepts a reply only with a `challenge_id` of 1–128 base64url characters (the check `nonce()` makes; share it), `expires_in` > 0, `resend_in` ≥ 0 and a non-empty `email`, else `RelayAPIError.badResponse`. `signInWithEmailCode` reads the reply with `SignInReply.signIn()`. Every non-2xx keeps the relay's code as `RelayAPIError.http(status:code:)`.

- [ ] **Step 1: Write the failing tests** with the stubs of `RelayAPISignInTests` (`api()`, `clientKey` = bytes `0x20…0x3f`, `StubURLProtocol.install`). `id` is `String(repeating: "aB3_-", count: 8) + "xyz"` (43 base64url characters); an error stub is `StubResponse(status, ["error": ["code": code, "message": "x"]])`.

| Test | Stub and call | Assertions |
| --- | --- | --- |
| `testRequestEmailCodePostsTheEmailAndTheLocaleWithoutToken` | 202 `["challenge_id": id, "expires_in": 600, "resend_in": 60, "email": "phu@example.com"]`; `requestEmailCode(email: " Phu@Example.com ", locale: "vi")` | result `== EmailChallenge(challengeID: id, expiresIn: 600, resendIn: 60, email: "phu@example.com")`; `"\(got)"` does not contain `id`; `String(reflecting: got)` does not contain `"phu@example.com"`; request `method == "POST"`, `path == "/v1/auth/email/code"`, `headers["Authorization"] == nil`, `json as? [String: String] == ["email": " Phu@Example.com ", "locale": "vi"]` (sent as given) |
| `testAChallengeTheApiDoesNotDocumentIsRefused` | 202 with each of: no `challenge_id`; `"has space"`; 129 × `"a"`; `expires_in: 0`; `resend_in: -1`; `email: ""` (the other fields valid) | each throws `RelayAPIError.badResponse` |
| `testTheCodeRequestKeepsEveryRelayErrorCode` | (400, `invalid_email`), (400, `disposable_email`), (429, `rate_limited`), (503, `email_sign_in_disabled`), (502, `email_send_failed`), (404, `not_found`) | each throws `.http(status: status, code: code)` |
| `testSignInWithEmailCodeSendsTheChallengeTheCodeAndTheMobileDevice` | 200 `["user_id": "u1", "device_id": "d1", "token": "tok-secret", "email": "phu@example.com"]`; `signInWithEmailCode(challengeID: id, code: "012345", deviceName: "Phu's iPhone", clientKey: clientKey)`; then (401, `invalid_code`), (410, `code_expired`), (409, `switch_from_signed_in_device`), (400, `invalid_device`), (429, `rate_limited`); then 200 without `email` | result `== AccountSignIn(session: AccountSession(userID: "u1", deviceID: "d1", token: "tok-secret"), email: "phu@example.com")`; `POST /v1/auth/email/verify`, no `Authorization`; `Set(json.keys) == ["challenge_id", "code", "device"]`; `json["challenge_id"] == id`; `json["code"] as? String == "012345"` (a string: the leading zero stays); `json["device"] as? [String: String] == ["kind": "mobile", "platform": "ios", "name": "Phu's iPhone", "public_key": "ICEiIyQlJicoKSorLC0uLzAxMjM0NTY3ODk6Ozw9Pj8"]`; each error throws `.http(status:code:)`; the reply without `email` throws `.badResponse` |
| `testDeleteAccountByCodeSendsTheBearerTheChallengeAndTheCode` | 204; `deleteAccount(challengeID: id, code: "123456", token: "tok")`; then (401, `invalid_code`), (410, `code_expired`), (401, `reauth_required`) | `method == "DELETE"`, `path == "/v1/account"`, `headers["Authorization"] == "Bearer tok"`, `json as? [String: String] == ["challenge_id": id, "code": "123456"]`; each error throws `.http(status:code:)` |

- [ ] **Step 2: Run them.** `toknix run swift test --package-path shellx-link --filter RelayAPIEmailCodeTests`. Expected: build error `cannot find 'EmailChallenge' in scope`.
- [ ] **Step 3: Commit the tests.** `git add shellx-link/Tests/ShellXLinkAccountTests/RelayAPIEmailCodeTests.swift && git commit -m "test(shellx-link): relay calls for the emailed sign-in code and for deleting the account with one"`
- [ ] **Step 4: Implement** `EmailChallenge` and the three methods in `RelayAPI+SignIn.swift` with the rules above; the wire type is a private `Decodable` struct like `NonceReply`.
- [ ] **Step 5: Run and commit.** The Step 2 command, then `toknix run swift test --package-path shellx-link` and `bash scripts/shellx/check-link-license.sh`: `with 0 failures` twice, exit 0. `git add shellx-link/Sources/ShellXLinkAccount/RelayAPI+SignIn.swift && git commit -m "feat(shellx-link): relay calls for the emailed sign-in code and for deleting the account with one"`

---

### Task 3: `AccountAuthMethod.email`, the new failures, the protocol and its fakes

**Files:**
- Modify (core): `…/ShellXAppCore/Account/StoredSession.swift`, `SignInError.swift`, `RelayAccountCalling.swift`; `…/ShellXAppTestSupport/FakeRelayAccount.swift`; `…/ShellXDemo/DemoRelay.swift`
- Modify (app, so the tree keeps building): `shellx-ios/ShellX/UI/SignIn/SignInErrorText.swift`
- Test: Modify `…T/SignInErrorTests.swift`, `AccountVaultTests.swift`, `DemoRelayTests.swift`, `PairingModelTests.swift` (`HeldPairRelay`), `MachineHubTests.swift` (`GatedGrantsRelay`); `shellx-ios/ShellXTests/AccountRenderTests.swift`

**Interfaces:**
- Consumes: Task 1 (the five `signin.error.*` keys), Task 2 (`EmailChallenge`; the three `RelayAPI` methods make `RelayAPI` conform by itself).
- Produces:

```swift
public enum AccountAuthMethod: String, Codable, Sendable { case password, google, apple, email }

// SignInError, five more cases and their mapping in init(_:):
case invalidEmail       // (400, "invalid_email"); also an address over 254 bytes (Task 5)
case disposableEmail    // (400, "disposable_email")
case invalidCode        // (401, "invalid_code")
case codeExpired        // (410, "code_expired")
case emailSendFailed    // (502, "email_send_failed")
                        // (503, "email_sign_in_disabled") → .providerUnavailable

// RelayAccountCalling, three more requirements:
func requestEmailCode(email: String, locale: String) async throws -> EmailChallenge
func signInWithEmailCode(challengeID: String, code: String, deviceName: String, clientKey: Data) async throws -> AccountSignIn
func deleteAccount(challengeID: String, code: String, token: String) async throws

// FakeRelayAccount:
//   Call:     .requestEmailCode(email:locale:), .signInWithEmailCode(challengeID:code:deviceName:clientKey:),
//             .deleteAccountWithCode(challengeID:code:token:)
//   Function: .requestEmailCode, .signInWithEmailCode, .deleteAccountWithCode
/// nil (the default): the nth request answers `EmailChallenge(challengeID: "challenge-<n>", expiresIn: 600, resendIn: 60,
/// email: <the email asked for, trimmed and lowercased>)`, as the relay normalizes.
public func setEmailChallenge(_ result: Result<EmailChallenge, Error>?)
/// Default: user "user", device "device", token "email-token", email "user@example.com".
public func setEmailSignIn(_ result: Result<AccountSignIn, Error>)
```

The three fake methods go through `enter(_:_:)` (recorded, hook, preset error) like `signInWithGoogle`. `DemoRelay` refuses all three with `DemoRelay.refusal`. `HeldPairRelay` and `GatedGrantsRelay` forward them to `base`. `SignInErrorText.message(for:)` maps the five cases to `signin.error.invalidEmail`, `.disposableEmail`, `.invalidCode`, `.codeExpired`, `.emailSendFailed`.

- [ ] **Step 1: Write the failing tests.**

| Test | What it adds | Assertions |
| --- | --- | --- |
| `SignInErrorTests.testRelayAndProviderErrorsMap` | rows in `cases` | `(400, "invalid_email") → .invalidEmail`; `(400, "disposable_email") → .disposableEmail`; `(401, "invalid_code") → .invalidCode`; `(410, "code_expired") → .codeExpired`; `(502, "email_send_failed") → .emailSendFailed`; `(503, "email_sign_in_disabled") → .providerUnavailable`; `(400, "invalid_device") → .server(code: "invalid_device")`; `(404, "not_found") → .server(code: "not_found")` (ruling 5) |
| `AccountVaultTests.testAnEmailSessionIsStoredAsEmailAndOlderSessionsStillRead` (new) | `setSession(StoredSession(userID: "u1", deviceID: "d1", token: "t", email: "a@b.c", authMethod: .email))` | the stored JSON has `"auth_method": "email"`; `vault.session()?.authMethod == .email`; a stored `{"userID":"u1","deviceID":"d1","token":"t","email":"a@b.c","auth_method":"<m>"}` reads as `.google`, `.apple`, `.password` for `<m>` = `google`, `apple`, `password` (the tests for a missing and an unknown method stay as they are) |
| `DemoRelayTests.testEveryAccountCallIsRefused` | three entries | `requestEmailCode(email: "a@b.c", locale: "en")`, `signInWithEmailCode(challengeID: "c", code: "1", deviceName: "p", clientKey: key)`, `deleteAccount(challengeID: "c", code: "1", token: "t")` each throw `DemoRelay.refusal` |
| `AccountRenderTests.testEveryFailureHasItsOwnWords` | `.invalidEmail, .disposableEmail, .invalidCode, .codeExpired, .emailSendFailed` in `errors` | unchanged: as many different messages as failures |
| `AccountRenderTests.testSwitchBannerShowsOnlyForPasswordSessionsUntilDismissed` | one line | `XCTAssertFalse(SwitchToGoogleBanner.isShown(authMethod: .email, dismissed: false))` |

- [ ] **Step 2: Run them.** `toknix run swift test --package-path shellx-ios/Packages/ShellXAppCore --filter "SignInErrorTests|AccountVaultTests|DemoRelayTests"`. Expected: build error `type 'SignInError' has no member 'invalidEmail'`.
- [ ] **Step 3: Commit the tests.** `git add shellx-ios/Packages/ShellXAppCore/Tests shellx-ios/ShellXTests/AccountRenderTests.swift && git commit -m "test(shellx-ios): an email session is stored as email; the relay's email errors have their own failures"`
- [ ] **Step 4: Implement** the Produces block.
- [ ] **Step 5: Run and commit.** `toknix run shellx-ios/scripts/dev.sh test core` (`==> test core: passed`), then `toknix run shellx-ios/scripts/dev.sh test app` (green: the app builds with the longer `switch`, and each failure has its own words). `git add shellx-ios/Packages/ShellXAppCore shellx-ios/ShellX/UI/SignIn/SignInErrorText.swift && git commit -m "feat(shellx-ios): email auth method, the email failures and the relay protocol for them"`

---

### Task 4: The coordinator signs in, and deletes, with a code

**Files:**
- Modify: `…/ShellXAppCore/Account/AppCoordinator.swift`; Create: `…/ShellXAppCore/Account/EmailSignInModel.swift` (this task puts only `EmailCodeLocale` in it)
- Test: Create `…T/AppCoordinatorEmailTests.swift`; Modify `…T/Support/CoordinatorRig.swift`

**Interfaces:**
- Consumes: Task 3 (protocol, fakes, `.email`, the failures); the existing private `completeSignIn(_:method:)`, `retryPendingWipe()`, `phoneKey()`, `beginAccountChange()`, `endFailedAccountChange(_:)`, `forgetLocalData()`.
- Produces:

```swift
public enum EmailCodeLocale {
    /// "vi" for Vietnamese ("vi", "vi-VN", "VI"), "en" for anything else (spec §3).
    public static func relayValue(appLanguage: String) -> String
    /// For the language the app shows: `Bundle.main.preferredLocalizations.first`.
    public static var current: String { get }
}

// AppCoordinator.init gains, before `makeHub`:  emailLocale: String = EmailCodeLocale.current, clock: any Clock<Duration> = ContinuousClock()
/// Asks the relay to mail a code to `email`. Stores nothing; the phase stays.
public func requestEmailCode(email: String) async throws(SignInError) -> EmailChallenge
/// The mailed code for `challengeID`: a right one signs in like Google, with `auth_method` email.
public func signInWithEmailCode(challengeID: String, code: String) async throws(SignInError)
/// Delete Account for an email session, first half: mails a code to the account's address.
public func requestDeleteAccountCode() async throws(SignInError) -> EmailChallenge
/// Second half: deletes on the relay, then forgets everything local exactly as `deleteAccount()` does.
public func deleteAccount(challengeID: String, code: String) async throws(SignInError)
```

Rules:
- Both sign-in calls clear `signInNotice` and run the pending-wipe guard first (`.localWipePending` before any relay call), as `signInWithGoogle` does. `signInWithEmailCode` takes the phone key, calls the relay with `deviceName` and the key, then `completeSignIn(signIn, method: .email)`.
- Errors of the relay's email calls: `RelayAPIError.http(404, "not_found")` → `.providerUnavailable`; anything else `SignInError(error)`.
- `requestDeleteAccountCode`: no session → `.server(code: "signed_out")`; a session that is not `.email` → `.server(code: "not_email_session")`; else `relay.requestEmailCode(email: stored.email, locale: emailLocale)`.
- `deleteAccount(challengeID:code:)`: `beginAccountChange()`, `relay.deleteAccount(challengeID:code:token: stored.token)`; a failure goes through `endFailedAccountChange` (session and hub stay; a 401 `unauthorized` signs out as expired); success ends as `deleteAccount()` ends (the two share that ending in one private function). `deleteAccount()` on an `.email` session throws `.server(code: "code_required")` before any call.
- `CoordinatorRig.make` creates `let clock = ManualClock()`, passes `emailLocale: "vi", clock: clock` and keeps `let clock: ManualClock`.

- [ ] **Step 1: Write the failing tests** (`@MainActor final class AppCoordinatorEmailTests`, with `CoordinatorRig.make(self)` and `signInError { }` as `AppCoordinatorSignInTests` uses them). `emailSession()` is a rig whose vault holds `StoredSession(userID: "u1", deviceID: "d1", token: "tok-old", email: "phu@example.com", authMethod: .email)` and machines owned by `"u1"`, launched. `http(s, c)` is `RelayAPIError.http(status: s, code: c)`.

| Test | Arrange and act | Assertions |
| --- | --- | --- |
| `testTheLocaleIsVietnameseOnlyForVietnamese` | — | `["vi", "vi-VN", "VI", "en", "fr", ""].map(EmailCodeLocale.relayValue(appLanguage:)) == ["vi", "vi", "vi", "en", "en", "en"]` |
| `testRequestingACodeSendsTheEmailInTheAppsLanguageAndStoresNothing` | launched rig; `requestEmailCode(email: "Phu@Example.com")` | returns `EmailChallenge(challengeID: "challenge-1", expiresIn: 600, resendIn: 60, email: "phu@example.com")`; `relay.calls == [.requestEmailCode(email: "Phu@Example.com", locale: "vi")]`; `vault.session() == nil`; `phase == .signedOut(expired: false)` |
| `testTheRightCodeSignsInLikeGoogleWithAnEmailSession` | `setEmailSignIn(.success(AccountSignIn(session: AccountSession(userID: "u1", deviceID: "d1", token: "tok-e"), email: "phu@example.com")))`; the vault holds a machine owned by `"someone-else"`; `signInWithEmailCode(challengeID: "challenge-1", code: "012345")` | `relay.calls == [.signInWithEmailCode(challengeID: "challenge-1", code: "012345", deviceName: "Phu's iPhone", clientKey: key)]`; `vault.session() == StoredSession(userID: "u1", deviceID: "d1", token: "tok-e", email: "phu@example.com", authMethod: .email)`; `phase == .signedIn(email: "phu@example.com")`; `authMethod == .email`; `hub != nil`; `wiper.wipes == 1` and `vault.machinesOwner() == "u1"` (another account's history goes, as for Google) |
| `testEveryRelayAnswerOfTheTwoCallsHasItsFailure` | one rig; `setError(_:for: .requestEmailCode)` then `requestEmailCode`; `setError(_:for: .signInWithEmailCode)` then `signInWithEmailCode` | request: `http(400, "invalid_email") → .invalidEmail`, `http(400, "disposable_email") → .disposableEmail`, `http(429, "rate_limited") → .rateLimited`, `http(503, "email_sign_in_disabled") → .providerUnavailable`, `http(404, "not_found") → .providerUnavailable`, `http(502, "email_send_failed") → .emailSendFailed`, `URLError(.notConnectedToInternet) → .network`; verify: `http(401, "invalid_code") → .invalidCode`, `http(410, "code_expired") → .codeExpired`, `http(409, "switch_from_signed_in_device") → .switchFromSignedInDevice`, `http(400, "invalid_device") → .server(code: "invalid_device")`, `http(429, "rate_limited") → .rateLimited`, `http(404, "not_found") → .providerUnavailable`, `URLError(.timedOut) → .network`; at the end `vault.session() == nil`, `phase == .signedOut(expired: false)`, `hub == nil` |
| `testAPendingWipeBlocksBothCallsBeforeAnyRelayCall` | rig with `extraWipers: [FlakyWiper()]`, `pendingDefaults.set(true, forKey: "shellx.localWipePending")` | both calls throw `.localWipePending`; `relay.calls == []` |
| `testDeleteByCodeMailsTheAccountsAddressThenDeletesAndWipesLikeSignOut` | `emailSession()`; `requestDeleteAccountCode()`; `deleteAccount(challengeID: challenge.challengeID, code: "123456")` | after the request `phase == .signedIn(email: "phu@example.com")`; `relay.calls == [.requestEmailCode(email: "phu@example.com", locale: "vi"), .deleteAccountWithCode(challengeID: "challenge-1", code: "123456", token: "tok-old")]` (no nonce, no unpair, no logout); `identity.googleNonces == []`; every `SecretItem` reads nil; `wiper.wipes == 1`; `phase == .signedOut(expired: false)`; `authMethod == nil`; `hub == nil` |
| `testAWrongExpiredOrForeignDeleteCodeKeepsEverything` | `emailSession()` per case; `setError(_:for: .deleteAccountWithCode)`; `deleteAccount(challengeID: "challenge-1", code: "000000")` | `http(401, "invalid_code") → .invalidCode`, `http(410, "code_expired") → .codeExpired`, `http(401, "reauth_required") → .reauthRequired`; `vault.session()?.token == "tok-old"`; the hub is the same object |
| `testDeletionAsksForTheRightKindOfProof` | `emailSession()`: `deleteAccount()`; a launched Google session: `requestDeleteAccountCode()` | `.server(code: "code_required")`; `.server(code: "not_email_session")`; both relays' `calls == []`; both `identity.googleNonces == []` |
| `testUnauthorizedDuringDeleteByCodeEndsSignedOutNotExpired` | `emailSession()`; hook on `.deleteAccountWithCode` calls `coordinator.handleUnauthorized()`; `deleteAccount(challengeID: "challenge-1", code: "123456")` | `phase == .signedOut(expired: false)` |

- [ ] **Step 2: Run them.** `toknix run swift test --package-path shellx-ios/Packages/ShellXAppCore --filter AppCoordinatorEmailTests`. Expected: build error `cannot find 'EmailCodeLocale' in scope`.
- [ ] **Step 3: Commit the tests.** `git add shellx-ios/Packages/ShellXAppCore/Tests && git commit -m "test(shellx-ios): the coordinator signs in and deletes the account with an emailed code"`
- [ ] **Step 4: Implement** the Produces block and the rules.
- [ ] **Step 5: Run and commit.** The Step 2 command, then `toknix run shellx-ios/scripts/dev.sh test core` (`==> test core: passed`). `git add shellx-ios/Packages/ShellXAppCore && git commit -m "feat(shellx-ios): the coordinator signs in and deletes the account with an emailed code"`

---

### Task 5: `EmailSignInModel`

**Files:**
- Modify: `…/ShellXAppCore/Account/EmailSignInModel.swift`, `…/ShellXAppCore/Account/AppCoordinator.swift`
- Test: Create `…T/EmailSignInModelTests.swift`

**Interfaces:**
- Consumes: Task 4 (`requestEmailCode(email:)`, `signInWithEmailCode(challengeID:code:)`, `requestDeleteAccountCode()`, `deleteAccount(challengeID:code:)`, the coordinator's `clock`); `ManualClock`, `Gate` and `eventually` of the test support.
- Produces:

```swift
/// Sign-in with a code sent by email: the steps, what was typed, the Resend lock and the failure to show. The same
/// model runs the code step of Delete Account for an email session (other `request` and `submit`, `autoSubmit` false).
@MainActor @Observable
public final class EmailSignInModel {
    public enum Step: Equatable, Sendable { case idle, email, sending, code, verifying, done }
    /// What the screen shows: `.providers` for idle and done; `.email` for email and a first sending; `.code` for code,
    /// verifying and the sending of a resend.
    public enum Panel: Equatable, Sendable { case providers, email, code }

    public static let codeLength = 6
    public static let maxEmailBytes = 254
    /// Trimmed, it has an "@" that is not first, and after it a "." that is neither the next character nor the last.
    public nonisolated static func looksLikeEmail(_ text: String) -> Bool
    /// The first six digits of `text` as ASCII (any character with a `wholeNumberValue` of 0–9 counts); the rest is dropped.
    public nonisolated static func digits(_ text: String) -> String

    public private(set) var step: Step                // .idle
    public var email: String                          // what the email field holds
    public private(set) var code: String              // 0–6 ASCII digits
    public private(set) var sentTo: String?           // the relay's normalized address; nil until a code was sent
    public private(set) var resendIn: Int             // whole seconds until Resend unlocks, rounded up; 0 when it can be pressed
    public private(set) var error: SignInError?
    public var panel: Panel { get }
    public var isEntering: Bool { get }               // panel != .providers
    public var isBusy: Bool { get }                   // .sending or .verifying
    public var canSend: Bool { get }                  // .email and looksLikeEmail(email)
    public var codeIsLive: Bool { get }               // a code was sent and can still be verified: false before a send and after a 410
    public var canVerify: Bool { get }                // .code, six digits and codeIsLive
    public var canResend: Bool { get }                // .code and resendIn == 0

    init(clock: any Clock<Duration>, autoSubmit: Bool = true,
         request: @escaping @MainActor (String) async throws -> EmailChallenge,
         submit: @escaping @MainActor (_ challengeID: String, _ code: String) async throws -> Void)

    public func begin(email: String? = nil)
    public func cancel()
    public func changeEmail()
    public func sendCode() async
    public func resend() async
    public func setCode(_ text: String)
    public func verify() async
}

// AppCoordinator
/// The email sign-in of the sign-in screen: one model for the coordinator's life (`@ObservationIgnored … lazy var`; the
/// `@Observable` macro takes no lazy property otherwise). Its closures call `requestEmailCode` and `signInWithEmailCode`.
public var emailSignIn: EmailSignInModel { get }
/// A new model for the deletion sheet of an email session, already at `.email` with the account's address, `autoSubmit`
/// false; `request` ignores its argument and calls `requestDeleteAccountCode()`, `submit` calls `deleteAccount(challengeID:code:)`.
public func makeDeleteAccountCode() -> EmailSignInModel
```

Rules (the tests pin each):

| Call | Allowed in | Effect |
| --- | --- | --- |
| `begin(email:)` | `.idle`, `.done` | → `.email`; `error` nil; sets `email` when given |
| `cancel()` | `.email`, `.code` | → `.idle`; drops the challenge, `code`, `sentTo`, `error` and the lock; keeps `email` |
| `changeEmail()` | `.code` | → `.email`; drops the same things |
| `sendCode()` | `.email` with `canSend` | trims `email`; over 254 UTF-8 bytes: `error = .invalidEmail`, no request. Else `.sending`, `error` nil, `request(trimmed)`. Reply: keep the challenge, `sentTo = challenge.email`, `code = ""`, the lock starts at `challenge.resendIn`, → `.code`. Failure: → `.email` with `error` |
| `resend()` | `.code` with `canResend` | `.sending` (the panel stays `.code`), `request(sentTo)`. Reply: as above (the new challenge replaces the old). Failure: → `.code` with `error`; the old challenge and `resendIn == 0` stay |
| `setCode(_:)` | `.code` with `codeIsLive` | `code = digits(text)`; an edit clears an `.invalidCode` error; when the code changed to six digits and `autoSubmit` is on, starts `verify()` |
| `verify()` | `.code` with `canVerify` | `.verifying`, `error` nil, `submit(challengeID, code)`. Success: → `.done`; `email`, `code`, `sentTo`, the challenge and the lock are cleared. `.invalidCode`: → `.code`, `code = ""`. `.codeExpired`: → `.code`, `code = ""`, the challenge dropped (`codeIsLive` false), `resendIn = 0`. `.switchFromSignedInDevice`: → `.email`, `code = ""`, `sentTo` nil, no challenge, no lock. Any other failure: → `.code`, `code` kept |

Every other call in every other step does nothing (a second `verify()` while one runs, `cancel()` while busy). A thrown error that is not a `SignInError` shows as `.server(code: "unknown")`. `resendIn` is computed from the time passed on the clock since the reply (never by counting ticks), refreshed about once a second by one task that ends at 0, on `cancel()`, on `changeEmail()` and on success; open the clock existential with a generic helper as `VoiceCapabilityCache.stopwatch` does.

- [ ] **Step 1: Write the failing tests** (`@MainActor final class EmailSignInModelTests`). `signedOut()` is a launched `CoordinatorRig`; `atCode()` is that rig after `begin()`, `email = "phu@example.com"`, `await sendCode()` (step `.code`, `challenge-1`, 60 seconds of lock); `model` is `rig.coordinator.emailSignIn`; `verifies` lists the relay's `.signInWithEmailCode` calls as `"<challengeID> <code>"`. A relay error is set with `rig.relay.setError(_:for:)`; effects that come from the auto-submit are awaited with `eventually { }`.

| Test | Arrange and act | Assertions |
| --- | --- | --- |
| `testTheStepsFromTheButtonToTheSignedInAccount` | `signedOut()`; `begin()`; type the address; `sendCode()`; `setCode("123456")`; then `coordinator.signOut()`, `begin()` | at first `step == .idle`, `panel == .providers`, `coordinator.emailSignIn === coordinator.emailSignIn`; after `begin()` `step == .email`, `isEntering`; `looksLikeEmail` is false for `""`, `"phu"`, `"phu@"`, `"phu@example"`, `"@example.com"`, `"phu@.com"`, `"phu@example."` and true for `"  phu@example.com "`; `canSend` false on an empty field, true with the address; after the send `step == .code`, `sentTo == "phu@example.com"`, `resendIn == 60`, `!canVerify`; after the sixth digit, eventually `phase == .signedIn(email: "user@example.com")`, `authMethod == .email`, `step == .done`, `panel == .providers`, `email == ""`, `code == ""`, `sentTo == nil`; `relay.calls.first == .requestEmailCode(email: "phu@example.com", locale: "vi")`, `verifies == ["challenge-1 123456"]`; after the sign-out and `begin()`: `step == .email`, `email == ""` |
| `testTheEmailIsTrimmedAndOver254BytesIsRefusedWithoutARequest` | `email = "  Phu@Example.com \n"`, `sendCode()`; then `changeEmail()`, `relay.resetCalls()`, `email = String(repeating: "a", count: 243) + "@example.com"` (255 bytes), `sendCode()` | first: `relay.calls == [.requestEmailCode(email: "Phu@Example.com", locale: "vi")]`, `sentTo == "phu@example.com"` (the relay's); then `canSend` is true, and after the send `step == .email`, `error == .invalidEmail`, `relay.calls == []` |
| `testASendFailureStaysOnTheEmailStepAndTheSameTapRetries` | at the email step with the address; for each relay error `sendCode()`; then `setError(nil, …)`, `sendCode()` | `(400, "invalid_email") → .invalidEmail`, `(400, "disposable_email") → .disposableEmail`, `(429, "rate_limited") → .rateLimited`, `(502, "email_send_failed") → .emailSendFailed`, `(503, "email_sign_in_disabled") → .providerUnavailable`, `(404, "not_found") → .providerUnavailable`, `URLError(.notConnectedToInternet) → .network`, each with `step == .email` and `email == "phu@example.com"`; at the end `step == .code`, `error == nil` |
| `testTheCountdownFollowsTheClockAlsoAfterTimeAway` | `atCode()`; `resend()`; `clock.advance(by: .seconds(1))`; `setCode("12")`; `clock.advance(by: .seconds(45))` (the app was away: one late tick); `clock.advance(by: .seconds(14))`; `resend()`; `setCode("654321")` | `!canResend` and the locked `resend()` sends nothing (`relay.calls.count == 1`); eventually `resendIn == 59`; after the 45 seconds, eventually `resendIn == 14` with `step == .code` and `code == "12"`; after 14 more, eventually `canResend` and `resendIn == 0`; after the resend `relay.calls.last == .requestEmailCode(email: "phu@example.com", locale: "vi")`, `resendIn == 60`, `code == ""`; at the end `verifies == ["challenge-2 654321"]` |
| `testAPastedCodeIsCutToItsSixDigits` | `atCode()`; `setCode(" 123 456\n")` | `["123 456", " 12-34 56\n", "1234567", "١٢٣٤٥٦", "abc", "Your ShellX sign-in code is 123456"].map(EmailSignInModel.digits) == ["123456", "123456", "123456", "123456", "", "123456"]`; eventually `step == .done`; `verifies == ["challenge-1 123456"]` |
| `testVerifyTwiceSendsOneRequest` | `atCode()`; a `Gate` waits in the hook of `.signInWithEmailCode`; `setCode("123456")`; when `gate.waiting == 1`: `await verify()`, `setCode("999999")`, `cancel()`; `gate.open()` | while held `step == .verifying` before and after the three calls; eventually `step == .done`; `verifies == ["challenge-1 123456"]` |
| `testAWrongCodeEmptiesTheFieldAndKeepsTheChallenge` | `atCode()`; relay `(401, "invalid_code")`; `setCode("111111")`; then no error, `setCode("2")`, `setCode("222222")` | eventually `error == .invalidCode`, with `step == .code`, `code == ""`; after `"2"`: `error == nil`; at the end `verifies == ["challenge-1 111111", "challenge-1 222222"]` |
| `testAnExpiredCodeUnlocksResendAtOnce` | `atCode()`; relay `(410, "code_expired")`; `setCode("123456")`; then no error, `setCode("123456")`, `verify()`; `resend()`; `setCode("123456")` | eventually `error == .codeExpired`, with `code == ""`, `resendIn == 0`, `canResend`, `!codeIsLive`; the dead field takes nothing: after the second `setCode` `code == ""`, `!canVerify`, `error == .codeExpired` still, and `verifies.count == 1` after `verify()`; after the resend `codeIsLive`, `error == nil`; at the end `verifies.last == "challenge-2 123456"` |
| `testAPasswordAccountGoesBackToTheEmailStep` | `atCode()`; relay `(409, "switch_from_signed_in_device")`; `setCode("123456")` | eventually `step == .email`; `error == .switchFromSignedInDevice`; `email == "phu@example.com"`; `sentTo == nil`; `resendIn == 0` |
| `testOfflineKeepsWhatWasTypedAndTheSameTapRetries` | `atCode()`; relay `URLError(.notConnectedToInternet)`; `setCode("123456")`; then no error, `await verify()` | eventually `error == .network`, with `step == .code`, `code == "123456"`, `canVerify`; after `verify()`: `step == .done`, `coordinator.authMethod == .email` |
| `testCancelAndChangeEmailDropTheCodeAndKeepTheAddress` | `atCode()`; `setCode("12")`; `changeEmail()`; `sendCode()`; `cancel()`; `begin()`; `setCode("123456")` | after `changeEmail()`: `step == .email`, `email == "phu@example.com"`, `code == ""`, `sentTo == nil`; after `cancel()`: `step == .idle`, `panel == .providers`, `resendIn == 0`; after `begin()`: `email == "phu@example.com"`; a code typed outside the code step goes nowhere: `verifies == []` |
| `testTheDeletionModelNeverSubmitsByItself` | a launched rig whose vault holds the email session of Task 4; `makeDeleteAccountCode()`; `sendCode()`; `setCode("123456")`; twenty `Task.yield()`; `verify()` | the model is not `coordinator.emailSignIn`; `step == .email`, `email == "phu@example.com"`, and `relay.calls == []` (opening mails nothing); after the six digits `relay.calls == [.requestEmailCode(email: "phu@example.com", locale: "vi")]` and `canVerify`; after `verify()`: `relay.calls.last == .deleteAccountWithCode(challengeID: "challenge-1", code: "123456", token: "tok-old")`, `step == .done`, `phase == .signedOut(expired: false)` |

- [ ] **Step 2: Run them.** `toknix run swift test --package-path shellx-ios/Packages/ShellXAppCore --filter EmailSignInModelTests`. Expected: build error `value of type 'AppCoordinator' has no member 'emailSignIn'`.
- [ ] **Step 3: Commit the tests.** `git add shellx-ios/Packages/ShellXAppCore/Tests && git commit -m "test(shellx-ios): the email sign-in model: steps, the resend lock on a clock, pasted codes, one request per verify"`
- [ ] **Step 4: Implement** the model and the two coordinator members.
- [ ] **Step 5: Run and commit.** The Step 2 command three times in a row (the countdown tests must not flake), then `toknix run shellx-ios/scripts/dev.sh test core` (`==> test core: passed`). `git add shellx-ios/Packages/ShellXAppCore && git commit -m "feat(shellx-ios): EmailSignInModel: email step, code step, resend lock, failures"`

---

### Task 6: "or" and "Continue with email" on the sign-in screen

**Files:**
- Create: `shellx-ios/ShellX/UI/SignIn/EmailSignInButton.swift`, `shellx-ios/ShellXTests/Support/Bitmap.swift`, `shellx-ios/ShellXTests/EmailSignInRenderTests.swift`
- Modify: `shellx-ios/ShellX/UI/SignIn/SignInIntro.swift` (`SignInLayout`), `shellx-ios/ShellX/UI/SignIn/SignInView.swift` (`actions`), `shellx-ios/ShellX/AppGraph.swift`
- Test: Modify `shellx-ios/ShellXTests/SignInIntroTests.swift` (the layout tests), `shellx-ios/ShellXTests/SignInRenderTests.swift`

**Interfaces:**
- Consumes: Task 1 (`signin.email.or`, `signin.email.continue`), Task 5 (`coordinator.emailSignIn.begin()`), the intro's `SignInLayout`, `SignInView.actions`, `Bitmap`.
- Produces:

```swift
struct SignInLayout: Equatable, Sendable {
    /// Two columns from this width. No iPhone is this wide upright (440 at most) and every iPhone is wider on its side
    /// (667 at least); a keyboard changes the height of the room, never its width.
    static let sidewaysWidth: CGFloat = 500
    let logoSize: CGFloat      // 96; 72 when size.height < 688 or sideBySide
    let showsSubtitle: Bool    // size.height >= 788
    let showsGuide: Bool       // size.height >= 400
    let sideBySide: Bool       // size.width >= sidewaysWidth
    init(size: CGSize)
}
/// "Continue with email": a 44-point capsule like the two buttons over it, a soft tint (`Color("AccentText")` at 14 %)
/// with the label in `AccentText`, SF Symbol `envelope` 8 points before the text, `.callout.weight(.medium)`; disabled
/// it fades to 40 %; id `signin.email`.
struct EmailSignInButton: View { let action: () -> Void }
/// A hairline, `signin.email.or` in `.footnote` secondary, a hairline; the lines are hidden from accessibility.
struct SignInOrDivider: View {}
// AppGraph.swift (DEBUG): `AppGraph.preview(relay: FakeRelayAccount = FakeRelayAccount())` and
// `AppCoordinator.preview(relay: FakeRelayAccount = FakeRelayAccount())`, so a render test can preset the relay.
// Support/Bitmap.swift: the `Bitmap` of SignInRenderTests.swift, moved unchanged and no longer private, plus:
extension Bitmap {
    /// From the first to the last row (points from the top) that holds a run of at least `points` of `colour` (each
    /// channel within `tolerance`), and the columns (points) of the widest such run; nil when no row has one.
    func band(of colour: Colour, atLeast points: Int = 200, tolerance: Int = 3) -> (rows: ClosedRange<Int>, columns: Range<Int>)?
}
```

The column of `SignInView.actions`, 12 points apart: Google, Apple, `SignInOrDivider`, `EmailSignInButton` (all four `.disabled(running != nil)`), then the demo link. A tap on the email button clears the screen's `error` and calls `coordinator.emailSignIn.begin()`; what then shows is Task 7's. The two rows make the column 86 points taller (18 + 12 and 44 + 12), which is why the two height thresholds move by 88.

- [ ] **Step 1: Write the failing tests.** In `EmailSignInRenderTests` (`@MainActor`; a `*RenderTests` class, so `dev.sh screenshots` runs it in en and vi): `render(_ name:, on:, relay:, type:, _ drive:)` makes `AppCoordinator.preview(relay:)`, awaits `drive(coordinator.emailSignIn)`, and writes `SignInView(coordinator:, expired: false, startDemo: {}, motion: .still)` through `SnapshotWriter` (at `on.size` with `on.safeArea`, default the writer's own; at Dynamic Type `type`, default `.large`), returning the light and the dark image and their `Bitmap`s; `se` is 375 × 667 with a top inset of 20, `landscape` 852 × 393 with insets 59 left and right and 21 below (as `SignInRenderTests`); `tint(style)` is `Color("AccentText")` at 14 % over `Color("Background")` for that appearance (`round(0.14 · accent + 0.86 · background)` per channel of the two `Bitmap.Colour`s): the fill of the email button.

| Test | What it draws or builds | Assertions |
| --- | --- | --- |
| `SignInIntroTests.testAPhoneInPortraitGetsTheFullLogoAndTheGuide` (new body) | `SignInLayout(size:)` for 430 × 839, 393 × 759, 375 × 647 | 839: `logoSize == 96`, `showsSubtitle`; 759: `logoSize == 96`, `!showsSubtitle` (under 788 the taglines replace it), `showsGuide`, `!sideBySide`; 647: `logoSize == 72` (the small logo makes room for the email button), `!showsSubtitle`, `showsGuide`, `!sideBySide` |
| `SignInIntroTests.testAShortOrSidewaysWindowShrinksTheLogo` (new numbers) | 360 × 687, 360 × 688, 1000 × 800 | `logoSize` 72, 96, 72 |
| `SignInIntroTests.testTheKeyboardNeverTurnsTheScreenOnItsSide` (new) | 375 × 300 (an iPhone SE upright over a tall keyboard), 440 × 250, 667 × 375, 734 × 160 | `sideBySide` false, false, true, true |
| `SignInRenderTests.testASmallPhoneShowsTheWholeScreenWithoutScrolling` (two numbers) | as today | the Google button's first row `< 667 - 242` (under it Apple, or, the email button and the demo link: 44 + 12 + 44 + 12 + 18 + 12 + 44 + 12 + 44); the logo's side `> 66` and `< 76`; `isPlain(fromRow: 667 - 12)` stays |
| `EmailSignInRenderTests.testTheEmailButtonSitsUnderOrBelowApplesButton` | `render("signin-email-idle")` | in both appearances `band(of: tint)` is not nil; its `rows.lowerBound >= google + 44 + 12 + 44 + 12 + 12` (`google` = `firstRowWithAWhiteRun()`); `rows.count <= 46`; `columns.count > 300` |
| `EmailSignInRenderTests.testOnASmallPhoneAndOnItsSideTheEmailButtonAndTheDemoLinkFit` | `render("signin-email-idle-se", on: se)`, `render("signin-email-idle-landscape", on: landscape)` | SE: `band.rows.upperBound + 12 + 44 <= 667` (the demo link fits under it) and `isPlain(fromRow: 667 - 12)`; landscape: `band.columns.lowerBound > 852 / 2` and `band.rows.upperBound + 12 + 44 <= 393 - 21` |

- [ ] **Step 2: Run them.** `toknix run shellx-ios/scripts/dev.sh test app`. Expected: `==> test app: FAILED` with build errors (`cannot find 'Bitmap' in scope` in the new file, `extra argument 'relay' in call`).
- [ ] **Step 3: Commit the tests.** `git add shellx-ios/ShellXTests && git commit -m "test(shellx-ios): the sign-in screen has room for or and Continue with email on every iPhone"`
- [ ] **Step 4: Implement.** Move `Bitmap` (no other change to it), add `band`, the two views, the `actions` rows, the `preview(relay:)` parameters and the `SignInLayout` numbers; update the intro's comments that say "wider than it is high", 600 and 700.
- [ ] **Step 5: Run and commit.** `toknix run shellx-ios/scripts/dev.sh test app` (green). If the small-phone test still shows the demo link cut, lower the logo for `size.height < 688` from 72 to 56 (never hide the guide, never shrink text), adjust the numbers in the tests and say so in the report. On the largest phones on their side the right column with the guide is about as tall as the room (by estimate 428 points in 419, the overflow being bottom padding): if the intro's `testALargePhoneOnItsSideAlsoShowsTheSteps` now finds ink under the home indicator, show the guide in two columns only from 430 points of height, update that test and the layout test that names 419, and say so. `git add shellx-ios/ShellX shellx-ios/ShellXTests && git commit -m "feat(shellx-ios): or and Continue with email on the sign-in screen"`

---

### Task 7: The email step and the code step

**Files:**
- Create: `shellx-ios/ShellX/UI/SignIn/EmailSignInPanel.swift`, `shellx-ios/ShellX/UI/SignIn/EmailCodeField.swift`, `shellx-ios/ShellXTests/EmailSignInViewTests.swift`
- Modify: `shellx-ios/ShellX/UI/SignIn/SignInView.swift`, `shellx-ios/ShellX/UI/SignIn/SignInIntro.swift` (`SignInLayout`)
- Test: Modify `shellx-ios/ShellXTests/EmailSignInRenderTests.swift`, `shellx-ios/ShellXTests/SignInIntroTests.swift`

**Interfaces:**
- Consumes: Task 5 (`EmailSignInModel`), Task 6 (`SignInLayout`, `Bitmap.band`, `preview(relay:)`, `render`), Task 1 (keys), `Keyboard.swift` (`tracksKeyboard`), `PrimaryButtonStyle`, `Color.appSurface`.
- Produces:

```swift
struct SignInLayout {   // one more input and one more output
    let showsTaglines: Bool
    /// `entry`: the email or the code step shows, or the keyboard is still up. Then the logo is 48 and the taglines,
    /// the subtitle and the guide are hidden, whatever the height. `sideBySide` does not depend on it.
    init(size: CGSize, entry: Bool = false)
}
/// The email step and the code step, in the place of the buttons.
struct EmailSignInPanel: View { @Bindable var model: EmailSignInModel; let startDemo: (() -> Void)? }
/// The six-digit field with the failure under it. It always shows `model.code` (a seventh digit or a letter never shows).
struct EmailCodeField: View { @Bindable var model: EmailSignInModel; let label: LocalizedStringResource }
/// "Resend code", or "Resend code in N s" while locked (monospaced digits, so the row does not move).
struct EmailResendButton: View { let model: EmailSignInModel }
```

How the intro behaves (the logo, the title, the typed taglines, the subtitle, the guide):

| The screen shows | Logo | Taglines | Subtitle | Guide | Columns |
| --- | --- | --- | --- | --- | --- |
| the buttons, upright, 788 points high or more | 96 | typed | yes | yes | one |
| the buttons, upright, 688–787 | 96 | typed | no | yes | one |
| the buttons, upright, under 688 (iPhone SE: 647) | 72 | typed | no | yes | one |
| the buttons, on its side | 72 | typed | no | from 400 high | two |
| the email or the code step, keyboard up or down | 48 | hidden | hidden | hidden | one upright, two on its side |

- The title stays in every row. The intro never restarts: `introStart` is kept, the logo goes on blinking and glowing at 48 points, and when the buttons come back the taglines are where their schedule is by then.
- `entry` is `model.isEntering || keyboardUp` (`@State keyboardUp` through `tracksKeyboard`), so the screen never lays itself out for the buttons in the room a keyboard leaves; after Cancel the intro unfolds when the keyboard starts to leave.
- iPhone SE (375 × 667) with a 260-point keyboard up (387 points left under the status bar): 24 of padding, the 48-point logo, the title, then the field and its primary button end near 257 (email step) and 332 (code step), both above the keyboard; the rows under them are reached by scrolling (`.scrollDismissesKeyboard(.interactively)` on the screen's `ScrollView`).
- On its side: the logo and the title on the left, the step on the right; the keyboard leaves about 160 points and the `ScrollView` brings the focused field above it.
- Large Dynamic Type: nothing has a fixed height (fields and buttons use `minHeight`), every text wraps, the screen scrolls; the logo stays 48. The primary action never needs its button in view: the return key of the email field is Send, and the sixth digit submits.
- Reduce Motion (`motion == .still`): the step changes without animation; otherwise `.snappy(duration: 0.25)`.
- Leaving the app to read the mail and coming back changes nothing on the screen: the model lives in the coordinator, the field keeps the keyboard, and the countdown is computed from elapsed time, so its first tick after the return shows the right number. No `scenePhase` hook is added.

`SignInView`: one tree for both arrangements, so a turn of the phone keeps the fields (and the keyboard): `AnyLayout(HStackLayout(alignment: .top, spacing: 32))` on its side, `AnyLayout(VStackLayout(alignment: .leading, spacing: 16))` upright, holding the hero and one `VStack(alignment: .leading, spacing: 16)` with the guide, the notices and the actions; the `maxWidth` values (820 / 520, `.infinity` for the columns on its side) become values of one modifier instead of two branches. `actions` shows the buttons for `model.panel == .providers`, else `EmailSignInPanel(model: coordinator.emailSignIn, startDemo: startDemo)`; the expired line, the notice and a Google or Apple failure show with the buttons only (ruling 17).

`EmailSignInPanel`, 12 points apart, every row full width:
- **Email step:** the email field (`signin.email.field` as placeholder and accessibility label; `.keyboardType(.emailAddress)`, `.textContentType(.username)`, no autocapitalization, no autocorrection, `.submitLabel(.send)`, `onSubmit` sends when `canSend`; `minHeight` 50 on `Color.appSurface`, corner radius 12; id `signin.email.field`); the failure (`SignInErrorText`, `.callout`, `Color("StatusError")`, id `signin.email.error`); **Send code** (`PrimaryButtonStyle`, `.headline`, a `ProgressView` in its place while `.sending` with the accessibility label kept, disabled unless `canSend`; id `signin.email.send`); **Cancel** (`common.cancel`, a text button in `AccentText`, `minHeight` 44, disabled while busy; id `signin.email.cancel`); the demo link when `startDemo` is not nil.
- **Code step:** `signin.email.sentTo %@` with `model.sentTo` (`.callout`, secondary, wraps; id `signin.email.sentTo`); `EmailCodeField(model:, label: "signin.email.code")` (`.keyboardType(.numberPad)`, `.textContentType(.oneTimeCode)`, `.title2.monospacedDigit()`, centred, the same box as the email field, disabled while busy and while `!codeIsLive`; id `signin.email.code`; the failure under it); **Verify** (primary, busy while `.verifying`, disabled unless `canVerify`; id `signin.email.verify`); `EmailResendButton` (disabled unless `canResend`; id `signin.email.resend`); **Use a different email** (text button, disabled while busy; id `signin.email.change`).
- Focus follows the panel: the email field when the email step shows, the code field when the code step shows and each time it can be typed in again (after a wrong code emptied it, after a resend). A new failure and the "We sent a code…" sentence are announced (`AccessibilityNotification.Announcement`), as the Google failure is today.

- [ ] **Step 1: Write the failing tests.** Render tests use Task 6's `render`; `atEmail(model)` is `begin()` and `email = "phu@example.com"`; `atCode(model)` is that and `await sendCode()`; `surface(style)` is `Bitmap.Colour(UIColor(named: "Surface"), style:)`, the fill of both fields; a keyboard of height `h` is the SE size with safe-area insets top 20 and bottom `h` (how the system presents a keyboard to the view). `EmailSignInViewTests` (`@MainActor`) hosts `SignInView(coordinator: .preview(relay:), expired: false, startDemo: {}, motion: .still)` live through `WindowHost` (393 × 852); `textFields` are the `UITextField`s under the host's window, found as `WindowHost.surfaces(in:)` finds surfaces; waits use `WorkspaceRig.eventually`.

| Test | What it draws or does | Assertions |
| --- | --- | --- |
| `SignInIntroTests.testWhileAStepShowsTheIntroFoldsWhateverTheHeight` | `SignInLayout(size:, entry: true)` for 393 × 759, 375 × 387, 430 × 839, 734 × 160 | each: `logoSize == 48`, `!showsTaglines`, `!showsSubtitle`, `!showsGuide`, `sideBySide == SignInLayout(size: size).sideBySide`; and `SignInLayout(size: CGSize(width: 393, height: 759)).showsTaglines` |
| `EmailSignInRenderTests.testTheStepsRender` | `signin-email-idle`; `signin-email-step` (`atEmail`); `signin-code-step` (`atCode`); `signin-code-step-resend` (relay `setEmailChallenge(.success(EmailChallenge(challengeID: "c", expiresIn: 600, resendIn: 0, email: "phu@example.com")))`); `signin-code-step-error` (relay `(401, "invalid_code")`, `setCode("123456")`, wait for `error == .invalidCode`); `signin-email-step-error` (relay `(400, "disposable_email")`, `sendCode()`) | the idle, email and code images differ from each other, and the error image from the code image; in the email and code images of both appearances `band(of: surface)` is not nil (the field) and `band(of: tint)` is nil (no email button while a step shows) |
| `EmailSignInRenderTests.testAKeyboardOnASmallPhoneKeepsOneColumnAndTheFieldAboveIt` | `signin-code-se-keyboard` (`atCode`, keyboard 260); `signin-email-se-keyboard` (`atEmail`, keyboard 260); `signin-code-se-tall-keyboard` (`atCode`, keyboard 300: 375 × 347 of room, wider than tall) | 260, both steps: the field's `rows.upperBound + 12 + 50 <= 667 - 260` (the field and its primary button are above the keyboard); 300: `columns.count > 300` (one column) and `rows.upperBound <= 667 - 300` |
| `EmailSignInRenderTests.testOnItsSideTheStepIsBesideTheLogo` | `signin-code-landscape` (`atCode`, `landscape`) | the field's `columns.lowerBound > 852 / 2`; in the light image `darkSquareSide()` is `> 42` and `< 52` (the logo stays, at 48) |
| `EmailSignInRenderTests.testALongEmailWrapsAndKeepsTheFieldOnTheScreen` | `signin-code-long-email` on `se`, the address `String(repeating: "very.long.name.", count: 8) + "x@a-long-mail-domain.example.com"` (152 characters) | `band(of: surface)` is not nil (the sentence wrapped; the field is on the first screen) and its `columns.count <= 375 - 32` (nothing was pushed wider than the screen) |
| `EmailSignInRenderTests.testLargeTypeKeepsTheFieldOnTheFirstScreen` | `signin-code-large-type` (`atCode`, `.xxxLarge`); `signin-code-accessibility-type` (`atCode`, `.accessibility2`, on `se`) | at `.xxxLarge` `band(of: surface)` is not nil in both appearances; the accessibility image is written for the screenshot check of Task 9 |
| `EmailSignInViewTests.testTheFieldsAskForTheRightKeyboards` | host at the email step; a second host at the code step | one `UITextField` each; email: `keyboardType == .emailAddress`, `textContentType == .username`, `autocapitalizationType == .none`, `autocorrectionType == .no`, `returnKeyType == .send`, `text == "phu@example.com"`; code: `keyboardType == .numberPad`, `textContentType == .oneTimeCode` |
| `EmailSignInViewTests.testTheCodeFieldShowsOnlyDigitsAndAWrongCodeEmptiesIt` | relay `(401, "invalid_code")`; host at the code step; `field.insertText("12 3-45")`; `field.insertText("67")` | eventually `field.isFirstResponder` (the code step takes the keyboard); eventually `field.text == "12345"` and `model.code == "12345"`; then eventually `model.error == .invalidCode` and `field.text == ""`; the relay saw one `.signInWithEmailCode`, with code `"123456"` |
| `EmailSignInViewTests.testTurningThePhoneInTheCodeStepKeepsTheDigitsAndTheKeyboard` | host at the code step; `model.setCode("123")`; wait until the field is first responder with text `"123"`; `host.window.frame = CGRect(x: 0, y: 0, width: 852, height: 393)`, the controller's view to the window's bounds, `layoutIfNeeded()` | eventually the field's frame in the window has `minX > 852 / 2` (the right column); `host.textFields.first === field` (turning did not rebuild it); `field.isFirstResponder`; `field.text == "123"`; `model.step == .code` |

- [ ] **Step 2: Run them.** `toknix run shellx-ios/scripts/dev.sh test app`. Expected: `==> test app: FAILED` with build errors (`extra argument 'entry' in call`, `value of type 'SignInLayout' has no member 'showsTaglines'`).
- [ ] **Step 3: Commit the tests.** `git add shellx-ios/ShellXTests && git commit -m "test(shellx-ios): the email and code steps: fields, focus, a turned phone, a keyboard on a small phone, a long address"`
- [ ] **Step 4: Implement** the three views, the `SignInLayout` input and the `SignInView` changes described above.
- [ ] **Step 5: Run and commit.** `toknix run shellx-ios/scripts/dev.sh test app` (green; the intro's own render tests still pass, since upright the nested column draws what the flat one drew). If a hosted test cannot take the keyboard focus in the test host on this simulator, keep its other assertions, turn the focus assertion into an `XCTSkip` with the reason, and say so in the report: do not weaken the product code for it. `git add shellx-ios/ShellX shellx-ios/ShellXTests && git commit -m "feat(shellx-ios): the email step and the code step on the sign-in screen"`

---

### Task 8: Settings › Account: the label, and Delete Account with a code

**Files:**
- Modify: `shellx-ios/ShellX/UI/Settings/AccountSection.swift`, `AccountActions.swift`, `DeleteAccountSheet.swift`
- Test: Modify `shellx-ios/ShellXTests/AccountRenderTests.swift`, `shellx-ios/ShellXTests/DeleteAccountRenderTests.swift`

**Interfaces:**
- Consumes: Task 5 (`makeDeleteAccountCode()`, the model), Task 7 (`EmailCodeField`, `EmailResendButton`), Task 1 (`settings.account.method.email`, `settings.account.delete.codeIntro`, `.codeField`).
- Produces:

```swift
struct AccountActions { …
    /// A new model for the deletion sheet of an email session; nil in fakes that have none.
    var deleteCode: (@MainActor () -> EmailSignInModel)? = nil
}   // AccountActions(coordinator:) sets `deleteCode: { coordinator.makeDeleteAccountCode() }`

struct DeleteAccountSheet: View { …
    /// Delete Account for an email session, driven by `code` (made by `makeDeleteAccountCode()`).
    init(code: EmailSignInModel, close: @escaping () -> Void)
}
```

- `AccountSection`: the email row's label is `settings.account.method.email` when `account?.authMethod == .email`, else `signin.email` (two literal `LocalizedStringResource`s, so `check-strings.py` reads both keys). "Delete Account…" on an email session with `deleteCode` opens `DeleteAccountSheet(code: model, close:)` with a new model each time; closing calls `model.cancel()`; `.interactiveDismissDisabled(model.isBusy)`. Other sessions are unchanged.
- The sheet's code branch (`.presentationDetents([.large])`: a keyboard comes up), with today's icon and title:
  - `model.panel == .email` (nothing sent yet, or the first sending): `settings.account.delete.message`, the failure (id `deleteAccount.error`), the destructive **Delete Account** button (`settings.account.delete.button`, `SecondaryButtonStyle(color: Color("StatusError"))`, id `deleteAccount.delete`) that calls `model.sendCode()` and shows a `ProgressView` while `.sending`, then Cancel.
  - `model.panel == .code`: `settings.account.delete.codeIntro`, `EmailCodeField(model:, label: "settings.account.delete.codeField")` focused, the "Deleting…" row while `.verifying`, the destructive **Delete Account** button that calls `model.verify()` (disabled unless `canVerify`; the sixth digit never presses it), `EmailResendButton`, Cancel (disabled while busy).
  - After the deletion the coordinator is signed out and the screen leaves with its sheet, as for Google.

- [ ] **Step 1: Write the failing tests.**

| Test | What it draws or does | Assertions |
| --- | --- | --- |
| `AccountRenderTests.testSettingsOfAnEmailSessionNameTheMethod` | `settings` with `actions(.google)` and `settings-email` with `actions(.email)`, both for `phu@example.com` | the two light images differ; `String(localized: "settings.account.method.email") != String(localized: "signin.email")` |
| `DeleteAccountRenderTests.testDeleteByCodeRendersEveryStep` | `let coordinator = AppCoordinator.preview(relay: relay)` (its hub stopped in a teardown block); `try await coordinator.signInWithEmailCode(challengeID: "challenge-0", code: "123456")`; `let model = coordinator.makeDeleteAccountCode()`; draw `delete-account-code-confirm`; `await model.sendCode()`; draw `delete-account-code`; relay `(401, "invalid_code")` for `.deleteAccountWithCode`; `model.setCode("123456")`; `await model.verify()`; draw `delete-account-code-error` | `coordinator.authMethod == .email` before and after the wrong code; the confirm and the code images differ, and the error image from the code image; in the light images `band(of:)` of `Bitmap.Colour(UIColor(named: "Surface"), style: .light)` is nil for the confirm step and not nil for the code step (the field); `model.error == .invalidCode` |

- [ ] **Step 2: Run them.** `toknix run shellx-ios/scripts/dev.sh test app`. Expected: `==> test app: FAILED` with the build error `extra argument 'code' in call` (or `incorrect argument label`).
- [ ] **Step 3: Commit the tests.** `git add shellx-ios/ShellXTests && git commit -m "test(shellx-ios): Settings names an email session and deletes its account with a code"`
- [ ] **Step 4: Implement** the Produces block and the two descriptions above.
- [ ] **Step 5: Run and commit.** `toknix run shellx-ios/scripts/dev.sh test app` (green). `git add shellx-ios/ShellX && git commit -m "feat(shellx-ios): Settings names an email session and deletes its account with a code"`

---

### Task 9: Verify, screenshots, contracts, report

**Files:**
- Modify: `docs/superpowers/plans/2026-11-07-shellx-mobile-contracts.md`

- [ ] **Step 1: Full checks** (one simulator run at a time):
  - `toknix run swift test --package-path shellx-link` → `with 0 failures`; `bash scripts/shellx/check-link-license.sh` → exit 0
  - `bash scripts/shellx/check-ios-license.sh` → `check-ios-license: ok`; `python3 shellx-ios/scripts/check-strings.py` → `check-strings: ok (N keys)`; `python3 shellx-android/scripts/import-strings.py --check` → `import-strings: ok (…)`
  - `toknix run shellx-ios/scripts/dev.sh test core` and `toknix run shellx-ios/scripts/dev.sh test app` → `passed` (nothing red beyond Task 0's baseline)
  - `toknix run shellx-ios/scripts/dev.sh test release` → `passed`: an unsigned Release build with no account and no device, the only check that no Debug-only name (`FakeRelayAccount`, `preview(relay:)`) reached the App Store build. The hand-off's standing rules allow it; if the brief for this run says simulator only in the strict sense, skip it and say so.
  - `python3 scripts/verify-local.py` → `PASSED`, or only the `feature-flags` failure the hand-off lists as known noise.
- [ ] **Step 2: Screenshots, en and vi, light and dark.** `toknix run shellx-ios/scripts/dev.sh screenshots <scratch dir>/email-signin-shots` → `screenshots written to …`. Open every `signin-email-*`, `signin-code-*`, `settings-email-*` and `delete-account-code-*` PNG (each exists as `-light-en`, `-dark-en`, `-light-vi`, `-dark-vi`), and the intro's `signin-se-*`, `signin-landscape*` and `signin-intro-*` once more. Fix clipped or overlapping text, a wrapped button label that cannot be read, a missing translation; rerun. Copy this plan's PNGs to `.superpowers/sdd/2026-11-11-email-code-signin/ios-screenshots/` of the main checkout (git-ignored) for the reviewer.
- [ ] **Step 3: Localization audit** (CLAUDE.md): print the 18 keys with their `en` and `vi` (a `python3 -c` over the catalog like Task 0 Step 3, printing `key | en | vi`); run `grep -rnE '(Text|Button|Label)\(\s*"' shellx-ios/ShellX` (no output). Put both in the report, with every key whose catalog text differs from Task 1's table (the Android part's wording won).
- [ ] **Step 4: Contracts.** In `docs/superpowers/plans/2026-11-07-shellx-mobile-contracts.md`: if the relay or the Android part already opened a section for email + code sign-in (`grep -n -i "email + code\|email code\|auth/email"` on that file), add the block of "Contract additions" below under it as its iPhone paragraph; otherwise add it as a new last section "## N. Email + code sign-in: iPhone (plan `2026-11-11-shellx-email-code-signin-ios.md`)". Correct any name in the block that landed differently. `git add docs/superpowers/plans/2026-11-07-shellx-mobile-contracts.md && git commit -m "docs(shellx): contracts: email + code sign-in on the iPhone"`
- [ ] **Step 5: Report and stop.** `git log --oneline develop..HEAD`, the test counts of Step 1, the screenshot directory, the localization audit, every place where the landed code differs from this plan (and why), and what stays unchecked: no device, no real relay, no real email, no autofill from Mail, no real keyboard (the hosted tests draw none). Do not merge and do not push: the orchestrator reviews the branch as a whole and lands it; the hand-off file is the orchestrator's too.

---

## Contract additions (the text for Task 9 Step 4)

- **`ShellXLinkAccount`** (§4): `EmailChallenge { challengeID, expiresIn, resendIn, email }` (redacted descriptions); `RelayAPI.requestEmailCode(email:locale:) -> EmailChallenge`, `signInWithEmailCode(challengeID:code:deviceName:clientKey:) -> AccountSignIn`, `deleteAccount(challengeID:code:token:)`. A challenge reply is accepted only with a base64url `challenge_id` of 1–128 characters, `expires_in` > 0, `resend_in` ≥ 0 and an email.
- **iPhone account state:** `AccountAuthMethod.email` (stored as `"auth_method": "email"`; a session without the field is still `password`). `SignInError` gains `invalidEmail`, `disposableEmail`, `invalidCode`, `codeExpired`, `emailSendFailed`; 503 `email_sign_in_disabled` and, for the email calls only, 404 `not_found` read as `providerUnavailable`; 400 `invalid_device` and anything else as `server`.
- **Strings** (iPhone catalog names; Android's importer strips the argument): `signin.email.continue`, `.or`, `.field`, `.send`, `signin.email.sentTo %@`, `signin.email.code`, `.verify`, `.resend`, `signin.email.resendIn %lld`, `.change`; `signin.error.invalidEmail`, `.disposableEmail`, `.invalidCode`, `.codeExpired`, `.emailSendFailed`; `settings.account.method.email`; `settings.account.delete.codeIntro`, `.codeField`. The "check your spam folder" sentence of the spec's §9 is part of `signin.email.sentTo %@`. The email step's way back is the existing `common.cancel`.
- **Behaviour the other apps can mirror:** one field for the six digits; pasted text is cut to its first six digits; the sixth digit submits a sign-in and never a deletion; 401 `invalid_code` empties the field and keeps the challenge; 410 `code_expired` empties the field, turns it and Verify off until a new code is sent, and ends the Resend lock at once; 409 `switch_from_signed_in_device` returns to the email step; an address over 254 bytes is refused without a request; Resend counts down from the reply's `resend_in` by elapsed time; Delete Account mails the code on the press of the button, not when the sheet opens.
- **iPhone sign-in screen:** `SignInLayout(size:entry:)`: logo 96, 72 under 688 points of height or on its side, 48 while a step shows; subtitle from 788 points; guide from 400; two columns from 500 points of width (never from the height, which a keyboard changes); while the email or the code step shows, the taglines, the subtitle and the guide are hidden.

## Spec notes

- Spec §3 step 2 lists what the email step holds and no way back to the Google and Apple buttons; without one the step is a dead end (ruling 7).
- Spec §3 step 3 submits on the sixth digit. For Delete Account that would delete an account on a paste or an autofill, so the deletion sheet waits for its button (ruling 10).
- `settings.account.delete.message` ends "To confirm, you sign in once more." For an email session the confirmation is a code; the spec adds no key for it and the sentence is close enough to stay. `signin.error.reauthRequired` names "the Google or Apple account"; on the code path it can only follow a change of the account's email by a Google link on another device, and then that advice is right.
- 410 `code_expired` is also the fifth wrong try, so the phone cannot tell "expired" from "too many tries": `signin.error.codeExpired` says "no longer works".
- Nothing of a running sign-in is persisted. When iOS ends the app while the user reads the mail, the screen starts over and a new request replaces the mailed code on the relay. Keeping the challenge in the Keychain for ten minutes would close this; it is not in the spec.
- The code field is `.oneTimeCode`: iOS 17 offers a code from Mail only when Apple Mail recognizes the message, which depends on the relay's subject and body (spec §4); it cannot be tested here.
- Spec §10 asks whether a relay URL override serves a manual try. The app has one (`dev.sh sim --api http://127.0.0.1:8787`, Debug only); a run against a local relay is possible once the relay part has landed and is not part of this plan (no relay, no key, and nobody to tap the simulator).
- The repo's testing skill prefers Swift Testing; every touched target is XCTest, so the new tests are XCTest.
