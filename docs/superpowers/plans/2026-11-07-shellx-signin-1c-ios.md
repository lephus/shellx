# ShellX iPhone sign-in (plan 1C) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The iPhone app signs in with Google or Apple, links a hidden-email Apple ID to a Mac's account through the Mac's QR code, switches a password session to Google in place, deletes the account in the app, and offers "Try without an account" in every build, with no password field left.

**Architecture:** shellx-link's `ShellXLinkAccount` gains the relay calls of contracts §2 (the §4 API) and an Apple-link poll loop that mirrors `PhonePairing`. `ShellXAppCore` gains a PKCE Google OAuth client (the code exchange runs on the phone), an `IdentityProviding` seam and new `AppCoordinator` flows (Google, Apple, Apple link, switch, delete) that reuse today's vault and wipe rules. The app target implements the seam with `ASWebAuthenticationSession` and `ASAuthorizationController`, rewrites the sign-in screen, reuses the pairing sheet for "Connect to Your Mac", and moves the demo into a new `ShellXDemo` package target that ships in Release behind a "Demo · Exit" banner.

**Tech Stack:** Swift 6.0 (strict concurrency), SwiftUI, iOS 17, AuthenticationServices, CryptoKit, XCTest, `swift test`, `shellx-ios/scripts/dev.sh`, bash (`release/mobile/ios.sh`, `scripts/shellx/check-ios-license.sh`).

**Spec:** `docs/superpowers/specs/2026-11-07-shellx-google-sign-in-design.md` (S1: §5, §6.3, §6.3b, §6.4, §6.6, §6.8, §9), `docs/superpowers/specs/2026-11-07-shellx-android-app-design.md` §7.4b, and the shared names in `docs/superpowers/plans/2026-11-07-shellx-mobile-contracts.md` (§1, §2, §4). Read `shellx-ios/README.md` before Task 3.

## Global Constraints

- Licence boundary (S1 §5, `shellx-ios/README.md`): Apple frameworks, the app's own code and shellx-link only. No GoogleSignIn SDK, no network package, nothing copied from `ios/`, `Packages/`, `Sources/`, `cmux-tui/` or `shellx-core/` (that includes `ios/cmux/Assets.xcassets/GoogleLogo.imageset`). `AuthenticationServices` and `CryptoKit` are already on the allowlist of `scripts/shellx/check-ios-license.sh`.
- Google's page opens only in `ASWebAuthenticationSession`, never in an embedded web view (S1 §4).
- Relay routes, bodies and error codes exactly as contracts §2. `device` is `{kind: "mobile", platform: "ios", name, public_key}`, `public_key` base64url without padding (as `login` sends it today).
- Apple nonce rule (contracts §2): Apple gets `sha256_hex(relay nonce)` (lowercase hex of SHA-256 over the nonce's UTF-8); the relay gets the raw nonce. Google gets the raw nonce.
- Google, iOS client (no secret): authorization `https://accounts.google.com/o/oauth2/v2/auth`, token `https://oauth2.googleapis.com/token`, `response_type=code`, `scope=openid email`, `prompt=select_account`, PKCE `S256`, a random `state`; for client ID `<prefix>.apps.googleusercontent.com` the callback scheme is `com.googleusercontent.apps.<prefix>` and the redirect URI `com.googleusercontent.apps.<prefix>:/oauth2redirect`.
- Apple: `ASAuthorizationAppleIDProvider` request with `requestedScopes = [.email]` only; entitlement `com.apple.developer.applesignin` = `["Default"]`.
- Google's button follows Google's branding guidelines (contracts §11, https://developers.google.com/identity/branding-guidelines): Google's official "G" from Google's own `signin-assets.zip`, Google Sans Medium 14/20, the Light theme's colours, iOS padding 16 / 12 / 16, a 44 pt pill beside Apple's button at the same size (Task 9). Never a Google logo from GPL code (`ios/`, `Packages/`, `Sources/`), never a drawn or traced one. Until the downloaded files are in, the button shows its text only, and `release/mobile/ios.sh` refuses such a build for the App Store.
- Never log an email, token, ID token, authorization code, `sub`, nonce, link token or pairing code (S1 §8). Log lines carry event names and error types only, like `AppCoordinator` today. Link tokens and ID tokens stay in memory.
- Google client IDs are not secrets and may be committed. Nothing else secret is written to the repo or asked for in chat.
- Strings: every visible string is a key of `shellx-ios/ShellX/Localizable.xcstrings` with `en` and `vi` (`"state": "translated"`), `"extractionState": "manual"` and a `comment`, used through `String(localized:)` or `LocalizedStringResource`. No bare literal in `Text`, `Button`, `Label`, `.navigationTitle`, `.alert`. A key whose `vi` equals its `en` goes in `shellx-ios/scripts/strings-identity.txt`. Edit the catalog with a JSON round trip (load, change `catalog["strings"]`, write `json.dumps(catalog, ensure_ascii=False, indent=2) + "\n"`: this reproduces today's file byte for byte), appending new keys. Removing a use of a key removes the key in the same task.
- Builds and simulator tests only through `shellx-ios/scripts/dev.sh` (App Store builds through `release/mobile/ios.sh`); never bare `xcodebuild`; only the "ShellX Dev" simulator. Never quit, relaunch or replace the user's running ShellX or cmux. Only one `dev.sh test app|all|screenshots` runs on this Mac at a time: before starting one, `pgrep -fl xcodebuild` must show no ShellX run from another worktree (wait until it ends).
- Swift 6.0 compatible code (no Swift 6.1+ syntax). New tests are XCTest, like their neighbours.
- `RelayAPI.login(email:password:...)`, `RelayAccountCalling.login` and `AppCoordinator.signIn(email:password:)` stay until Task 15; stored password sessions keep working. No UI calls them after Task 9.
- Landing (contracts §1): branch `feat/shellx-signin-1c-ios` from `develop`; this plan changes app UI/runtime, so after the final review it waits for the USER device check and the user's merge directive (`merge`, `merge it` or `auto-merge`, CLAUDE.md "CI, review and merge"); if none was given, ask with the review summary. Only then merge into `develop` from the main checkout (not inside the worktree) and push `develop`. Never `main`, never a deploy, a store upload or a release.

## Review Focus

1. A 401 for the old token that arrives while "Switch to Google sign-in" or "Delete Account…" runs must not sign the user out or show "session expired": Task 7 `testUnauthorizedDuringSwitchIsIgnoredAndTheNewSessionStays`, `testUnauthorizedDuringDeleteEndsSignedOutNotExpired`.
2. A session stored by the App Store build 1.0.0 (5) has no `auth_method`; it must still open the app, as a password session: Task 4 `testStoredSessionWithoutAuthMethodReadsAsPassword`.
3. Closing Google's or Apple's sheet is not an error: nothing changes, nothing is shown, the next tap works: Task 6 `testGoogleSignInCancelledChangesNothing`, Task 9 `testCancelledHasNoMessage`.
4. Apple link: a wrong QR code, a network drop or another account's Mac keep the user on the scanner; Deny on the Mac, an expired request or an expired link token go back to sign-in with a short message: Task 5 `testRetryableFailuresStayOnTheScanner`, `testDeniedExpiredAndRefusedTokenEndTheLink`.
5. The demo never calls the relay or the Keychain and Exit stops it, while the App Store check still refuses every test fake: Task 12 `testEveryAccountCallIsRefused`, Task 13 `testExitStopsTheDemo`, `testDebugOnlyNamesAreRefused`.

---

### Task 0: Set up the worktree

**Prerequisites:** none. No other plan has to be merged first: every test here stubs the relay (contracts §2, §4). The live checks need relay plan 1A deployed and belong to plan 1D. `pairing.instructions` (Task 10) names the Mac menu item "Pair Phone…" of desktop 1.8.0 (plan 1B); plan 1D publishes that desktop before it submits this iPhone build.

- [ ] **Step 1: Create the worktree.** Invoke `superpowers:using-git-worktrees` and create branch `feat/shellx-signin-1c-ios` from `develop` in a new worktree. Every later path is relative to that worktree's root. If this plan or `docs/superpowers/plans/2026-11-07-shellx-mobile-contracts.md` is missing there (they may be untracked in the main checkout), read them from `/Users/lehuuphu/Documents/myProjects/shellx/docs/superpowers/plans/`; never add them on this branch.
- [ ] **Step 2: Baseline.** Run `swift test --package-path shellx-link` (expected: ends with `Executed N tests, with 0 failures`), `bash scripts/shellx/check-link-license.sh` (expected: exit 0, no output), `shellx-ios/scripts/dev.sh test core` (expected: last line `==> test core: passed`). If one fails, stop and report: the base is broken.

---

### Task 1: Relay sign-in calls in ShellXLinkAccount (contracts §4)

**Files:**
- Create: `shellx-link/Sources/ShellXLinkAccount/RelayAPI+SignIn.swift`
- Modify: `shellx-link/Sources/ShellXLinkAccount/RelayAPI.swift:194` and `:199` (`private static func isSafeSegment` and `private static func base64URL` become `static func`, so the new file can use them)
- Test: `shellx-link/Tests/ShellXLinkAccountTests/RelayAPISignInTests.swift`

**Interfaces:**
- Consumes: `RelayAPI.send(_:_:token:body:)`, `Empty`, `AccountSession`, `PairingOffer.proof(clientKey:)` (all existing).
- Produces (public, module `ShellXLinkAccount`):

```swift
public struct AccountSignIn: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var session: AccountSession
    public var email: String
    public init(session: AccountSession, email: String)
    // description and debugDescription: "AccountSignIn(user: <userID>, device: <deviceID>, <redacted>)";
    // customMirror children: userID, deviceID only (no token, no email).
}
public enum AppleSignInResult: Equatable, Sendable {
    case signedIn(AccountSignIn)
    case linkRequired(linkToken: String, expiresIn: Int)
}
// Contract additions §A: `approved` carries the machine as the status reply gives it.
public enum AppleLinkStatus: Equatable, Sendable {
    case pending, denied, expired
    case approved(AccountSignIn, machineID: String, name: String, linkSlot: String)
}
extension RelayAPI {
    public func nonce() async throws -> String
    public func signInWithGoogle(idToken: String, nonce: String, deviceName: String, clientKey: Data) async throws -> AccountSignIn
    public func linkGoogle(idToken: String, nonce: String, token: String) async throws -> AccountSignIn
    public func signInWithApple(identityToken: String, authorizationCode: String, nonce: String, deviceName: String, clientKey: Data) async throws -> AppleSignInResult
    public func requestAppleLink(linkToken: String, offer: PairingOffer, clientKey: Data) async throws -> String
    public func appleLinkStatus(linkToken: String, pairingID: String) async throws -> AppleLinkStatus
    public func deleteAccount(idToken: String, nonce: String, token: String) async throws
}
```

Rules the code follows (the tests pin each one):
- `nonce`: `POST /v1/auth/nonce`, body `{}`, no bearer; returns `nonce` when it is 1–128 characters of `[A-Za-z0-9_-]`, else `RelayAPIError.badResponse`.
- `signInWithGoogle`: `POST /v1/auth/google`, body `{id_token, nonce, device}`, no bearer. `linkGoogle`: `POST /v1/auth/google/link`, bearer `token`, body `{id_token, nonce}`.
- `signInWithApple`: `POST /v1/auth/apple`, body `{identity_token, authorization_code, nonce, device}`, no bearer. A reply with `status == "link_required"`, a non-empty `link_token` and `expires_in` is `.linkRequired`; a reply with `user_id`, `device_id`, `token`, `email` is `.signedIn`; anything else is `badResponse`.
- `requestAppleLink`: `POST /v1/auth/apple/link`, body `{link_token, machine_id: offer.machineID, client_key_b64, proof_b64}` (standard base64, as `requestPairing`), no bearer; the `pairing_id` must pass `isSafeSegment`, else `badResponse`.
- `appleLinkStatus`: `POST /v1/auth/apple/link/status`, body `{link_token, pairing_id}`, no bearer; `approved` needs both `session` and `machine`, an unknown status is `badResponse`.
- `deleteAccount`: `DELETE /v1/account`, bearer `token`, body `{id_token, nonce}`; any 2xx returns.
- A session reply needs all of `user_id`, `device_id`, `token`, `email`.

- [ ] **Step 1: Write the failing tests** in `RelayAPISignInTests.swift` (same stubs as `RelayAPITests`):

```swift
import Foundation
import ShellXLinkCore
import XCTest
@testable import ShellXLinkAccount

final class RelayAPISignInTests: XCTestCase {
    private let clientKey = Data((0..<32).map { UInt8(0x20 + $0) })
    private static let reply: [String: String] = ["user_id": "u1", "device_id": "d1", "token": "tok-secret", "email": "g@example.com"]
    private let signIn = AccountSignIn(session: AccountSession(userID: "u1", deviceID: "d1", token: "tok-secret"), email: "g@example.com")
    private func api() throws -> RelayAPI {
        try RelayAPI(baseURL: URL(string: "https://api.example.test")!, session: StubURLProtocol.session(), clientVersion: "9.9.9")
    }

    func testNoncePostsAnEmptyObjectWithoutToken() async throws {
        let nonce = String(repeating: "aB3_-", count: 8) + "xyz"   // 43 base64url characters
        StubURLProtocol.install { _ in StubResponse(201, ["nonce": nonce, "expires_in": 600]) }
        let got = try await api().nonce()
        XCTAssertEqual(got, nonce)
        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "/v1/auth/nonce")
        XCTAssertNil(request.headers["Authorization"])
        XCTAssertEqual(request.json?.count, 0)
    }

    func testNonceOutsideBase64URLIsRefused() async throws {
        for bad in ["", "has space", "slash/es", String(repeating: "a", count: 129)] {
            StubURLProtocol.install { _ in StubResponse(201, ["nonce": bad, "expires_in": 600]) }
            do { _ = try await api().nonce(); XCTFail("accepted \(bad)") } catch {
                XCTAssertEqual(error as? RelayAPIError, .badResponse)
            }
        }
    }

    func testGoogleSignInSendsTokenNonceAndMobileDevice() async throws {
        StubURLProtocol.install { _ in StubResponse(200, Self.reply) }
        let got = try await api().signInWithGoogle(idToken: "id-secret", nonce: "n-1", deviceName: "Phu's iPhone", clientKey: clientKey)
        XCTAssertEqual(got, signIn)
        XCTAssertFalse("\(got)".contains("tok-secret"))
        XCTAssertFalse(String(reflecting: got).contains("g@example.com"))
        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.path, "/v1/auth/google")
        XCTAssertNil(request.headers["Authorization"])
        let body = try XCTUnwrap(request.json)
        XCTAssertEqual(body["id_token"] as? String, "id-secret")
        XCTAssertEqual(body["nonce"] as? String, "n-1")
        let device = try XCTUnwrap(body["device"] as? [String: Any])
        XCTAssertEqual(device["kind"] as? String, "mobile")
        XCTAssertEqual(device["platform"] as? String, "ios")
        XCTAssertEqual(device["name"] as? String, "Phu's iPhone")
        XCTAssertEqual(device["public_key"] as? String, "ICEiIyQlJicoKSorLC0uLzAxMjM0NTY3ODk6Ozw9Pj8")
    }

    func testGoogleSignInKeepsTheRelayErrorCode() async throws {
        for (status, code) in [(409, "switch_from_signed_in_device"), (401, "invalid_credentials")] {
            StubURLProtocol.install { _ in StubResponse(status, ["error": ["code": code, "message": "x"]]) }
            do { _ = try await api().signInWithGoogle(idToken: "i", nonce: "n", deviceName: "p", clientKey: clientKey); XCTFail() } catch {
                XCTAssertEqual(error as? RelayAPIError, .http(status: status, code: code))
            }
        }
    }

    func testLinkGoogleSendsTheBearerAndNoDevice() async throws {
        StubURLProtocol.install { _ in StubResponse(200, Self.reply) }
        let got = try await api().linkGoogle(idToken: "id-secret", nonce: "n-1", token: "tok-old")
        XCTAssertEqual(got, signIn)
        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.path, "/v1/auth/google/link")
        XCTAssertEqual(request.headers["Authorization"], "Bearer tok-old")
        XCTAssertEqual(Set(try XCTUnwrap(request.json).keys), ["id_token", "nonce"])
    }

    func testAppleSignInSignedInOrLinkRequired() async throws {
        StubURLProtocol.install { _ in StubResponse(200, Self.reply) }
        let signedIn = try await api().signInWithApple(
            identityToken: "apple-secret", authorizationCode: "code-secret", nonce: "n-1", deviceName: "p", clientKey: clientKey)
        XCTAssertEqual(signedIn, .signedIn(signIn))
        let body = try XCTUnwrap(StubURLProtocol.requests.first?.json)
        XCTAssertEqual(body["identity_token"] as? String, "apple-secret")
        XCTAssertEqual(body["authorization_code"] as? String, "code-secret")
        XCTAssertEqual(body["nonce"] as? String, "n-1")
        XCTAssertEqual((body["device"] as? [String: Any])?["platform"] as? String, "ios")
        XCTAssertEqual(StubURLProtocol.requests.first?.path, "/v1/auth/apple")

        StubURLProtocol.install { _ in StubResponse(202, ["status": "link_required", "link_token": "link-secret", "expires_in": 600]) }
        let link = try await api().signInWithApple(
            identityToken: "a", authorizationCode: "c", nonce: "n", deviceName: "p", clientKey: clientKey)
        XCTAssertEqual(link, .linkRequired(linkToken: "link-secret", expiresIn: 600))
    }

    func testAppleSignInWithAnOddReplyIsABadResponse() async throws {
        for reply: [String: Any] in [["status": "weird"], ["status": "link_required", "expires_in": 600]] {
            let response = StubResponse(202, reply)   // StubResponse is Sendable; the dictionary is not
            StubURLProtocol.install { _ in response }
            do { _ = try await api().signInWithApple(identityToken: "a", authorizationCode: "c", nonce: "n", deviceName: "p", clientKey: clientKey); XCTFail() } catch {
                XCTAssertEqual(error as? RelayAPIError, .badResponse)
            }
        }
    }

    func testRequestAppleLinkSendsTheProofWithoutToken() async throws {
        let offer = PairingOffer.make(
            machineID: "6f1c2b7e-0d4a-4c1e-9a53-3b8e5d2f7a10", linkSlot: "slot-1",
            hostKey: Data((0..<32).map { UInt8(0x40 + $0) }), machineName: "Mac")
        StubURLProtocol.install { _ in StubResponse(201, ["pairing_id": "p-1"]) }
        let id = try await api().requestAppleLink(linkToken: "link-secret", offer: offer, clientKey: clientKey)
        XCTAssertEqual(id, "p-1")
        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.path, "/v1/auth/apple/link")
        XCTAssertNil(request.headers["Authorization"])
        let body = try XCTUnwrap(request.json)
        XCTAssertEqual(body["link_token"] as? String, "link-secret")
        XCTAssertEqual(body["machine_id"] as? String, offer.machineID)
        XCTAssertEqual(body["client_key_b64"] as? String, clientKey.base64EncodedString())
        XCTAssertEqual(body["proof_b64"] as? String, offer.proof(clientKey: clientKey).base64EncodedString())

        StubURLProtocol.install { _ in StubResponse(201, ["pairing_id": "../x"]) }
        do { _ = try await api().requestAppleLink(linkToken: "l", offer: offer, clientKey: clientKey); XCTFail() } catch {
            XCTAssertEqual(error as? RelayAPIError, .badResponse)
        }
    }

    func testAppleLinkStatusReadsEveryState() async throws {
        for (status, expected) in [("pending", AppleLinkStatus.pending), ("denied", .denied), ("expired", .expired)] {
            StubURLProtocol.install { _ in StubResponse(200, ["status": status]) }
            let got = try await api().appleLinkStatus(linkToken: "link-secret", pairingID: "p-1")
            XCTAssertEqual(got, expected)
        }
        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.path, "/v1/auth/apple/link/status")
        XCTAssertEqual(request.json?["link_token"] as? String, "link-secret")
        XCTAssertEqual(request.json?["pairing_id"] as? String, "p-1")

        StubURLProtocol.install { _ in
            StubResponse(200, ["status": "approved", "session": Self.reply, "machine": ["machine_id": "m1", "name": "Mac", "link_slot": "slot-1"]])
        }
        let approved = try await api().appleLinkStatus(linkToken: "l", pairingID: "p-1")
        XCTAssertEqual(approved, .approved(signIn, machineID: "m1", name: "Mac", linkSlot: "slot-1"))

        for reply: [String: Any] in [["status": "approved", "machine": ["machine_id": "m1", "name": "Mac", "link_slot": "s"]], ["status": "later"]] {
            let response = StubResponse(200, reply)
            StubURLProtocol.install { _ in response }
            do { _ = try await api().appleLinkStatus(linkToken: "l", pairingID: "p-1"); XCTFail() } catch {
                XCTAssertEqual(error as? RelayAPIError, .badResponse)
            }
        }
    }

    func testDeleteAccountSendsAFreshTokenWithTheBearer() async throws {
        StubURLProtocol.install { _ in StubResponse(204) }
        try await api().deleteAccount(idToken: "fresh-id", nonce: "n-2", token: "tok")
        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.method, "DELETE")
        XCTAssertEqual(request.path, "/v1/account")
        XCTAssertEqual(request.headers["Authorization"], "Bearer tok")
        XCTAssertEqual(request.json?["id_token"] as? String, "fresh-id")
        XCTAssertEqual(request.json?["nonce"] as? String, "n-2")

        StubURLProtocol.install { _ in StubResponse(401, ["error": ["code": "reauth_required", "message": "x"]]) }
        do { try await api().deleteAccount(idToken: "old", nonce: "n", token: "tok"); XCTFail() } catch {
            XCTAssertEqual(error as? RelayAPIError, .http(status: 401, code: "reauth_required"))
        }
    }
}
```

- [ ] **Step 2: Run them to see them fail.** Run: `swift test --package-path shellx-link --filter RelayAPISignInTests`. Expected: build error `value of type 'RelayAPI' has no member 'nonce'`.
- [ ] **Step 3: Implement** the types and the extension in `RelayAPI+SignIn.swift` with the rules above; wire types are private `Decodable` structs with `CodingKeys` like `LoginReply` (`RelayAPI.swift:226-235`). Make the two helpers in `RelayAPI.swift` internal.
- [ ] **Step 4: Run them to see them pass.** Run: `swift test --package-path shellx-link --filter RelayAPISignInTests`, then `swift test --package-path shellx-link` and `bash scripts/shellx/check-link-license.sh`. Expected: `with 0 failures` both times; the licence check exits 0.
- [ ] **Step 5: Commit.**

```bash
git add shellx-link/Sources/ShellXLinkAccount/RelayAPI+SignIn.swift shellx-link/Sources/ShellXLinkAccount/RelayAPI.swift shellx-link/Tests/ShellXLinkAccountTests/RelayAPISignInTests.swift
git commit -m "feat(shellx-link): relay calls for Google and Apple sign-in, Apple link and account deletion"
```

---

### Task 2: Apple link pairing loop in ShellXLinkAccount

**Files:**
- Create: `shellx-link/Sources/ShellXLinkAccount/AppleLinkPairing.swift`
- Modify: `shellx-link/Tests/ShellXLinkAccountTests/PhonePairingTests.swift:248-257` (delete the private `PollCounter`) and `shellx-link/Tests/ShellXLinkAccountTests/StubURLProtocol.swift` (add the same class, internal: `final class PollCounter: @unchecked Sendable { func next() -> Int }`)
- Test: `shellx-link/Tests/ShellXLinkAccountTests/AppleLinkPairingTests.swift`

**Interfaces:**
- Consumes: Task 1 `requestAppleLink(linkToken:offer:clientKey:)`, `appleLinkStatus(linkToken:pairingID:)`, `AccountSignIn`; existing `PairingOffer`, `PairedMachine`, `PhonePairingError`.
- Produces:

```swift
public struct AppleLinkApproval: Equatable, Sendable {
    public var signIn: AccountSignIn
    /// From the scanned offer: the host key is the QR code's, never the relay's.
    public var machine: PairedMachine
    public init(signIn: AccountSignIn, machine: PairedMachine)
}
public enum AppleLinkPairing {
    public static func link(
        offerURI: String, linkToken: String, clientKey: Data, api: RelayAPI,
        pollInterval: Duration = .seconds(2), timeout: Duration = .seconds(PairingOffer.lifetime),
        onRequested: @Sendable (String) -> Void = { _ in }
    ) async throws -> AppleLinkApproval
}
```

Rules (mirror `PhonePairing.pair`, `shellx-link/Sources/ShellXLinkAccount/PhonePairing.swift:35-88`): parse the offer first (its `PairingOfferError` is thrown before any request); `requestAppleLink`; `onRequested(id)`; poll `appleLinkStatus` every `pollInterval`. `approved` must name the offer's `machineID` and `linkSlot` (else `RelayAPIError.badResponse`) and returns the machine built from the offer (`machineID`, `machineName`, `linkSlot`, `hostKey`); `denied` throws `PhonePairingError.denied`; `expired` and the deadline throw `PhonePairingError.expired`; a `URLError` other than `.cancelled` and an HTTP status ≥ 500 keep polling; every other error (the relay's 401 for an expired link token, 404) is thrown at once. Nothing is sent to withdraw the request: contracts §2 has no route for it (Spec notes).

- [ ] **Step 1: Write the failing tests.**

```swift
import Foundation
import ShellXLinkCore
import XCTest
@testable import ShellXLinkAccount

final class AppleLinkPairingTests: XCTestCase {
    private let clientKey = Data((0..<32).map { UInt8(0x20 + $0) })
    private let hostKey = Data((0..<32).map { UInt8(0x40 + $0) })
    private let machineID = "6f1c2b7e-0d4a-4c1e-9a53-3b8e5d2f7a10"
    private func api() throws -> RelayAPI {
        try RelayAPI(baseURL: URL(string: "https://api.example.test")!, session: StubURLProtocol.session(), clientVersion: "1")
    }
    private func offer() -> PairingOffer { PairingOffer.make(machineID: machineID, linkSlot: "slot-1", hostKey: hostKey, machineName: "Mac") }
    /// The link request answers p-1; the status answers `pending` twice, then `final`.
    private func install(final: @escaping @Sendable () -> StubResponse) {
        let polls = PollCounter()
        StubURLProtocol.install { request in
            if request.path == "/v1/auth/apple/link" { return StubResponse(201, ["pairing_id": "p-1"]) }
            return polls.next() < 2 ? StubResponse(200, ["status": "pending"]) : final()
        }
    }
    private func approved(machineID: String? = nil, slot: String = "slot-1") -> StubResponse {
        StubResponse(200, [
            "status": "approved",
            "session": ["user_id": "u1", "device_id": "d1", "token": "tok-secret", "email": "owner@example.com"],
            "machine": ["machine_id": machineID ?? self.machineID, "name": "Relay Name", "link_slot": slot],
        ])
    }
    private func link(timeout: Duration = .seconds(5)) async throws -> AppleLinkApproval {
        try await AppleLinkPairing.link(
            offerURI: offer().uri, linkToken: "link-secret", clientKey: clientKey, api: api(),
            pollInterval: .milliseconds(5), timeout: timeout)
    }

    func testLinkPollsUntilApprovedAndKeepsTheOffersHostKey() async throws {
        let response = approved()
        install { response }
        let approval = try await link()
        XCTAssertEqual(approval.signIn, AccountSignIn(session: AccountSession(userID: "u1", deviceID: "d1", token: "tok-secret"), email: "owner@example.com"))
        XCTAssertEqual(approval.machine, PairedMachine(machineID: machineID, name: "Mac", linkSlot: "slot-1", hostKey: hostKey))
        let polls = StubURLProtocol.requests.filter { $0.path == "/v1/auth/apple/link/status" }
        XCTAssertEqual(polls.count, 3)
        XCTAssertEqual(polls.first?.json?["link_token"] as? String, "link-secret")
        XCTAssertEqual(polls.first?.json?["pairing_id"] as? String, "p-1")
        XCTAssertTrue(StubURLProtocol.requests.allSatisfy { $0.headers["Authorization"] == nil })
    }

    func testDeniedAndExpiredThrow() async throws {
        for (status, expected) in [("denied", PhonePairingError.denied), ("expired", .expired)] {
            install { StubResponse(200, ["status": status]) }
            do { _ = try await link(); XCTFail(status) } catch { XCTAssertEqual(error as? PhonePairingError, expected) }
        }
    }

    func testApprovalForAnotherMacOrSlotIsRefused() async throws {
        for response in [approved(machineID: "other"), approved(slot: "slot-2")] {
            install { response }
            do { _ = try await link(); XCTFail() } catch { XCTAssertEqual(error as? RelayAPIError, .badResponse) }
        }
    }

    func testRefusedLinkTokenStopsAtOnce() async throws {
        StubURLProtocol.install { request in
            request.path == "/v1/auth/apple/link" ? StubResponse(201, ["pairing_id": "p-1"])
                : StubResponse(401, ["error": ["code": "invalid_credentials", "message": "x"]])
        }
        do { _ = try await link(); XCTFail() } catch {
            XCTAssertEqual(error as? RelayAPIError, .http(status: 401, code: "invalid_credentials"))
        }
        XCTAssertEqual(StubURLProtocol.requests.filter { $0.path == "/v1/auth/apple/link/status" }.count, 1)
    }

    func testTransientErrorsKeepPolling() async throws {
        let response = approved()
        let polls = PollCounter()
        StubURLProtocol.install { request in
            if request.path == "/v1/auth/apple/link" { return StubResponse(201, ["pairing_id": "p-1"]) }
            return polls.next() == 0 ? StubResponse(503) : response
        }
        let approval = try await link()
        XCTAssertEqual(approval.machine.machineID, machineID)
    }

    func testDeadlineExpires() async throws {
        install { StubResponse(200, ["status": "pending"]) }
        do { _ = try await link(timeout: .milliseconds(30)); XCTFail() } catch { XCTAssertEqual(error as? PhonePairingError, .expired) }
    }

    func testBadOfferNeverReachesTheRelay() async throws {
        StubURLProtocol.install { _ in StubResponse(500) }
        do {
            _ = try await AppleLinkPairing.link(offerURI: "shellx-link://pair?v=1", linkToken: "l", clientKey: clientKey, api: api())
            XCTFail()
        } catch { XCTAssertTrue(error is PairingOfferError, "\(error)") }
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
    }
}
```

- [ ] **Step 2: Run them to see them fail.** Run: `swift test --package-path shellx-link --filter AppleLinkPairingTests`. Expected: build error `cannot find 'AppleLinkPairing' in scope`.
- [ ] **Step 3: Implement** `AppleLinkApproval` and `AppleLinkPairing.link` with the rules above, and move `PollCounter` into `StubURLProtocol.swift`.
- [ ] **Step 4: Run them to see them pass.** Run: `swift test --package-path shellx-link`. Expected: `with 0 failures` (the `PhonePairingTests` use the moved counter).
- [ ] **Step 5: Commit.**

```bash
git add shellx-link/Sources/ShellXLinkAccount/AppleLinkPairing.swift shellx-link/Tests/ShellXLinkAccountTests/AppleLinkPairingTests.swift shellx-link/Tests/ShellXLinkAccountTests/PhonePairingTests.swift shellx-link/Tests/ShellXLinkAccountTests/StubURLProtocol.swift
git commit -m "feat(shellx-link): Apple link pairing waits for Allow on the Mac with the link token"
```

---

### Task 3: PKCE Google OAuth and the identity provider seam (ShellXAppCore)

All paths below start at `shellx-ios/Packages/ShellXAppCore/`.

**Files:**
- Create: `Sources/ShellXAppCore/Account/AuthCrypto.swift`, `Sources/ShellXAppCore/Account/IdentityProviding.swift`, `Sources/ShellXAppCore/Account/GoogleOAuth.swift`
- Test: `Tests/ShellXAppCoreTests/AuthCryptoTests.swift`, `Tests/ShellXAppCoreTests/GoogleOAuthTests.swift`

**Interfaces:**
- Produces (public, module `ShellXAppCore`):

```swift
public enum AuthCrypto {
    public static func base64URL(_ data: Data) -> String               // `-_` alphabet, no padding
    public static func randomToken(byteCount: Int = 32) -> String       // base64URL of `byteCount` secure random bytes
    public static func pkceChallenge(verifier: String) -> String        // base64URL(SHA-256(UTF-8 verifier)), CryptoKit
    public static func sha256Hex(_ text: String) -> String              // lowercase hex of SHA-256(UTF-8 text)
}

public struct AppleCredential: Equatable, Sendable {
    public var identityToken: String
    public var authorizationCode: String
    public init(identityToken: String, authorizationCode: String)
}
public enum IdentityProviderError: Error, Equatable, Sendable {
    /// The user closed Google's or Apple's sheet.
    case cancelled
    /// This build has no usable Google client ID.
    case notConfigured
    /// Google or Apple did not finish: a bad redirect, another state, a refused code, a missing token.
    case failed
}
/// The phone's identity providers. The app implements it with AuthenticationServices; tests use a fake.
@MainActor public protocol IdentityProviding {
    /// Google's ID token for a sign-in carrying `nonce` (the relay's, raw).
    func googleIDToken(nonce: String) async throws -> String
    /// Sign in with Apple, `requestedScopes = [.email]`, with `requestNonce` = `AuthCrypto.sha256Hex(relay nonce)`.
    func appleCredential(requestNonce: String) async throws -> AppleCredential
}
/// Every call throws `IdentityProviderError.notConfigured` (the demo, tests that sign in no other way).
public struct UnavailableIdentityProvider: IdentityProviding { public init() }

@MainActor public protocol WebAuthenticating {
    /// Shows `url` in the system's web sign-in sheet; returns the URL the page sent back to `callbackScheme`.
    /// Throws `IdentityProviderError.cancelled` when the user closes the sheet.
    func authenticate(url: URL, callbackScheme: String) async throws -> URL
}
public struct GoogleOAuthClient: Equatable, Sendable {
    public static let authorizationEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    public static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!
    public let clientID: String
    /// Nil unless `clientID` matches `^[0-9]+-[a-z0-9]+\.apps\.googleusercontent\.com$` (the build placeholder does not).
    public init?(clientID: String)
    public var callbackScheme: String   // "com.googleusercontent.apps.<prefix>"
    public var redirectURI: String      // callbackScheme + ":/oauth2redirect"
    public func authorizationURL(nonce: String, state: String, codeChallenge: String) -> URL
    /// Throws IdentityProviderError: `error=access_denied` → .cancelled; another `error`, another scheme, another `state`, no `code` → .failed.
    public func code(fromCallback url: URL, state: String) throws -> String
    /// POST, `application/x-www-form-urlencoded`, timeout 15 s; fields client_id, code, code_verifier,
    /// grant_type=authorization_code, redirect_uri; values keep only `A-Z a-z 0-9 - . _ ~` unescaped. No client_secret.
    public func tokenRequest(code: String, codeVerifier: String) -> URLRequest
    /// The `id_token` of a status-200 JSON reply; anything else throws IdentityProviderError.failed.
    public static func idToken(fromTokenResponse data: Data, status: Int) throws -> String
}
@MainActor public struct GoogleSignIn {
    public typealias Exchange = @Sendable (URLRequest) async throws -> (Data, Int)
    /// `exchange` nil: `URLSession.shared.data(for:)`, with the HTTP status (0 when there is none).
    public init(client: GoogleOAuthClient, web: any WebAuthenticating, exchange: Exchange? = nil)
    /// verifier = randomToken(32), state = randomToken(16); opens authorizationURL; reads the code; exchanges it.
    public func idToken(nonce: String) async throws -> String
}
```

- [ ] **Step 1: Write the failing tests.**

```swift
// AuthCryptoTests.swift
import XCTest
@testable import ShellXAppCore

final class AuthCryptoTests: XCTestCase {
    func testPKCEChallengeMatchesRFC7636AppendixB() {
        XCTAssertEqual(
            AuthCrypto.pkceChallenge(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
            "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }
    func testSHA256HexIsLowercaseHex() {
        XCTAssertEqual(AuthCrypto.sha256Hex("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
    func testBase64URLUsesTheURLAlphabetWithoutPadding() {
        XCTAssertEqual(AuthCrypto.base64URL(Data([0xFB, 0xFF, 0xBF])), "-_-_")
        XCTAssertEqual(AuthCrypto.base64URL(Data([0x61])), "YQ")
    }
    func testRandomTokensAre43URLSafeCharactersAndDiffer() {
        let a = AuthCrypto.randomToken(), b = AuthCrypto.randomToken()
        XCTAssertEqual(a.count, 43)
        XCTAssertNotEqual(a, b)
        XCTAssertTrue(a.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") })
    }
}
```

```swift
// GoogleOAuthTests.swift
import Foundation
import XCTest
@testable import ShellXAppCore

@MainActor
final class GoogleOAuthTests: XCTestCase {
    private let id = "123456789012-abcdef123.apps.googleusercontent.com"
    private var client: GoogleOAuthClient { GoogleOAuthClient(clientID: id)! }
    private func query(_ url: URL) -> [String: String] {
        Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    }
    private func form(_ request: URLRequest) -> [String: String] {
        var parts = URLComponents()
        parts.percentEncodedQuery = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
        return Dictionary(uniqueKeysWithValues: (parts.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    }

    func testOnlyGoogleIOSClientIDsAreAccepted() {
        XCTAssertEqual(client.callbackScheme, "com.googleusercontent.apps.123456789012-abcdef123")
        XCTAssertEqual(client.redirectURI, "com.googleusercontent.apps.123456789012-abcdef123:/oauth2redirect")
        for bad in ["", "0-shellx-placeholder.apps.googleusercontent.com", "abc.apps.googleusercontent.com",
                    "123-abc.example.com", "123-ABC.apps.googleusercontent.com"] {
            XCTAssertNil(GoogleOAuthClient(clientID: bad), bad)
        }
    }

    func testAuthorizationURLCarriesPKCEStateAndNonce() throws {
        let url = client.authorizationURL(nonce: "n-1", state: "s-1", codeChallenge: "c-1")
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "accounts.google.com")
        XCTAssertEqual(url.path, "/o/oauth2/v2/auth")
        XCTAssertEqual(query(url), [
            "client_id": id, "redirect_uri": client.redirectURI, "response_type": "code", "scope": "openid email",
            "code_challenge": "c-1", "code_challenge_method": "S256", "state": "s-1", "nonce": "n-1",
            "prompt": "select_account",
        ])
    }

    func testCallbackGivesTheCodeOfThisState() throws {
        let url = URL(string: "com.googleusercontent.apps.123456789012-abcdef123:/oauth2redirect?state=s-1&code=4/0Abc-_x")!
        XCTAssertEqual(try client.code(fromCallback: url, state: "s-1"), "4/0Abc-_x")
    }

    func testCallbackFailures() {
        let base = "com.googleusercontent.apps.123456789012-abcdef123:/oauth2redirect"
        let cases: [(String, IdentityProviderError)] = [
            ("\(base)?error=access_denied&state=s-1", .cancelled),
            ("\(base)?error=server_error&state=s-1", .failed),
            ("\(base)?state=other&code=c", .failed),
            ("\(base)?state=s-1", .failed),
            ("com.example.other:/oauth2redirect?state=s-1&code=c", .failed),
        ]
        for (text, expected) in cases {
            XCTAssertThrowsError(try client.code(fromCallback: URL(string: text)!, state: "s-1"), text) {
                XCTAssertEqual($0 as? IdentityProviderError, expected, text)
            }
        }
    }

    func testTokenRequestIsAFormPostWithoutSecret() {
        let request = client.tokenRequest(code: "4/0Abc", codeVerifier: "v-1")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url, GoogleOAuthClient.tokenEndpoint)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
        let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
        XCTAssertTrue(body.contains("code=4%2F0Abc"), body)
        XCTAssertFalse(body.contains("client_secret"))
        XCTAssertEqual(form(request), [
            "client_id": id, "code": "4/0Abc", "code_verifier": "v-1", "grant_type": "authorization_code",
            "redirect_uri": client.redirectURI,
        ])
    }

    func testIDTokenComesOnlyFromASuccessfulTokenResponse() throws {
        XCTAssertEqual(
            try GoogleOAuthClient.idToken(fromTokenResponse: Data(#"{"id_token":"eyJ.a.b","access_token":"x"}"#.utf8), status: 200),
            "eyJ.a.b")
        for (json, status) in [(#"{"error":"invalid_grant"}"#, 400), (#"{"access_token":"x"}"#, 200), ("not json", 200)] {
            XCTAssertThrowsError(try GoogleOAuthClient.idToken(fromTokenResponse: Data(json.utf8), status: status)) {
                XCTAssertEqual($0 as? IdentityProviderError, .failed)
            }
        }
    }

    func testSignInOpensTheSheetThenExchangesTheCodeWithTheVerifier() async throws {
        let web = FakeWebAuthenticator()
        let sent = RequestBox()
        let flow = GoogleSignIn(client: client, web: web, exchange: { request in
            sent.set(request)
            return (Data(#"{"id_token":"google-id"}"#.utf8), 200)
        })
        let token = try await flow.idToken(nonce: "relay-nonce")
        XCTAssertEqual(token, "google-id")
        let opened = try XCTUnwrap(web.opened.first)
        XCTAssertEqual(opened.callbackScheme, client.callbackScheme)
        let asked = query(opened.url)
        XCTAssertEqual(asked["nonce"], "relay-nonce")
        let exchanged = form(try XCTUnwrap(sent.request))
        XCTAssertEqual(exchanged["code"], "code-1")
        XCTAssertEqual(AuthCrypto.pkceChallenge(verifier: try XCTUnwrap(exchanged["code_verifier"])), asked["code_challenge"])
    }

    func testCancelledSheetStopsBeforeTheExchange() async {
        let web = FakeWebAuthenticator()
        web.error = IdentityProviderError.cancelled
        let sent = RequestBox()
        let flow = GoogleSignIn(client: client, web: web, exchange: { sent.set($0); return (Data(), 200) })
        do { _ = try await flow.idToken(nonce: "n"); XCTFail() } catch {
            XCTAssertEqual(error as? IdentityProviderError, .cancelled)
        }
        XCTAssertNil(sent.request)
    }
}

/// Answers like Google: back to the callback scheme with the request's `state` and code "code-1".
@MainActor
private final class FakeWebAuthenticator: WebAuthenticating {
    var opened: [(url: URL, callbackScheme: String)] = []
    var error: (any Error)?
    func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        opened.append((url, callbackScheme))
        if let error { throw error }
        let state = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "state" }?.value ?? ""
        return URL(string: "\(callbackScheme):/oauth2redirect?state=\(state)&code=code-1")!
    }
}

private final class RequestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: URLRequest?
    var request: URLRequest? { lock.withLock { stored } }
    func set(_ request: URLRequest) { lock.withLock { stored = request } }
}
```

- [ ] **Step 2: Run them to see them fail.** Run: `swift test --package-path shellx-ios/Packages/ShellXAppCore --filter 'AuthCryptoTests|GoogleOAuthTests'`. Expected: build error `cannot find 'AuthCrypto' in scope`.
- [ ] **Step 3: Implement** the three files to the interfaces above (`import CryptoKit` for SHA-256; secure random bytes from `SystemRandomNumberGenerator`).
- [ ] **Step 4: Run them to see them pass.** Same command, then `shellx-ios/scripts/dev.sh test core`. Expected: `with 0 failures`; `==> test core: passed`.
- [ ] **Step 5: Commit.**

```bash
git add shellx-ios/Packages/ShellXAppCore/Sources/ShellXAppCore/Account/AuthCrypto.swift shellx-ios/Packages/ShellXAppCore/Sources/ShellXAppCore/Account/IdentityProviding.swift shellx-ios/Packages/ShellXAppCore/Sources/ShellXAppCore/Account/GoogleOAuth.swift shellx-ios/Packages/ShellXAppCore/Tests/ShellXAppCoreTests/AuthCryptoTests.swift shellx-ios/Packages/ShellXAppCore/Tests/ShellXAppCoreTests/GoogleOAuthTests.swift
git commit -m "feat(shellx-ios): Google OAuth with PKCE and the identity provider seam"
```

---

### Task 4: Sessions remember how they signed in; relay calls and errors for the providers

Paths start at `shellx-ios/Packages/ShellXAppCore/`.

**Files:**
- Modify: `Sources/ShellXAppCore/Account/StoredSession.swift`, `Sources/ShellXAppCore/Account/SignInError.swift`, `Sources/ShellXAppCore/Account/RelayAccountCalling.swift`, `Sources/ShellXAppCore/Account/RelayAPI+RelayAccountCalling.swift`, `Sources/ShellXAppTestSupport/FakeRelayAccount.swift`
- Create: `Sources/ShellXAppTestSupport/FakeIdentityProvider.swift`
- Test: Modify `Tests/ShellXAppCoreTests/AccountVaultTests.swift`; Create `Tests/ShellXAppCoreTests/SignInErrorTests.swift`

**Interfaces:**
- Consumes: Tasks 1–3 (`AccountSignIn`, `AppleSignInResult`, `AppleLinkApproval`, `AppleLinkPairing.link`, `IdentityProviding`, `AppleCredential`, `IdentityProviderError`).
- Produces:

```swift
public enum AccountAuthMethod: String, Codable, Sendable { case password, google, apple }   // mirrors tokens.auth_method
// StoredSession gains:
public var authMethod: AccountAuthMethod
public init(userID: String, deviceID: String, token: String, email: String, authMethod: AccountAuthMethod = .password)
// CodingKeys: userID, deviceID, token, email, authMethod = "auth_method". A missing key decodes as .password; an
// unknown value fails decoding, so AccountVault.session() returns nil as for any unreadable session.

// SignInError gains (existing cases stay):
case cancelled, switchFromSignedInDevice, emailInUse, identityInUse, reauthRequired, providerUnavailable, providerFailed, switchToGoogleFirst

// RelayAccountCalling gains (RelayAPI conforms with Task 1's methods; linkApple calls AppleLinkPairing.link(..., api: self)):
func nonce() async throws -> String
func signInWithGoogle(idToken: String, nonce: String, deviceName: String, clientKey: Data) async throws -> AccountSignIn
func linkGoogle(idToken: String, nonce: String, token: String) async throws -> AccountSignIn
func signInWithApple(identityToken: String, authorizationCode: String, nonce: String, deviceName: String, clientKey: Data) async throws -> AppleSignInResult
func linkApple(offerURI: String, linkToken: String, clientKey: Data) async throws -> AppleLinkApproval
func deleteAccount(idToken: String, nonce: String, token: String) async throws

// FakeRelayAccount gains Call cases .nonce, .signInWithGoogle(idToken:nonce:deviceName:clientKey:),
// .linkGoogle(idToken:nonce:token:), .signInWithApple(identityToken:authorizationCode:nonce:deviceName:clientKey:),
// .linkApple(offerURI:linkToken:clientKey:), .deleteAccount(idToken:nonce:token:); the same names in `Function`;
// presets (defaults in brackets):
public func setNonce(_ nonce: String)                                     // ["nonce-1"]
public func setGoogleSignIn(_ result: Result<AccountSignIn, Error>)       // [user/device/"token", "user@example.com"]
public func setLinkGoogle(_ result: Result<AccountSignIn, Error>)         // [user/device/"google-token", "user@example.com"]
public func setAppleSignIn(_ result: Result<AppleSignInResult, Error>)    // [.signedIn(user/device/"token", "user@example.com")]
public func setAppleLinkSignIn(_ signIn: AccountSignIn)                   // [user/device/"apple-token", "user@example.com"]
/// Runs inside `function`'s call, after it is recorded and before it answers (a 401 racing a request).
public func setHook(_ hook: (@Sendable () async -> Void)?, for function: Function)
// linkApple works like pair: parses the offer (its error is thrown), waits approvalDelay, adds the Mac's grant and returns
// AppleLinkApproval(signIn: <appleLinkSignIn>, machine: <PairedMachine from the offer>). setError(_:for:) works for every new function.

/// An IdentityProviding answering from presets and recording what it was asked.
@MainActor public final class FakeIdentityProvider: IdentityProviding {
    public var googleResult: Result<String, Error> = .success("google-id-token")
    public var appleResult: Result<AppleCredential, Error> = .success(AppleCredential(identityToken: "apple-id-token", authorizationCode: "apple-code"))
    public private(set) var googleNonces: [String] = []
    public private(set) var appleRequestNonces: [String] = []
    public init()
}
```

`SignInError.init(_:)` maps, first match wins:

| Thrown | `SignInError` |
| --- | --- |
| `RelayAPIError.http(401, "invalid_credentials")` | `.invalidCredentials` |
| `RelayAPIError.http(401, "reauth_required")` | `.reauthRequired` |
| `RelayAPIError.http(409, "switch_from_signed_in_device")` | `.switchFromSignedInDevice` |
| `RelayAPIError.http(409, "email_in_use")` | `.emailInUse` |
| `RelayAPIError.http(409, "identity_in_use")` | `.identityInUse` |
| `RelayAPIError.http(429, _)` | `.rateLimited` |
| `RelayAPIError.http(_, code)` | `.server(code: code)` |
| `RelayAPIError.badResponse` | `.server(code: "bad_response")` |
| `URLError` | `.network` |
| `IdentityProviderError.cancelled` / `.notConfigured` / `.failed` | `.cancelled` / `.providerUnavailable` / `.providerFailed` |
| anything else | `.server(code: "unknown")` |

- [ ] **Step 1: Write the failing tests.** Add to `AccountVaultTests`:

```swift
func testStoredSessionWithoutAuthMethodReadsAsPassword() async throws {
    let store = InMemorySecretStore()
    try store.write(Data(#"{"userID":"u1","deviceID":"d1","token":"t","email":"a@b.c"}"#.utf8), for: .session)
    let session = try await AccountVault(store: store).session()
    XCTAssertEqual(session, StoredSession(userID: "u1", deviceID: "d1", token: "t", email: "a@b.c", authMethod: .password))
}

func testStoredSessionKeepsItsAuthMethodUnderAuthMethod() async throws {
    let store = InMemorySecretStore()
    let vault = AccountVault(store: store)
    try await vault.setSession(StoredSession(userID: "u1", deviceID: "d1", token: "t", email: "a@b.c", authMethod: .apple))
    let read = try await vault.session()
    XCTAssertEqual(read?.authMethod, .apple)
    let raw = try XCTUnwrap(try store.read(.session))
    let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: raw) as? [String: Any])
    XCTAssertEqual(json["auth_method"] as? String, "apple")
}

func testUnknownAuthMethodIsAnUnreadableSession() async throws {
    let store = InMemorySecretStore()
    try store.write(Data(#"{"userID":"u1","deviceID":"d1","token":"t","email":"a@b.c","auth_method":"carrier-pigeon"}"#.utf8), for: .session)
    let session = try await AccountVault(store: store).session()
    XCTAssertNil(session)
}
```

and create `SignInErrorTests.swift`:

```swift
import Foundation
import ShellXLinkAccount
import XCTest
@testable import ShellXAppCore

final class SignInErrorTests: XCTestCase {
    func testRelayAndProviderErrorsMap() {
        let cases: [(any Error, SignInError)] = [
            (RelayAPIError.http(status: 401, code: "invalid_credentials"), .invalidCredentials),
            (RelayAPIError.http(status: 401, code: "reauth_required"), .reauthRequired),
            (RelayAPIError.http(status: 409, code: "switch_from_signed_in_device"), .switchFromSignedInDevice),
            (RelayAPIError.http(status: 409, code: "email_in_use"), .emailInUse),
            (RelayAPIError.http(status: 409, code: "identity_in_use"), .identityInUse),
            (RelayAPIError.http(status: 429, code: "rate_limited"), .rateLimited),
            (RelayAPIError.http(status: 500, code: "boom"), .server(code: "boom")),
            (RelayAPIError.badResponse, .server(code: "bad_response")),
            (URLError(.notConnectedToInternet), .network),
            (IdentityProviderError.cancelled, .cancelled),
            (IdentityProviderError.notConfigured, .providerUnavailable),
            (IdentityProviderError.failed, .providerFailed),
            (CocoaError(.fileNoSuchFile), .server(code: "unknown")),
        ]
        for (error, expected) in cases { XCTAssertEqual(SignInError(error), expected, "\(error)") }
    }
}
```

- [ ] **Step 2: Run them to see them fail.** Run: `swift test --package-path shellx-ios/Packages/ShellXAppCore --filter 'AccountVaultTests|SignInErrorTests'`. Expected: build error `extra argument 'authMethod' in call`.
- [ ] **Step 3: Implement** the interfaces above; update the doc comment of `SignInError.init` ("Maps what the relay and the identity providers threw").
- [ ] **Step 4: Run them to see them pass.** Same command, then `shellx-ios/scripts/dev.sh test core`. Expected: `with 0 failures`; `==> test core: passed`.
- [ ] **Step 5: Commit.**

```bash
git add shellx-ios/Packages/ShellXAppCore/Sources/ShellXAppCore/Account/StoredSession.swift shellx-ios/Packages/ShellXAppCore/Sources/ShellXAppCore/Account/SignInError.swift shellx-ios/Packages/ShellXAppCore/Sources/ShellXAppCore/Account/RelayAccountCalling.swift shellx-ios/Packages/ShellXAppCore/Sources/ShellXAppCore/Account/RelayAPI+RelayAccountCalling.swift shellx-ios/Packages/ShellXAppCore/Sources/ShellXAppTestSupport/FakeRelayAccount.swift shellx-ios/Packages/ShellXAppCore/Sources/ShellXAppTestSupport/FakeIdentityProvider.swift shellx-ios/Packages/ShellXAppCore/Tests/ShellXAppCoreTests/AccountVaultTests.swift shellx-ios/Packages/ShellXAppCore/Tests/ShellXAppCoreTests/SignInErrorTests.swift
git commit -m "feat(shellx-ios): sessions remember how they signed in; relay calls and errors for Google and Apple"
```

---

### Task 5: "Connect to Your Mac" model for an Apple ID without an account

Paths start at `shellx-ios/Packages/ShellXAppCore/`.

**Files:**
- Create: `Sources/ShellXAppCore/Account/AppleLinkModel.swift`
- Test: `Tests/ShellXAppCoreTests/AppleLinkModelTests.swift`

**Interfaces:**
- Consumes: Task 4 `RelayAccountCalling.linkApple`, `FakeRelayAccount`; existing `PairingModel.Step`, `PairingModel.lowercasingScheme`, `PairingFailure`, `AccountVault.phoneKey()`.
- Produces:

```swift
/// "Connect to Your Mac" after Sign in with Apple found no ShellX account (S1 §6.4): scan the Mac's pairing code,
/// confirm its name, press Allow on the Mac. Steps are `PairingModel.Step`, so the pairing screen shows them. The
/// link token stays in memory and is never logged.
@MainActor @Observable public final class AppleLinkModel {
    public enum Outcome: Equatable, Sendable { case linked(AppleLinkApproval), cancelled, denied, expired }
    public private(set) var step: PairingModel.Step = .idle
    init(linkToken: String, relay: any RelayAccountCalling, vault: AccountVault, finish: @escaping @MainActor (Outcome) async -> Void)
    /// As `PairingModel.begin(uri:)`: trims, lowercases the scheme, parses; never reaches the relay.
    public func begin(uri: String)
    /// `.confirm` → `.waitingForMac` → `relay.linkApple(offerURI:linkToken:clientKey: <phone key>)` → `.paired` then `finish(.linked)`.
    public func confirm() async
    /// Back to `.idle`, dropping the attempt under way (there is nothing to withdraw on the relay).
    public func cancel()
    /// The Close button: `cancel()`, then `finish(.cancelled)`.
    public func close()
}
```

Failure rules in `confirm()`: `PhonePairingError.denied` → `finish(.denied)`; `PhonePairingError.expired` or any `RelayAPIError.http(status: 401, _)` (the link token expired) → `finish(.expired)`; every other error → `step = .failed(PairingFailure(error))` and the link goes on. An answer for an attempt that `begin`, `cancel` or `close` replaced is dropped (as `PairingModel.confirm`, `PairingModel.swift:65-100`).

- [ ] **Step 1: Write the failing tests.**

```swift
import Foundation
import ShellXAppTestSupport
import ShellXLinkAccount
import ShellXLinkCore
import XCTest
@testable import ShellXAppCore

@MainActor
final class AppleLinkModelTests: XCTestCase {
    @MainActor private final class OutcomeLog { var all: [AppleLinkModel.Outcome] = [] }
    private struct Rig { let relay: FakeRelayAccount; let vault: AccountVault; let model: AppleLinkModel; let log: OutcomeLog }
    private let owner = AccountSignIn(session: AccountSession(userID: "owner", deviceID: "d9", token: "tok-a"), email: "owner@example.com")
    private let hostKey = Data(repeating: 4, count: 32)
    private func offer() -> PairingOffer { PairingOffer.make(machineID: "m1", linkSlot: "s1", hostKey: hostKey, machineName: "Studio") }
    private func rig() async -> Rig {
        let relay = FakeRelayAccount()
        await relay.setAppleLinkSignIn(owner)
        let vault = AccountVault(store: InMemorySecretStore())
        let log = OutcomeLog()
        let model = AppleLinkModel(linkToken: "link-1", relay: relay, vault: vault, finish: { log.all.append($0) })
        return Rig(relay: relay, vault: vault, model: model, log: log)
    }

    func testCodeIsReadWithoutTouchingTheRelay() async {
        let rig = await rig()
        rig.model.begin(uri: offer().uri.replacingOccurrences(of: "shellx-link:", with: "SHELLX-LINK:"))
        XCTAssertEqual(rig.model.step, .confirm(machineName: "Studio"))
        let calls = await rig.relay.calls
        XCTAssertEqual(calls, [])
    }

    func testConfirmLinksWithTheTokenAndThePhoneKey() async throws {
        let rig = await rig()
        let offer = offer()
        rig.model.begin(uri: offer.uri)
        await rig.model.confirm()
        let key = try await rig.vault.phoneKey().publicKey
        let calls = await rig.relay.calls
        XCTAssertEqual(calls, [.linkApple(offerURI: offer.uri, linkToken: "link-1", clientKey: key)])
        XCTAssertEqual(rig.log.all, [.linked(AppleLinkApproval(
            signIn: owner, machine: PairedMachine(machineID: "m1", name: "Studio", linkSlot: "s1", hostKey: hostKey)))])
        XCTAssertEqual(rig.model.step, .paired(machineName: "Studio"))
    }

    func testDeniedExpiredAndRefusedTokenEndTheLink() async {
        let cases: [(any Error, AppleLinkModel.Outcome)] = [
            (PhonePairingError.denied, .denied), (PhonePairingError.expired, .expired),
            (RelayAPIError.http(status: 401, code: "invalid_credentials"), .expired),
        ]
        for (error, outcome) in cases {
            let rig = await rig()
            await rig.relay.setError(error, for: .linkApple)
            rig.model.begin(uri: offer().uri)
            await rig.model.confirm()
            XCTAssertEqual(rig.log.all, [outcome], "\(error)")
        }
    }

    func testRetryableFailuresStayOnTheScanner() async {
        let cases: [(any Error, PairingFailure)] = [
            (URLError(.notConnectedToInternet), .network),
            (RelayAPIError.http(status: 404, code: "machine_not_found"), .otherAccount),
            (RelayAPIError.http(status: 500, code: "oops"), .server(code: "oops")),
        ]
        for (error, failure) in cases {
            let rig = await rig()
            await rig.relay.setError(error, for: .linkApple)
            rig.model.begin(uri: offer().uri)
            await rig.model.confirm()
            XCTAssertEqual(rig.model.step, .failed(failure), "\(error)")
            XCTAssertEqual(rig.log.all, [])
            rig.model.cancel()
            XCTAssertEqual(rig.model.step, .idle)
        }
        let rig = await rig()
        rig.model.begin(uri: "hello")
        XCTAssertEqual(rig.model.step, .failed(.notShellXCode))
    }

    func testCloseEndsTheLink() async {
        let rig = await rig()
        rig.model.begin(uri: offer().uri)
        rig.model.close()
        let ended = await eventually { rig.log.all == [.cancelled] }
        XCTAssertTrue(ended, "\(rig.log.all)")
        XCTAssertEqual(rig.model.step, .idle)
    }
}
```

- [ ] **Step 2: Run them to see them fail.** Run: `swift test --package-path shellx-ios/Packages/ShellXAppCore --filter AppleLinkModelTests`. Expected: build error `cannot find 'AppleLinkModel' in scope`.
- [ ] **Step 3: Implement** `AppleLinkModel` to the interface and rules above (`close()` starts a `Task` for `finish(.cancelled)`).
- [ ] **Step 4: Run them to see them pass.** Same command. Expected: `with 0 failures`.
- [ ] **Step 5: Commit.**

```bash
git add shellx-ios/Packages/ShellXAppCore/Sources/ShellXAppCore/Account/AppleLinkModel.swift shellx-ios/Packages/ShellXAppCore/Tests/ShellXAppCoreTests/AppleLinkModelTests.swift
git commit -m "feat(shellx-ios): Connect to Your Mac links an Apple ID through the Mac's pairing code"
```

---

### Task 6: AppCoordinator signs in with Google and Apple

Paths start at `shellx-ios/Packages/ShellXAppCore/`.

**Files:**
- Modify: `Sources/ShellXAppCore/Account/AppCoordinator.swift` (init `:25-36`, `launch` `:40-55`, `signIn(email:password:)` `:63-103`, `signOut` `:109-135`, `handleUnauthorized` `:139-145`), `Sources/ShellXAppCore/Account/AppPhase.swift`, and `shellx-ios/ShellX/UI/RootView.swift:16-30` (one `case`, so the app still builds)
- Create: `Sources/ShellXAppCore/Account/SignInNotice.swift`
- Test: Create `Tests/ShellXAppCoreTests/Support/CoordinatorRig.swift`, `Tests/ShellXAppCoreTests/AppCoordinatorSignInTests.swift`

**Interfaces:**
- Consumes: Tasks 3–5; `CountingWiper`, `FlakyWiper` (`AppCoordinatorTests.swift`), `CoordinatorBox` (`MachineHubTests.swift:668-672`), `instantSleep`, `eventually` (`Support/AsyncTestSupport.swift`).
- Produces:

```swift
// AppPhase gains, after signedOut:
/// Sign in with Apple found no account: "Connect to Your Mac" runs (`AppCoordinator.appleLink`).
case linkingApple

public enum SignInNotice: Equatable, Sendable { case appleLinkDenied, appleLinkExpired, appleLinkFailed }

// AppCoordinator:
public init(
    vault: AccountVault, relay: any RelayAccountCalling, identity: any IdentityProviding = UnavailableIdentityProvider(),
    deviceName: String, wipers: [any LocalDataWiping], pendingWipeDefaults: UserDefaults = .standard,
    makeHub: @escaping @MainActor () -> MachineHub)
/// How the stored session signed in; nil unless signed in.
public private(set) var authMethod: AccountAuthMethod?
/// Non-nil exactly while `phase == .linkingApple`.
public private(set) var appleLink: AppleLinkModel?
/// Why the last Apple link ended; cleared when the next sign-in starts.
public private(set) var signInNotice: SignInNotice?
public func signInWithGoogle() async throws(SignInError)
public func signInWithApple() async throws(SignInError)
```

Order of each sign-in (the tests pin it): clear `signInNotice`; `guard await retryPendingWipe() else { throw .localWipePending }`; phone key (failure → `.server(code: "keychain")`); `relay.nonce()`; then
- Google: `identity.googleIDToken(nonce:)` → `relay.signInWithGoogle(idToken:nonce:deviceName:clientKey:)` → `completeSignIn(_:method: .google)`.
- Apple: `identity.appleCredential(requestNonce: AuthCrypto.sha256Hex(nonce))` → `relay.signInWithApple(identityToken:authorizationCode:nonce: <raw nonce>, deviceName:clientKey:)`; `.signedIn` → `completeSignIn(_:method: .apple)`; `.linkRequired(linkToken, _)` → `appleLink = AppleLinkModel(linkToken:relay:vault:finish:)` (finish → `finishAppleLink`, `[weak self]`), `phase = .linkingApple`.
- Every thrown error goes through `SignInError(_:)`.

`private func completeSignIn(_ signIn: AccountSignIn, method: AccountAuthMethod) async throws(SignInError)` is today's `:81-102` (other-owner wipe first, then machines and session), storing `StoredSession(..., email: signIn.email, authMethod: method)` and setting `authMethod`. `signIn(email:password:)` keeps its signature and calls it with `AccountSignIn(session: session, email: email)` and `.password`.

`finishAppleLink(_:)`: `.linked(approval)` → same owner check and wipe; machines: same owner → today's list with `approval.machine` upserted by `machineID`, other or no owner → `[approval.machine]`; session `authMethod .apple`; `appleLink = nil`; `phase = .signedIn(email: approval.signIn.email)`; `startHub()`. A store or wipe failure there → `appleLink = nil`, `signInNotice = .appleLinkFailed`, `phase = .signedOut(expired: false)`. `.cancelled` → `appleLink = nil`, `phase = .signedOut(expired: false)`. `.denied` / `.expired` → the same with `signInNotice` `.appleLinkDenied` / `.appleLinkExpired`. `launch()` sets `authMethod` from the stored session; `signOut()` and `handleUnauthorized()` set it to nil. The new flows stay in `AppCoordinator.swift` (they use its private state).

- [ ] **Step 1: Write the rig and the failing tests.**

```swift
// Support/CoordinatorRig.swift
import Foundation
import ShellXAppTestSupport
import ShellXLinkAccount
import XCTest
@testable import ShellXAppCore

/// A signed-out AppCoordinator over memory, a FakeRelayAccount and a FakeIdentityProvider. Its hubs reach `macs`
/// and report a refused token to the coordinator.
@MainActor
struct CoordinatorRig {
    let store: InMemorySecretStore
    let vault: AccountVault
    let relay: FakeRelayAccount
    let identity: FakeIdentityProvider
    let wiper: CountingWiper
    let pendingDefaults: UserDefaults
    let coordinator: AppCoordinator

    static func make(
        _ test: XCTestCase, macs: [FakeMac] = [], extraWipers: [any LocalDataWiping] = [],
        store: InMemorySecretStore = InMemorySecretStore(),
        pendingDefaults: UserDefaults = UserDefaults(suiteName: "CoordinatorRig-pending-\(UUID().uuidString)")!
    ) async -> CoordinatorRig {
        let vault = AccountVault(store: store)
        let relay = FakeRelayAccount()
        let identity = FakeIdentityProvider()
        let wiper = CountingWiper()
        let defaults = UserDefaults(suiteName: "CoordinatorRig-\(UUID().uuidString)")!
        let box = CoordinatorBox()
        let coordinator = AppCoordinator(
            vault: vault, relay: relay, identity: identity, deviceName: "Phu's iPhone", wipers: extraWipers + [wiper],
            pendingWipeDefaults: pendingDefaults,
            makeHub: {
                MachineHub(
                    vault: vault, relay: relay, connector: FakeMacFleet(macs, phoneKey: { try await vault.phoneKey() }),
                    latency: LatencyLog(), defaults: defaults, sleep: instantSleep,
                    onUnauthorized: { await box.coordinator?.handleUnauthorized() })
            })
        box.coordinator = coordinator
        test.addTeardownBlock { await coordinator.hub?.stopAll() }
        return CoordinatorRig(
            store: store, vault: vault, relay: relay, identity: identity, wiper: wiper, pendingDefaults: pendingDefaults,
            coordinator: coordinator)
    }
}

/// The error a sign-in, a switch or a deletion threw; nil when it succeeded.
@MainActor
func signInError(_ body: () async throws(SignInError) -> Void) async -> SignInError? {
    do { try await body(); return nil } catch { return error }
}
```

```swift
// AppCoordinatorSignInTests.swift
import Foundation
import ShellXAppTestSupport
import ShellXLinkAccount
import ShellXLinkCore
import XCTest
@testable import ShellXAppCore

@MainActor
final class AppCoordinatorSignInTests: XCTestCase {
    private let google = AccountSignIn(session: AccountSession(userID: "u1", deviceID: "d1", token: "tok-g"), email: "g@example.com")
    private let owner = AccountSignIn(session: AccountSession(userID: "owner", deviceID: "d9", token: "tok-a"), email: "owner@example.com")

    func testGoogleSignInSendsTheNonceTheTokenAndThePhoneKey() async throws {
        let rig = await CoordinatorRig.make(self)
        await rig.relay.setGoogleSignIn(.success(google))
        await rig.coordinator.launch()
        try await rig.coordinator.signInWithGoogle()
        let key = try await rig.vault.phoneKey().publicKey
        let calls = await rig.relay.calls
        XCTAssertEqual(calls, [.nonce, .signInWithGoogle(idToken: "google-id-token", nonce: "nonce-1", deviceName: "Phu's iPhone", clientKey: key)])
        XCTAssertEqual(rig.identity.googleNonces, ["nonce-1"])
        let session = try await rig.vault.session()
        XCTAssertEqual(session, StoredSession(userID: "u1", deviceID: "d1", token: "tok-g", email: "g@example.com", authMethod: .google))
        XCTAssertEqual(rig.coordinator.phase, .signedIn(email: "g@example.com"))
        XCTAssertEqual(rig.coordinator.authMethod, .google)
        XCTAssertNotNil(rig.coordinator.hub)
    }

    func testGoogleSignInCancelledChangesNothing() async throws {
        let rig = await CoordinatorRig.make(self)
        await rig.coordinator.launch()
        rig.identity.googleResult = .failure(IdentityProviderError.cancelled)
        let error = await signInError { try await rig.coordinator.signInWithGoogle() }
        XCTAssertEqual(error, .cancelled)
        let calls = await rig.relay.calls
        XCTAssertEqual(calls, [.nonce])
        XCTAssertEqual(rig.coordinator.phase, .signedOut(expired: false))
        XCTAssertNil(rig.coordinator.hub)
        rig.identity.googleResult = .success("google-id-token")
        try await rig.coordinator.signInWithGoogle()
        XCTAssertEqual(rig.coordinator.authMethod, .google, "the next tap works")
    }

    func testGoogleSignInErrorsMap() async {
        let cases: [(any Error, SignInError)] = [
            (RelayAPIError.http(status: 409, code: "switch_from_signed_in_device"), .switchFromSignedInDevice),
            (RelayAPIError.http(status: 401, code: "invalid_credentials"), .invalidCredentials),
            (RelayAPIError.http(status: 429, code: "rate_limited"), .rateLimited),
        ]
        for (relayError, expected) in cases {
            let rig = await CoordinatorRig.make(self)
            await rig.relay.setGoogleSignIn(.failure(relayError))
            let error = await signInError { try await rig.coordinator.signInWithGoogle() }
            XCTAssertEqual(error, expected)
        }
        let rig = await CoordinatorRig.make(self)
        rig.identity.googleResult = .failure(IdentityProviderError.notConfigured)
        let error = await signInError { try await rig.coordinator.signInWithGoogle() }
        XCTAssertEqual(error, .providerUnavailable)
    }

    func testGoogleSignInAsAnotherAccountWipesTheOldHistory() async throws {
        let rig = await CoordinatorRig.make(self)
        await rig.relay.setGoogleSignIn(.success(google))
        try await rig.vault.setMachines([PairedMachine(machineID: "m0", name: "Old", linkSlot: "s0", hostKey: Data(repeating: 1, count: 32))], owner: "someone-else")
        try await rig.coordinator.signInWithGoogle()
        XCTAssertEqual(rig.wiper.wipes, 1)
        let machines = try await rig.vault.machines()
        let owner = try await rig.vault.machinesOwner()
        XCTAssertEqual(machines, [])
        XCTAssertEqual(owner, "u1")
    }

    func testPendingWipeBlocksGoogleSignInBeforeAnyRelayCall() async {
        let flaky = FlakyWiper()
        let rig = await CoordinatorRig.make(self, extraWipers: [flaky])
        rig.pendingDefaults.set(true, forKey: "shellx.localWipePending")
        let error = await signInError { try await rig.coordinator.signInWithGoogle() }
        XCTAssertEqual(error, .localWipePending)
        let calls = await rig.relay.calls
        XCTAssertEqual(calls, [])
    }

    func testAppleSignInHashesTheNonceForAppleAndSendsItRaw() async throws {
        let rig = await CoordinatorRig.make(self)
        await rig.relay.setAppleSignIn(.success(.signedIn(owner)))
        try await rig.coordinator.signInWithApple()
        XCTAssertEqual(rig.identity.appleRequestNonces, [AuthCrypto.sha256Hex("nonce-1")])
        let key = try await rig.vault.phoneKey().publicKey
        let calls = await rig.relay.calls
        XCTAssertEqual(calls, [.nonce, .signInWithApple(
            identityToken: "apple-id-token", authorizationCode: "apple-code", nonce: "nonce-1", deviceName: "Phu's iPhone", clientKey: key)])
        XCTAssertEqual(rig.coordinator.authMethod, .apple)
        let session = try await rig.vault.session()
        XCTAssertEqual(session?.authMethod, .apple)
    }

    func testAppleWithoutAccountLinksThroughTheMac() async throws {
        let mac = FakeMac(name: "Studio")
        let rig = await CoordinatorRig.make(self, macs: [mac])
        await rig.relay.setAppleSignIn(.success(.linkRequired(linkToken: "link-1", expiresIn: 600)))
        await rig.relay.setAppleLinkSignIn(owner)
        await rig.coordinator.launch()
        try await rig.coordinator.signInWithApple()
        XCTAssertEqual(rig.coordinator.phase, .linkingApple)
        let stored = try await rig.vault.session()
        XCTAssertNil(stored, "nothing is stored before the Mac allows it")
        let link = try XCTUnwrap(rig.coordinator.appleLink)
        link.begin(uri: await mac.pairingCode())
        await link.confirm()
        XCTAssertEqual(rig.coordinator.phase, .signedIn(email: "owner@example.com"))
        XCTAssertEqual(rig.coordinator.authMethod, .apple)
        XCTAssertNil(rig.coordinator.appleLink)
        let machines = try await rig.vault.machines()
        let machineOwner = try await rig.vault.machinesOwner()
        XCTAssertEqual(machines, [mac.machine])
        XCTAssertEqual(machineOwner, "owner")
        let online = await eventually { rig.coordinator.hub?.machines.first?.state == .online }
        XCTAssertTrue(online)
    }

    func testLinkKeepsThisAccountsOtherMacsAndWipesAnotherAccountsHistory() async throws {
        let mac = FakeMac(name: "Studio")
        let other = PairedMachine(machineID: "m0", name: "Old", linkSlot: "s0", hostKey: Data(repeating: 1, count: 32))
        for (previousOwner, expected, wipes) in [("owner", [other, mac.machine], 0), ("someone-else", [mac.machine], 1)] {
            let rig = await CoordinatorRig.make(self, macs: [mac])
            try await rig.vault.setMachines([other], owner: previousOwner)
            await rig.relay.setAppleSignIn(.success(.linkRequired(linkToken: "link-1", expiresIn: 600)))
            await rig.relay.setAppleLinkSignIn(owner)
            try await rig.coordinator.signInWithApple()
            let link = try XCTUnwrap(rig.coordinator.appleLink)
            link.begin(uri: await mac.pairingCode())
            await link.confirm()
            let machines = try await rig.vault.machines()
            XCTAssertEqual(machines, expected, previousOwner)
            XCTAssertEqual(rig.wiper.wipes, wipes, previousOwner)
        }
    }

    func testEndedLinksReturnToSignInWithANoticeThatTheNextSignInClears() async throws {
        let cases: [(any Error, SignInNotice)] = [
            (PhonePairingError.denied, .appleLinkDenied), (RelayAPIError.http(status: 401, code: "invalid_credentials"), .appleLinkExpired),
        ]
        for (error, notice) in cases {
            let rig = await CoordinatorRig.make(self)
            await rig.relay.setAppleSignIn(.success(.linkRequired(linkToken: "link-1", expiresIn: 600)))
            await rig.relay.setError(error, for: .linkApple)
            try await rig.coordinator.signInWithApple()
            let link = try XCTUnwrap(rig.coordinator.appleLink)
            link.begin(uri: PairingOffer.make(machineID: "m1", linkSlot: "s1", hostKey: Data(repeating: 4, count: 32), machineName: "Studio").uri)
            await link.confirm()
            XCTAssertEqual(rig.coordinator.phase, .signedOut(expired: false))
            XCTAssertEqual(rig.coordinator.signInNotice, notice)
            XCTAssertNil(rig.coordinator.appleLink)
            try await rig.coordinator.signInWithGoogle()
            XCTAssertNil(rig.coordinator.signInNotice)
        }
    }

    func testClosingTheLinkReturnsToSignInQuietly() async throws {
        let rig = await CoordinatorRig.make(self)
        await rig.relay.setAppleSignIn(.success(.linkRequired(linkToken: "link-1", expiresIn: 600)))
        try await rig.coordinator.signInWithApple()
        try XCTUnwrap(rig.coordinator.appleLink).close()
        let back = await eventually { rig.coordinator.phase == .signedOut(expired: false) }
        XCTAssertTrue(back)
        XCTAssertNil(rig.coordinator.signInNotice)
        XCTAssertNil(rig.coordinator.appleLink)
    }
}
```

- [ ] **Step 2: Run them to see them fail.** Run: `swift test --package-path shellx-ios/Packages/ShellXAppCore --filter AppCoordinatorSignInTests`. Expected: build error `extra argument 'identity' in call` (or `has no member 'signInWithGoogle'`).
- [ ] **Step 3: Implement** the interfaces and the order above.
- [ ] **Step 4: Run them to see them pass.** `AppPhase` has a new case, so first add `case .linkingApple: LaunchView()` to the `switch` of `shellx-ios/ShellX/UI/RootView.swift:16-30` (Task 10 gives it its screen). Run the same command, then `shellx-ios/scripts/dev.sh test core` (the existing `AppCoordinatorTests`, `PairingModelTests` and `MachineHubTests` stay green) and `shellx-ios/scripts/dev.sh test app` (the app still builds). Expected: `with 0 failures`; `==> test core: passed`; `==> test app: passed`.
- [ ] **Step 5: Commit.**

```bash
git add shellx-ios/Packages/ShellXAppCore/Sources/ShellXAppCore/Account/AppCoordinator.swift shellx-ios/Packages/ShellXAppCore/Sources/ShellXAppCore/Account/AppPhase.swift shellx-ios/Packages/ShellXAppCore/Sources/ShellXAppCore/Account/SignInNotice.swift shellx-ios/Packages/ShellXAppCore/Tests/ShellXAppCoreTests/Support/CoordinatorRig.swift shellx-ios/Packages/ShellXAppCore/Tests/ShellXAppCoreTests/AppCoordinatorSignInTests.swift shellx-ios/ShellX/UI/RootView.swift
git commit -m "feat(shellx-ios): the coordinator signs in with Google and Apple and links Apple IDs"
```

---

### Task 7: Switch to Google sign-in and Delete Account in the coordinator

Paths start at `shellx-ios/Packages/ShellXAppCore/`.

**Files:**
- Modify: `Sources/ShellXAppCore/Account/AppCoordinator.swift`
- Test: Create `Tests/ShellXAppCoreTests/AccountChangeTests.swift`

**Interfaces:**
- Consumes: Task 6 (`CoordinatorRig`, `completeSignIn`), Task 4 (`FakeRelayAccount.setHook`, `setLinkGoogle`).
- Produces:

```swift
/// S1 §6.3b: a password session becomes a Google one on this iPhone, keeping the account, its Macs and history.
public func switchToGoogle() async throws(SignInError)
/// S1 §6.8: sign in again with the account's provider, delete the account on the relay, then forget everything
/// local exactly as `signOut()` does (without unpairing or logging out: the account is gone).
public func deleteAccount() async throws(SignInError)
```

Rules:
- `switchToGoogle()`: does nothing unless the stored session's `authMethod` is `.password`. `relay.nonce()`; `identity.googleIDToken(nonce:)`; then, with a private `accountChangeInProgress` flag set, `relay.linkGoogle(idToken:nonce:token: <stored token>)`; store `StoredSession(<new session>, email: signIn.email, authMethod: .google)`; `stopHub()` then `startHub()` (a fresh hub: requests of the old one may carry the deleted token); `phase = .signedIn(email: signIn.email)`, `authMethod = .google`; clear the flag. The screens therefore start again at the home, as after a sign-in.
- `deleteAccount()`: no stored session → `.server(code: "signed_out")`; `.password` → throw `.switchToGoogleFirst` before any call; `relay.nonce()`; `.google` → `identity.googleIDToken(nonce:)`, `.apple` → `identity.appleCredential(requestNonce: AuthCrypto.sha256Hex(nonce)).identityToken`; with the flag set, `relay.deleteAccount(idToken:nonce:token:)`; `stopHub()`; the local part of `signOut()` (`AppCoordinator.swift:126-133`, extracted into one private function both use); `phase = .signedOut(expired: false)`, `authMethod = nil`; clear the flag.
- `handleUnauthorized()`: while the flag is set it only remembers that a 401 came and returns. On success that remembered 401 is dropped: it answered the token the relay just replaced or deleted.
- Failures of both: clear the flag; `RelayAPIError.http(401, "unauthorized")` (the stored token itself is refused) → `handleUnauthorized()`, then throw `.server(code: "unauthorized")`; otherwise, when a 401 was remembered during the call → `handleUnauthorized()`; throw `SignInError(error)`. The hub and the session stay as they were.

- [ ] **Step 1: Write the failing tests.**

```swift
import Foundation
import ShellXAppTestSupport
import ShellXLinkAccount
import XCTest
@testable import ShellXAppCore

@MainActor
final class AccountChangeTests: XCTestCase {
    private let googleSession = AccountSignIn(session: AccountSession(userID: "u1", deviceID: "d1", token: "tok-google"), email: "g@example.com")

    private func signedIn(_ method: AccountAuthMethod, macs: [FakeMac] = []) async throws -> CoordinatorRig {
        let rig = await CoordinatorRig.make(self, macs: macs)
        try await rig.vault.setSession(StoredSession(userID: "u1", deviceID: "d1", token: "tok-old", email: "old@example.com", authMethod: method))
        try await rig.vault.setMachines(macs.map { $0.machine }, owner: "u1")
        await rig.relay.setLinkGoogle(.success(googleSession))
        await rig.coordinator.launch()
        return rig
    }

    func testSwitchToGoogleStoresTheGoogleSessionAndRestartsTheHub() async throws {
        let mac = FakeMac(name: "Studio")
        let rig = try await signedIn(.password, macs: [mac])
        let before = try XCTUnwrap(rig.coordinator.hub)
        try await rig.coordinator.switchToGoogle()
        let calls = await rig.relay.calls
        XCTAssertEqual(calls, [.nonce, .linkGoogle(idToken: "google-id-token", nonce: "nonce-1", token: "tok-old")])
        let session = try await rig.vault.session()
        XCTAssertEqual(session, StoredSession(userID: "u1", deviceID: "d1", token: "tok-google", email: "g@example.com", authMethod: .google))
        XCTAssertEqual(rig.coordinator.phase, .signedIn(email: "g@example.com"))
        XCTAssertEqual(rig.coordinator.authMethod, .google)
        let after = try XCTUnwrap(rig.coordinator.hub)
        XCTAssertFalse(after === before)
        XCTAssertEqual(after.machines.map(\.id), [mac.machine.machineID], "the Macs stay")
    }

    func testSwitchIsOnlyForPasswordSessions() async throws {
        let rig = try await signedIn(.google)
        try await rig.coordinator.switchToGoogle()
        let calls = await rig.relay.calls
        XCTAssertEqual(calls, [])
    }

    func testFailedSwitchKeepsThePasswordSessionAndTheHub() async throws {
        for (code, expected) in [("email_in_use", SignInError.emailInUse), ("identity_in_use", .identityInUse)] {
            let rig = try await signedIn(.password)
            await rig.relay.setLinkGoogle(.failure(RelayAPIError.http(status: 409, code: code)))
            let before = try XCTUnwrap(rig.coordinator.hub)
            let error = await signInError { try await rig.coordinator.switchToGoogle() }
            XCTAssertEqual(error, expected)
            let session = try await rig.vault.session()
            XCTAssertEqual(session?.token, "tok-old")
            XCTAssertEqual(session?.authMethod, .password)
            XCTAssertTrue(rig.coordinator.hub === before)
        }
    }

    func testSwitchWithARefusedTokenSignsOutAsExpired() async throws {
        let mac = FakeMac(name: "Studio")
        let rig = try await signedIn(.password, macs: [mac])
        await rig.relay.setLinkGoogle(.failure(RelayAPIError.http(status: 401, code: "unauthorized")))
        _ = await signInError { try await rig.coordinator.switchToGoogle() }
        XCTAssertEqual(rig.coordinator.phase, .signedOut(expired: true))
        let machines = try await rig.vault.machines()
        XCTAssertEqual(machines, [mac.machine])
    }

    func testUnauthorizedDuringSwitchIsIgnoredAndTheNewSessionStays() async throws {
        let rig = try await signedIn(.password)
        let coordinator = rig.coordinator
        await rig.relay.setHook({ await coordinator.handleUnauthorized() }, for: .linkGoogle)
        try await rig.coordinator.switchToGoogle()
        XCTAssertEqual(rig.coordinator.phase, .signedIn(email: "g@example.com"))
        let session = try await rig.vault.session()
        XCTAssertEqual(session?.token, "tok-google")
    }

    func testDeleteGoogleAccountReauthenticatesDeletesAndWipesLikeSignOut() async throws {
        let rig = try await signedIn(.google)
        rig.identity.googleResult = .success("google-fresh")
        try await rig.coordinator.deleteAccount()
        let calls = await rig.relay.calls
        XCTAssertEqual(calls, [.nonce, .deleteAccount(idToken: "google-fresh", nonce: "nonce-1", token: "tok-old")], "no unpair, no logout")
        for item in SecretItem.allCases { XCTAssertNil(try rig.store.read(item)) }
        XCTAssertEqual(rig.wiper.wipes, 1)
        XCTAssertFalse(rig.pendingDefaults.bool(forKey: "shellx.localWipePending"))
        XCTAssertEqual(rig.coordinator.phase, .signedOut(expired: false))
        XCTAssertNil(rig.coordinator.authMethod)
        XCTAssertNil(rig.coordinator.hub)
    }

    func testDeleteAppleAccountSignsInWithAppleUsingTheHashedNonce() async throws {
        let rig = try await signedIn(.apple)
        try await rig.coordinator.deleteAccount()
        XCTAssertEqual(rig.identity.appleRequestNonces, [AuthCrypto.sha256Hex("nonce-1")])
        let calls = await rig.relay.calls
        XCTAssertEqual(calls.last, .deleteAccount(idToken: "apple-id-token", nonce: "nonce-1", token: "tok-old"))
    }

    func testDeletePasswordSessionAsksToSwitchFirst() async throws {
        let rig = try await signedIn(.password)
        let error = await signInError { try await rig.coordinator.deleteAccount() }
        XCTAssertEqual(error, .switchToGoogleFirst)
        let calls = await rig.relay.calls
        XCTAssertEqual(calls, [])
        XCTAssertEqual(rig.identity.googleNonces, [])
    }

    func testCancelledOrRefusedDeleteKeepsEverything() async throws {
        let cancelled = try await signedIn(.google)
        cancelled.identity.googleResult = .failure(IdentityProviderError.cancelled)
        let cancelError = await signInError { try await cancelled.coordinator.deleteAccount() }
        XCTAssertEqual(cancelError, .cancelled)
        let cancelCalls = await cancelled.relay.calls
        XCTAssertEqual(cancelCalls, [.nonce])

        let refused = try await signedIn(.google)
        await refused.relay.setError(RelayAPIError.http(status: 401, code: "reauth_required"), for: .deleteAccount)
        let before = try XCTUnwrap(refused.coordinator.hub)
        let refusedError = await signInError { try await refused.coordinator.deleteAccount() }
        XCTAssertEqual(refusedError, .reauthRequired)
        let session = try await refused.vault.session()
        XCTAssertEqual(session?.token, "tok-old")
        XCTAssertTrue(refused.coordinator.hub === before)
    }

    func testUnauthorizedDuringDeleteEndsSignedOutNotExpired() async throws {
        let rig = try await signedIn(.google)
        let coordinator = rig.coordinator
        await rig.relay.setHook({ await coordinator.handleUnauthorized() }, for: .deleteAccount)
        try await rig.coordinator.deleteAccount()
        XCTAssertEqual(rig.coordinator.phase, .signedOut(expired: false))
    }
}
```

- [ ] **Step 2: Run them to see them fail.** Run: `swift test --package-path shellx-ios/Packages/ShellXAppCore --filter AccountChangeTests`. Expected: build error `value of type 'AppCoordinator' has no member 'switchToGoogle'`.
- [ ] **Step 3: Implement** both methods and the `handleUnauthorized` rule.
- [ ] **Step 4: Run them to see them pass.** Same command, then `shellx-ios/scripts/dev.sh test core`. Expected: `with 0 failures`; `==> test core: passed`.
- [ ] **Step 5: Commit.**

```bash
git add shellx-ios/Packages/ShellXAppCore/Sources/ShellXAppCore/Account/AppCoordinator.swift shellx-ios/Packages/ShellXAppCore/Tests/ShellXAppCoreTests/AccountChangeTests.swift
git commit -m "feat(shellx-ios): switch a password session to Google and delete the account"
```

---

### Task 8: System sheets, client IDs per build and the App Store checks for them

**Files:**
- Create: `shellx-ios/ShellX/Platform/SystemWebAuthenticator.swift`, `shellx-ios/ShellX/Platform/SystemAppleAuthorizer.swift`, `shellx-ios/ShellX/Platform/SystemIdentityProvider.swift`
- Modify: `shellx-ios/ShellX/AppComposition.swift:41-53` (pass `identity:`), `shellx-ios/Config/Debug.xcconfig` (after `:8`), `shellx-ios/Config/Release.xcconfig` (after `:7`), `shellx-ios/Config/Info.plist` (after `:58-59`), `shellx-ios/Config/ShellX.entitlements`, `release/mobile/ios.sh` (after `:111`, and inside the signed block after `:125`), `release/mobile/README.md:23-36`
- Test: Modify `shellx-ios/ShellXTests/LaunchSmokeTests.swift`; Create `shellx-ios/Packages/ShellXAppCore/Tests/ShellXAppCoreTests/ReleaseCheckTests.swift`

**Interfaces:**
- Consumes: Task 3 (`IdentityProviding`, `WebAuthenticating`, `GoogleOAuthClient`, `GoogleSignIn`, `AppleCredential`, `IdentityProviderError`), Task 6 (`AppCoordinator(identity:)`).
- Produces (app target):

```swift
/// Google's page in the system's web sign-in sheet (S1 §4: never an embedded web view).
@MainActor final class SystemWebAuthenticator: NSObject, WebAuthenticating, ASWebAuthenticationPresentationContextProviding
/// Sign in with Apple through ASAuthorizationController.
@MainActor final class SystemAppleAuthorizer: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    func authorize(requestNonce: String) async throws -> AppleCredential
}
@MainActor final class SystemIdentityProvider: IdentityProviding {
    /// `googleClientID` is Info.plist `ShellXGoogleClientID`; one that `GoogleOAuthClient` refuses makes Google throw `.notConfigured`.
    init(googleClientID: String?)
}
```

Behaviour of the glue (not unit-testable beyond Step 1):
- `SystemWebAuthenticator`: one `ASWebAuthenticationSession(url:callbackURLScheme:completionHandler:)` (if the SDK marks that initializer deprecated, use `ASWebAuthenticationSession(url:callback: .customScheme(callbackScheme), completionHandler:)` under `if #available(iOS 17.4, *)` and keep the old one as the fallback), kept in a property until it completes; `prefersEphemeralWebBrowserSession = false`; `ASWebAuthenticationSessionError.canceledLogin` → `IdentityProviderError.cancelled`, any other error or a nil URL → `.failed`; anchor: the key window of the foreground-active `UIWindowScene`. No `CFBundleURLTypes` entry is added: the session catches its callback scheme itself.
- `SystemAppleAuthorizer`: `ASAuthorizationAppleIDProvider().createRequest()`, `requestedScopes = [.email]`, `nonce = requestNonce`; `identityToken` and `authorizationCode` decoded as UTF-8 (missing → `.failed`); `ASAuthorizationError.canceled` → `.cancelled`, others → `.failed`. When Swift 6 reports an isolation mismatch on a delegate conformance, mark that conformance `@preconcurrency`.
- `SystemIdentityProvider.googleIDToken`: `GoogleOAuthClient(clientID: googleClientID ?? "")`, nil → `IdentityProviderError.notConfigured`, else `GoogleSignIn(client:web: SystemWebAuthenticator()).idToken(nonce:)`; `appleCredential` → its `SystemAppleAuthorizer`.
- `AppComposition.make()`: `identity: SystemIdentityProvider(googleClientID: bundle.object(forInfoDictionaryKey: "ShellXGoogleClientID") as? String)`.

Exact config text:

```text
// Debug.xcconfig, after SHELLX_APS_ENVIRONMENT:
// Google sign-in: the iOS OAuth client of com.shellx.dev without its ".apps.googleusercontent.com" suffix
// (Info.plist ShellXGoogleClientID). Not a secret. The placeholder makes Continue with Google report
// "not available in this build".
SHELLX_GOOGLE_IOS_CLIENT = 0-shellx-placeholder

// Release.xcconfig, after SHELLX_APS_ENVIRONMENT:
// Google sign-in: the iOS OAuth client of com.shellx.prod without its ".apps.googleusercontent.com" suffix.
// Not a secret. release/mobile/ios.sh refuses an App Store build that still has the placeholder.
SHELLX_GOOGLE_IOS_CLIENT = 0-shellx-placeholder
```

```xml
<!-- Info.plist, after ShellXKeychainGroup -->
	<key>ShellXGoogleClientID</key>
	<string>$(SHELLX_GOOGLE_IOS_CLIENT).apps.googleusercontent.com</string>
<!-- ShellX.entitlements, after keychain-access-groups -->
	<key>com.apple.developer.applesignin</key>
	<array>
		<string>Default</string>
	</array>
```

```bash
# release/mobile/ios.sh, check_app, after the NSAllowsLocalNetworking check (line 111):
  # Google sign-in needs the real iOS OAuth client of com.shellx.prod (SHELLX_GOOGLE_IOS_CLIENT in
  # Release.xcconfig); the placeholder only serves builds that never reach the store.
  value="$(plist_value ShellXGoogleClientID "$info" || true)"
  if ! [[ "$value" =~ ^[0-9]+-[a-z0-9]+\.apps\.googleusercontent\.com$ ]]; then
    if [ "$mode" = "signed" ]; then
      fail+=("ShellXGoogleClientID is '$value', not a Google iOS client id (set SHELLX_GOOGLE_IOS_CLIENT in shellx-ios/Config/Release.xcconfig)")
    else
      note "$label: ShellXGoogleClientID is not a Google iOS client id yet ('$value'): Continue with Google cannot work in this build"
    fi
  fi
# inside `if [ "$mode" = "signed" ]`, after the aps-environment check (line 125):
    # Sign in with Apple (S1 §6.6).
    if [ "$(plist_value com.apple.developer.applesignin:0 "$entitlements" || true)" != "Default" ]; then
      fail+=("lacks the Sign in with Apple entitlement (com.apple.developer.applesignin = Default)")
    fi
```

`release/mobile/README.md`, step 2's list gains, after the `aps-environment` line: "- its `ShellXGoogleClientID` is not a Google iOS client id (`SHELLX_GOOGLE_IOS_CLIENT` in `shellx-ios/Config/Release.xcconfig` still holds the placeholder);" and "- it lacks the Sign in with Apple entitlement `com.apple.developer.applesignin`;".

- [ ] **Step 1: Write the failing tests.** Add to `LaunchSmokeTests`:

```swift
func testGoogleClientIDComesFromTheBuildSettings() {
    let id = Bundle.main.object(forInfoDictionaryKey: "ShellXGoogleClientID") as? String
    XCTAssertEqual(id?.hasSuffix(".apps.googleusercontent.com"), true, id ?? "nil")
    XCTAssertEqual(id?.contains("$("), false, "the build setting was expanded")
}

@MainActor
func testPlaceholderClientMakesGoogleUnavailable() async {
    let provider = SystemIdentityProvider(googleClientID: "0-shellx-placeholder.apps.googleusercontent.com")
    do { _ = try await provider.googleIDToken(nonce: "n"); XCTFail("signed in without a client") } catch {
        XCTAssertEqual(error as? IdentityProviderError, .notConfigured)
    }
}
```

and create `ReleaseCheckTests.swift`:

```swift
#if os(macOS)
import Foundation
import XCTest

/// `release/mobile/ios.sh --check-app --unsigned` on a fake app: an Info.plist and a tiny Mach-O whose strings the test picks.
final class ReleaseCheckTests: XCTestCase {
    private var script: String { ScriptRunner.repositoryRoot.appendingPathComponent("release/mobile/ios.sh").path }

    /// MARKETING_VERSION and CURRENT_PROJECT_VERSION of shellx-ios/Config/Version.xcconfig.
    private func version() throws -> (marketing: String, build: String) {
        let text = try String(contentsOf: ScriptRunner.repositoryRoot.appendingPathComponent("shellx-ios/Config/Version.xcconfig"), encoding: .utf8)
        func value(_ key: String) throws -> String {
            let line = try XCTUnwrap(text.split(separator: "\n").first { $0.hasPrefix(key) })
            return String(try XCTUnwrap(line.split(separator: "=").last)).trimmingCharacters(in: .whitespaces)
        }
        return (try value("MARKETING_VERSION"), try value("CURRENT_PROJECT_VERSION"))
    }

    private func makeApp(clientID: String = "123456789012-abcdef123.apps.googleusercontent.com", names: String = "ShellX") throws -> URL {
        let root = try ScriptRunner.temporaryDirectory(for: self)
        let app = root.appendingPathComponent("ShellX.app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        let (marketing, build) = try version()
        let info: [String: Any] = [
            "CFBundleIdentifier": "com.shellx.prod", "CFBundleShortVersionString": marketing, "CFBundleVersion": build,
            "CFBundleExecutable": "ShellX", "ShellXGoogleClientID": clientID,
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: app.appendingPathComponent("Info.plist"))
        try ScriptRunner.write("const char *volatile shellx_names = \"\(names)\";\nint main(void) { return shellx_names[0] == 0; }\n", to: "main.c", under: root)
        let cc = try ScriptRunner.run("xcrun", ["clang", "-x", "c", root.appendingPathComponent("main.c").path, "-o", app.appendingPathComponent("ShellX").path])
        XCTAssertEqual(cc.status, 0, cc.output)
        return app
    }
    private func check(_ app: URL) throws -> ScriptRunner.Result { try ScriptRunner.run("bash", [script, "--check-app", "--unsigned", app.path]) }

    func testRealGoogleClientPassesQuietly() throws {
        let result = try check(try makeApp())
        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertFalse(result.output.contains("not a Google iOS client id"), result.output)
    }

    func testPlaceholderGoogleClientIsOnlyNotedWhenUnsigned() throws {
        let result = try check(try makeApp(clientID: "0-shellx-placeholder.apps.googleusercontent.com"))
        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("ShellXGoogleClientID is not a Google iOS client id yet"), result.output)
    }
}
#endif
```

- [ ] **Step 2: Run them to see them fail.** Run: `swift test --package-path shellx-ios/Packages/ShellXAppCore --filter ReleaseCheckTests` (expected: `testPlaceholderGoogleClientIsOnlyNotedWhenUnsigned` fails, the note is missing) and `shellx-ios/scripts/dev.sh test app` (expected: `error: cannot find 'SystemIdentityProvider' in scope`, then `==> test app: FAILED`).
- [ ] **Step 3: Implement** the three platform classes, the wiring, the config text, the `ios.sh` checks and the README lines above.
- [ ] **Step 4: Run them to see them pass.** Run the two commands of Step 2, then `shellx-ios/scripts/dev.sh test release`. Expected: `with 0 failures`; `==> test app: passed`; `==> test release: passed`, with the note line `ShellXGoogleClientID is not a Google iOS client id yet ('0-shellx-placeholder.apps.googleusercontent.com')` while the placeholder is in.
- [ ] **Step 5: USER: create the two Google iOS clients** (S1 §10; not secret). Google Cloud console, project `shellxpro` (contracts §16; if it asks for the OAuth consent screen first, set it up as plan 1D Task 1 Step 2 describes) → APIs & Services → Credentials → + Create credentials → OAuth client ID → Application type **iOS** → Name `ShellX iOS (dev)`, Bundle ID `com.shellx.dev` → Create; again with Name `ShellX iOS`, Bundle ID `com.shellx.prod`. Paste both client IDs in the chat, or put the part before `.apps.googleusercontent.com` into `SHELLX_GOOGLE_IOS_CLIENT` in `shellx-ios/Config/Debug.xcconfig` (dev) and `shellx-ios/Config/Release.xcconfig` (prod). Both full client IDs also go into the relay's `GOOGLE_CLIENT_IDS` when 1D sets the relay env. Meanwhile the executor goes on with the placeholder; when the IDs arrive, it replaces the two values and commits them as `chore(shellx-ios): Google iOS client ids`.
- [ ] **Step 6: USER: enable Sign in with Apple on both App IDs.** developer.apple.com → Certificates, Identifiers & Profiles → Identifiers → `com.shellx.prod` → Capabilities → tick **Sign In with Apple** → Edit → "Enable as a primary App ID" → Save → Confirm; then `com.shellx.dev` → tick **Sign In with Apple** → Edit → "Group with an existing primary App ID" → `com.shellx.prod` → Save → Confirm (contracts §16: the relay's one Sign in with Apple key serves both bundles; plan 1D Task 3 checks it). Device builds (`dev.sh device`, `ios.sh`) need it; simulator builds and the tests of this plan should not, so the executor goes on (if `dev.sh test app` ever stops on a provisioning error naming `com.apple.developer.applesignin`, it waits for this step).
- [ ] **Step 7: Commit.**

```bash
git add shellx-ios/ShellX/Platform/SystemWebAuthenticator.swift shellx-ios/ShellX/Platform/SystemAppleAuthorizer.swift shellx-ios/ShellX/Platform/SystemIdentityProvider.swift shellx-ios/ShellX/AppComposition.swift shellx-ios/Config/Debug.xcconfig shellx-ios/Config/Release.xcconfig shellx-ios/Config/Info.plist shellx-ios/Config/ShellX.entitlements release/mobile/ios.sh release/mobile/README.md shellx-ios/ShellXTests/LaunchSmokeTests.swift shellx-ios/Packages/ShellXAppCore/Tests/ShellXAppCoreTests/ReleaseCheckTests.swift
git commit -m "feat(shellx-ios): Google and Apple sign-in on the system sheets, a Google client per build"
```

---

### Task 9: The sign-in screen: Google's branded button beside Apple's, no password field

**Files:**
- Modify: `shellx-ios/ShellX/UI/SignIn/SignInView.swift` (whole file), `shellx-ios/ShellX/UI/RootView.swift:19-20`, `shellx-ios/ShellX/Localizable.xcstrings`, `release/mobile/ios.sh` (after Task 8's Google client check), `release/mobile/README.md` (step 2's list), `shellx-ios/README.md` (section "Assets")
- Create: `shellx-ios/ShellX/UI/SignIn/GoogleSignInButton.swift`, `shellx-ios/ShellX/UI/SignIn/AppleSignInButton.swift`, `shellx-ios/ShellX/UI/SignIn/SignInErrorText.swift`
- After the USER step (Steps 6–8): Create `shellx-ios/ShellX/Assets.xcassets/GoogleG.imageset/Contents.json`, `GoogleG@2x.png`, `GoogleG@3x.png`, `shellx-ios/ShellX/Fonts/GoogleSans.ttf`, `shellx-ios/ShellX/Fonts/GoogleSans-OFL.txt`; Modify `shellx-ios/Config/Info.plist` (`UIAppFonts`)
- Test: Modify `shellx-ios/ShellXTests/AccountRenderTests.swift`, `shellx-ios/Packages/ShellXAppCore/Tests/ShellXAppCoreTests/ReleaseCheckTests.swift`

**Interfaces:**
- Consumes: Task 6 (`signInWithGoogle()`, `signInWithApple()`, `signInNotice`), Tasks 4/6 (`SignInError`, `SignInNotice`).
- Produces:

```swift
struct SignInView: View {
    init(coordinator: AppCoordinator, expired: Bool, notice: SignInNotice? = nil, initialError: SignInError? = nil)
}
/// "Continue with Google" drawn to Google's branding guidelines (contracts §11); its values follow this block.
struct GoogleSignInButton: View {
    var busy = false
    let action: () -> Void
    /// Google's official "G" (asset `GoogleG`, 20 × 20 pt); nil until Step 7 adds it, and the button then shows its text only.
    static var mark: UIImage? { UIImage(named: "GoogleG") }
    /// Google Sans Medium 14 pt: the bundled variable font `GoogleSans-Regular` with its `wght` axis (tag 0x77676874) at 500;
    /// `UIFont.systemFont(ofSize: 14, weight: .medium)` until Step 7 bundles the font.
    static func labelFont() -> UIFont
}
/// Apple's own button (HIG): `ASAuthorizationAppleIDButton(authorizationButtonType: .signIn, authorizationButtonStyle:)`,
/// `.whiteOutline` in light mode and `.white` in dark mode, 44 pt high, `cornerRadius` 22 (the same pill as Google's), enabled
/// from the SwiftUI environment. It only reports the tap: the app fetches the relay's nonce first, then runs the request.
struct AppleSignInButton: UIViewRepresentable { let action: () -> Void }
/// The words for a failure or a notice; shared by the sign-in screen and Settings › Account.
enum SignInErrorText {
    /// nil for `.cancelled`: closing Google's or Apple's sheet is not an error.
    static func message(for error: SignInError) -> String?
    static func message(for notice: SignInNotice) -> String
}
// RootView: SignInView(coordinator: coordinator, expired: expired, notice: coordinator.signInNotice)
```

`GoogleSignInButton` follows https://developers.google.com/identity/branding-guidelines (re-read the named sections before Step 3):
- "Color": the Light theme, fill `#FFFFFF`, stroke `#747775` 1 pt inside (`strokeBorder`), text `#1F1F1F`, in both appearances (Spec notes: equal prominence beside Apple's white button in dark mode).
- "Font": Google Sans Medium, 14/20 (14 pt, 20 pt line).
- **Font licence gate (before bundling, USER-visible):** bundle `GoogleSans.ttf` only if it comes from its official source (Google Fonts or Google's own repository) with an SIL Open Font License 1.1 text, which is then saved as `GoogleSans-OFL.txt` next to it. If the official download is not OFL (or the licence cannot be confirmed), do **not** bundle it: keep the system font on the button, record the reason in the hand-off note, and leave `testGoogleSansIsUsedOnceBundled` skipped. The `ios.sh` refusal then checks only the `GoogleG` asset. Prefer the **static** `GoogleSans-Medium.ttf` when the official download has one (plan 1B does the same; the variable font adds about 5 MB): then the PostScript name in the test and in `GoogleSignInButton.labelFont()` is `GoogleSans-Medium` and no `wght` axis setting is needed. Use the variable font only if no static Medium face exists.
- "Padding" (iOS): 16 pt before the G, 12 pt between the G and the text, 16 pt after the text. "Google logo in the Sign in with Google button": the G is 20 × 20 pt, never scaled or recoloured.
- "Theme and Shape options": Pill, 44 pt high (the height of Google's own iOS buttons in the bundle), full width, with the G and the text centred together as one group.
- "Text": `signin.google`, "Continue with Google" / "Tiếp tục với Google" (the page allows the translation).
- Without the `GoogleG` asset the G and its 12 pt gap are left out (the text-only fallback). While `busy`, a `ProgressView` tinted `#1F1F1F` replaces the group; disabled, it fades to 40 % like `PrimaryButtonStyle`; id `signin.google`.

Screen, top to bottom (padding, widths and fonts as today's `SignInView`): logo; `signin.title`; `signin.subtitle`; `signin.expired` when `expired`; the notice (`StatusNeedsYou`); the error (`StatusError`, announced as today); `GoogleSignInButton`, then `AppleSignInButton` 12 pt below it, both full width and 44 pt high so neither is more prominent (App Store Review Guideline 4.8; the branding page's "Sign in with Google and other third party sign-in options"). The Apple button gets `.id(colorScheme)` so a change of appearance makes a new one, id `signin.apple`. Both are disabled while either runs; a `.cancelled` result clears the busy state and shows nothing.

`SignInErrorText` mapping: `.invalidCredentials` → `signin.error.invalidCredentials`, `.rateLimited` → `signin.error.rateLimited`, `.network` → `signin.error.network`, `.server` → `signin.error.server`, `.localWipePending` → `signin.error.localWipePending`, `.cancelled` → nil, `.switchFromSignedInDevice` → `signin.error.switchFromSignedInDevice`, `.emailInUse` → `signin.error.emailInUse`, `.identityInUse` → `signin.error.identityInUse`, `.reauthRequired` → `signin.error.reauthRequired`, `.providerUnavailable` → `signin.error.providerUnavailable`, `.providerFailed` → `signin.error.providerFailed`, `.switchToGoogleFirst` → `settings.account.delete.switchFirst`; notices `.appleLinkDenied` / `.appleLinkExpired` / `.appleLinkFailed` → `signin.apple.linkDenied` / `signin.apple.linkExpired` / `signin.apple.linkFailed`.

Strings (en | vi | comment). Delete `signin.password` and `signin.button` (no longer used); `signin.email` stays (Settings' email row).

| Key | en | vi | comment |
| --- | --- | --- | --- |
| `signin.subtitle` (changed) | Use the Google account you use with ShellX on your Mac, or sign in with Apple and link this iPhone to your Mac once. | Dùng tài khoản Google bạn dùng với ShellX trên Mac, hoặc đăng nhập bằng Apple rồi nối iPhone này với Mac một lần. | Explains which account to use on the sign-in screen. |
| `signin.error.invalidCredentials` (changed) | ShellX couldn't confirm this sign-in. Try again. | ShellX không xác nhận được lần đăng nhập này. Thử lại. | Sign-in error: the relay refused the Google or Apple sign-in. |
| `signin.google` | Continue with Google | Tiếp tục với Google | Button of the sign-in screen: Google's sign-in. |
| `signin.error.switchFromSignedInDevice` | This email already has a ShellX account. Open ShellX on a device that is still signed in, go to Settings › Account › Switch to Google sign-in, then try again. | Email này đã có tài khoản ShellX. Mở ShellX trên một máy đang đăng nhập, vào Cài đặt › Tài khoản › Chuyển sang đăng nhập Google, rồi thử lại. | Sign-in error: the email belongs to an account that still has a password (S1 §6.3). Same text as the Mac's `remote.signin.error.switchFromSignedInDevice` (plan 1B). |
| `signin.error.emailInUse` | Another ShellX account already uses that Google account's email. | Một tài khoản ShellX khác đã dùng email của tài khoản Google đó. | Switch to Google failed: the Google email belongs to another account. |
| `signin.error.identityInUse` | That Google account already signs in to another ShellX account, or this account already uses another Google account. | Tài khoản Google đó đã đăng nhập vào một tài khoản ShellX khác, hoặc tài khoản này đã dùng một tài khoản Google khác. | Switch to Google failed: the Google account is linked elsewhere, or this account already has another Google account (relay plan 1A). |
| `signin.error.reauthRequired` | Sign in with the Google or Apple account this ShellX account uses, then try again. | Hãy đăng nhập bằng tài khoản Google hoặc Apple mà tài khoản ShellX này dùng, rồi thử lại. | Delete Account: the fresh sign-in was another account or too old. |
| `signin.error.providerUnavailable` | This way of signing in isn't available in this build. | Bản này chưa dùng được cách đăng nhập này. | The build has no Google client ID. |
| `signin.error.providerFailed` | The sign-in didn't finish. Try again. | Đăng nhập chưa xong. Thử lại. | Google or Apple did not finish the sign-in. |
| `signin.apple.linkDenied` | The Mac declined, so this Apple ID isn't linked. | Mac đã từ chối nên Apple ID này chưa được liên kết. | Back on sign-in after Deny on the Mac. |
| `signin.apple.linkExpired` | Linking took too long. Sign in with Apple again. | Liên kết quá lâu. Hãy đăng nhập bằng Apple lại. | Back on sign-in after the link request or its token expired. |
| `signin.apple.linkFailed` | Linking didn't finish. Sign in with Apple again. | Liên kết chưa xong. Hãy đăng nhập bằng Apple lại. | Back on sign-in when the approved link could not be saved. |
| `settings.account.delete.switchFirst` | Switch this iPhone to Google sign-in first, then delete the account here. | Hãy chuyển iPhone này sang đăng nhập Google trước, rồi xoá tài khoản tại đây. | Delete Account on a password session. |

- [ ] **Step 1: Write the failing tests** in `AccountRenderTests` (replace `testSignInWithErrorRenders`, keep the others):

```swift
func testSignInWithErrorRenders() throws {
    try assertRenders(
        SignInView(coordinator: .preview(), expired: false, initialError: .switchFromSignedInDevice), name: "signin-error")
}

func testSignInWithNoticeRenders() throws {
    try assertRenders(SignInView(coordinator: .preview(), expired: false, notice: .appleLinkDenied), name: "signin-notice")
}

func testEveryFailureHasItsOwnWords() {
    let errors: [SignInError] = [
        .invalidCredentials, .rateLimited, .network, .server(code: "x"), .localWipePending, .switchFromSignedInDevice,
        .emailInUse, .identityInUse, .reauthRequired, .providerUnavailable, .providerFailed, .switchToGoogleFirst,
    ]
    let messages = errors.compactMap(SignInErrorText.message(for:))
    XCTAssertEqual(messages.count, errors.count)
    XCTAssertEqual(Set(messages).count, errors.count, "each failure says something different")
    let notices: [SignInNotice] = [.appleLinkDenied, .appleLinkExpired, .appleLinkFailed]
    XCTAssertEqual(Set(notices.map(SignInErrorText.message(for:))).count, 3)
}

func testCancelledHasNoMessage() {
    XCTAssertNil(SignInErrorText.message(for: .cancelled))
}

func testSignInButtonsRender() throws {
    try assertRenders(
        VStack(spacing: 12) { GoogleSignInButton(action: {}); AppleSignInButton(action: {}).frame(height: 44); Spacer() }
            .padding(16).background(Color.appBackground),
        name: "signin-buttons")
    try assertRenders(
        VStack(spacing: 12) { GoogleSignInButton(busy: true, action: {}); Spacer() }.padding(16).background(Color.appBackground),
        name: "signin-buttons-busy")
}

func testGoogleMarkIsTheOfficialSizeOnceBundled() throws {
    try XCTSkipIf(GoogleSignInButton.mark == nil, "Task 9 Step 7 adds the GoogleG asset")
    XCTAssertEqual(GoogleSignInButton.mark?.size, CGSize(width: 20, height: 20))
}

func testGoogleSansIsUsedOnceBundled() throws {
    let font = Bundle.main.url(forResource: "GoogleSans", withExtension: "ttf")
        ?? Bundle.main.url(forResource: "GoogleSans", withExtension: "ttf", subdirectory: "Fonts")
    try XCTSkipIf(font == nil, "Task 9 Step 7 bundles Google Sans")
    XCTAssertNotNil(UIFont(name: "GoogleSans-Regular", size: 14))
    XCTAssertTrue(GoogleSignInButton.labelFont().fontName.hasPrefix("GoogleSans"), GoogleSignInButton.labelFont().fontName)
    XCTAssertEqual(GoogleSignInButton.labelFont().pointSize, 14)
}
```

and add to `ReleaseCheckTests` (Task 8):

```swift
func testMissingGoogleBrandingIsOnlyNotedWhenUnsigned() throws {
    let result = try check(try makeApp())   // no Assets.car, no font
    XCTAssertEqual(result.status, 0, result.output)
    XCTAssertTrue(result.output.contains("no Google “G” mark or Google Sans yet"), result.output)
}
```

- [ ] **Step 2: Run them to see them fail.** Run: `shellx-ios/scripts/dev.sh test app` (expected: `error: cannot find 'SignInErrorText' in scope`, then `==> test app: FAILED`) and `swift test --package-path shellx-ios/Packages/ShellXAppCore --filter ReleaseCheckTests` (expected: `testMissingGoogleBrandingIsOnlyNotedWhenUnsigned` fails, the note is missing).
- [ ] **Step 3: Implement** the screen, the three new files, the RootView argument and the catalog changes above. In `release/mobile/ios.sh`, after Task 8's Google client check:

```bash
  # Google's branding guidelines want the official "G" (asset GoogleG) and Google Sans on the Continue with Google
  # button (contracts §11); without them the button shows its text only.
  local google_mark="" google_font=""
  if [ -f "$app/Assets.car" ] && assetutil --info "$app/Assets.car" 2>/dev/null | grep -Eq '"Name" *: *"GoogleG"'; then google_mark=yes; fi
  if [ -f "$app/GoogleSans.ttf" ]; then google_font=yes; fi
  if [ -z "$google_mark" ] || [ -z "$google_font" ]; then
    if [ "$mode" = "signed" ]; then
      fail+=("lacks Google's sign-in branding (the GoogleG asset or GoogleSans.ttf); see shellx-ios/README.md, Assets")
    else
      note "$label: no Google “G” mark or Google Sans yet: Continue with Google shows its text-only fallback"
    fi
  fi
```

`release/mobile/README.md`, step 2's list gains "- it lacks Google's sign-in branding: the `GoogleG` asset (in `Assets.car`) or `GoogleSans.ttf`;". `shellx-ios/README.md`, end of "Assets": "`GoogleG` is Google's official \"G\", cropped unchanged (20 × 20 pt) from the Light, no-text, Square iOS icons of Google's sign-in bundle (https://developers.google.com/static/identity/images/signin-assets.zip, linked from https://developers.google.com/identity/branding-guidelines). `Fonts/GoogleSans.ttf` is Google Sans (SIL OFL 1.1, `Fonts/GoogleSans-OFL.txt`) from github.com/google/fonts. Both serve only the Continue with Google button, which follows that page. Never replace them with a Google logo from `ios/`, `Packages/` or `Sources/`, or with a drawn one."
- [ ] **Step 4: Run them to see them pass.** Run: `python3 shellx-ios/scripts/check-strings.py`, `swift test --package-path shellx-ios/Packages/ShellXAppCore --filter ReleaseCheckTests`, then `shellx-ios/scripts/dev.sh test app`. Expected: `check-strings: ok (N keys)`; `with 0 failures`; `==> test app: passed`, with `testGoogleMarkIsTheOfficialSizeOnceBundled` and `testGoogleSansIsUsedOnceBundled` skipped.
- [ ] **Step 5: Commit.**

```bash
git add shellx-ios/ShellX/UI/SignIn/SignInView.swift shellx-ios/ShellX/UI/SignIn/GoogleSignInButton.swift shellx-ios/ShellX/UI/SignIn/AppleSignInButton.swift shellx-ios/ShellX/UI/SignIn/SignInErrorText.swift shellx-ios/ShellX/UI/RootView.swift shellx-ios/ShellX/Localizable.xcstrings shellx-ios/ShellXTests/AccountRenderTests.swift release/mobile/ios.sh release/mobile/README.md shellx-ios/README.md shellx-ios/Packages/ShellXAppCore/Tests/ShellXAppCoreTests/ReleaseCheckTests.swift
git commit -m "feat(shellx-ios): sign in with Google or Apple; no password field"
```

- [ ] **Step 6: USER: download Google's sign-in assets and Google Sans** (contracts §11: the user approves this download under Google's terms, the branding page's "Other Guidelines" and https://www.google.com/permissions/; Google Sans is under the SIL Open Font License 1.1 with no Reserved Font Name). The link is in the page's section "Download Pre-Approved Brand Icons". Run:

```bash
! mkdir -p ~/Downloads/shellx-google-signin && curl -fL -o ~/Downloads/shellx-google-signin/signin-assets.zip https://developers.google.com/static/identity/images/signin-assets.zip && shasum -a 256 ~/Downloads/shellx-google-signin/signin-assets.zip
! curl -fL -o ~/Downloads/shellx-google-signin/GoogleSans.ttf 'https://raw.githubusercontent.com/google/fonts/main/ofl/googlesans/GoogleSans%5BGRAD%2Copsz%2Cwght%5D.ttf' && curl -fL -o ~/Downloads/shellx-google-signin/OFL.txt https://raw.githubusercontent.com/google/fonts/main/ofl/googlesans/OFL.txt
```

  On 2026-11-07 the zip's SHA-256 was `ba884069e12093b06bcfd776915081254a7c95094b80d50be2c5dc6bac1c1da1`; another value only means Google updated the bundle, and Step 7 checks that the two files it keeps are still there. The zip holds whole buttons (`iOS/` and `Android + Web/`, PNG @1x–@4x and SVG, themes Light, Dark and Neutral, with and without text, Square and Pill), no bare "G". Then the user says "Google assets downloaded" in the chat. Meanwhile the executor goes on with Task 10 and comes back for Steps 7–8.
- [ ] **Step 7: Add the G and the font.** Keep only the two Light-theme, no-text, Square iOS icons (the official 20 × 20 pt G sits centred at 12–32 pt in each 44 pt icon, so cropping the centre keeps the G's size and colours and drops only the button frame), the font and its licence. Never take another source: no Google logo from `ios/`, `Packages/` or `Sources/`, no drawn or traced one, and not the bundle's SVGs (their gradient G is a `foreignObject` that asset catalogs do not render).

```bash
S=~/Downloads/shellx-google-signin; A=shellx-ios/ShellX/Assets.xcassets/GoogleG.imageset
mkdir -p "$A" shellx-ios/ShellX/Fonts
unzip -p "$S/signin-assets.zip" "iOS/PNG @2x/Light/Theme=Light, Show text=No, Shape=Square, Platform=iOS@2x.png" > "$S/light@2x.png"
unzip -p "$S/signin-assets.zip" "iOS/PNG @3x/Light/Theme=Light, Show text=No, Shape=Square, Platform=iOS@3x.png" > "$S/light@3x.png"
sips -g pixelWidth "$S/light@2x.png" "$S/light@3x.png"   # expected: 88 and 132
sips --cropToHeightWidth 40 40 "$S/light@2x.png" --out "$A/GoogleG@2x.png"
sips --cropToHeightWidth 60 60 "$S/light@3x.png" --out "$A/GoogleG@3x.png"
cp "$S/GoogleSans.ttf" shellx-ios/ShellX/Fonts/GoogleSans.ttf
cp "$S/OFL.txt" shellx-ios/ShellX/Fonts/GoogleSans-OFL.txt
```

  `GoogleG.imageset/Contents.json`:

```json
{
  "images" : [
    { "filename" : "GoogleG@2x.png", "idiom" : "universal", "scale" : "2x" },
    { "filename" : "GoogleG@3x.png", "idiom" : "universal", "scale" : "3x" }
  ],
  "info" : { "author" : "xcode", "version" : 1 },
  "properties" : { "template-rendering-intent" : "original" }
}
```

  `shellx-ios/Config/Info.plist`, after `ShellXGoogleClientID`: `<key>UIAppFonts</key>` with `<array><string>GoogleSans.ttf</string></array>`. If Step 8 finds the font unregistered because the synchronized folder kept the `Fonts/` path, use `Fonts/GoogleSans.ttf` there and in `ios.sh`'s check. Open both PNGs with the Read tool: each must show the G alone on white; if a file is missing from the zip or a crop shows any frame, stop and ask the user. `scripts/shellx/check-ios-license.sh` is not affected: it checks package manifests, `project.pbxproj`, Swift imports, the word Manaflow in text files, symlinks and the shellx-link boundary (`check-ios-license.sh:8-20`); an image set, a font and a licence text are none of these.
- [ ] **Step 8: Verify and commit.** Run `bash scripts/shellx/check-ios-license.sh` (expected `check-ios-license: ok`), `shellx-ios/scripts/dev.sh test app` (expected `==> test app: passed`, `testGoogleMarkIsTheOfficialSizeOnceBundled` and `testGoogleSansIsUsedOnceBundled` now run instead of being skipped), `shellx-ios/scripts/dev.sh test release` (expected `==> test release: passed` without the line `no Google “G” mark or Google Sans yet`) and `shellx-ios/scripts/dev.sh screenshots /tmp/shellx-1c-shots`. Put `signin-buttons-light-en.png` and `signin-buttons-light-vi.png` beside Google's `iOS/PNG @3x/Light/Theme=Light, Show text=Yes, Shape=Pill, Platform=iOS@3x.png` from the zip: same G, padding, font and colours; only the words differ. Then:

```bash
git add shellx-ios/ShellX/Assets.xcassets/GoogleG.imageset shellx-ios/ShellX/Fonts shellx-ios/Config/Info.plist
git commit -m "feat(shellx-ios): Google's G mark and Google Sans on the Continue with Google button"
```

---

### Task 10: "Connect to Your Mac" screen and the phone wording of the pairing instructions

**Files:**
- Create: `shellx-ios/ShellX/UI/Pairing/PairingFlow.swift`
- Modify: `shellx-ios/ShellX/UI/Pairing/PairingSheet.swift` (`PairingSheet` `:7-41` becomes generic; `PairingSheetContent` `:43-79` gains `title` and `intro`; `PairingScanStep` `:171-218` shows `intro`), `shellx-ios/ShellX/UI/RootView.swift` (the `.linkingApple` case), `shellx-ios/ShellX/Localizable.xcstrings`
- Test: Create `shellx-ios/ShellXTests/AppleLinkRenderTests.swift`

**Interfaces:**
- Consumes: Task 5 `AppleLinkModel` (`step`, `begin(uri:)`, `confirm()`, `cancel()`, `close()`), Task 6 `coordinator.appleLink`.
- Produces:

```swift
/// What the pairing sheet drives: pairing a Mac (`PairingModel`) or linking an Apple ID through one (`AppleLinkModel`).
@MainActor protocol PairingFlow: AnyObject, Observable {
    var step: PairingModel.Step { get }
    func begin(uri: String)
    func confirm() async
    func cancel()
}
extension PairingModel: PairingFlow {}
extension AppleLinkModel: PairingFlow {}
struct PairingSheet<Flow: PairingFlow>: View {
    let model: Flow
    let close: () -> Void
    var title = String(localized: "pairing.title")
    var intro: String? = nil
}
// PairingSheetContent gains, after `actions`: `var title = String(localized: "pairing.title")` (its navigation title) and
// `var intro: String? = nil` (body text at the top of the `.idle` step, above the camera).
// RootView: case .linkingApple → `PairingSheet(model: link, close: { link.close() }, title: String(localized: "appleLink.title"),
// intro: String(localized: "appleLink.intro"))` for `coordinator.appleLink`, `LaunchView()` when it is nil.
```

Strings:

| Key | en | vi | comment |
| --- | --- | --- | --- |
| `appleLink.title` | Connect to Your Mac | Kết nối với Mac của bạn | Title of the screen that links an Apple ID to a Mac's account. |
| `appleLink.intro` | This Apple ID isn't linked to a ShellX account yet. Scan the pairing code on your Mac and click Allow there; this Apple ID then signs in to that Mac's account. | Apple ID này chưa gắn với tài khoản ShellX nào. Quét mã ghép cặp trên Mac rồi bấm Đồng ý ở đó; từ đó Apple ID này đăng nhập vào tài khoản của Mac. | Above the scanner of Connect to Your Mac. Allow is the Mac's button. |
| `pairing.instructions` (changed) | On your Mac, open ShellX, right-click “This Mac” and choose Pair Phone… | Trên Mac, mở ShellX, bấm chuột phải vào “Mac này” rồi chọn Ghép cặp điện thoại… | Where to find the pairing QR code on the Mac. “This Mac” and Pair Phone… name items of the Mac app: `remote.phonePairing.menu` from desktop 1.8.0 (contracts §10). |

- [ ] **Step 1: Write the failing tests.**

```swift
import ShellXAppCore
import SwiftUI
import XCTest
@testable import ShellX

@MainActor
final class AppleLinkRenderTests: XCTestCase {
    private func assertRenders(_ view: some View, name: String) throws {
        let images = try SnapshotWriter().write(view, name: name)
        XCTAssertEqual(images.count, 2)
        for image in images { XCTAssertEqual(image.size, SnapshotWriter.size) }
        XCTAssertNotEqual(images.first?.pngData(), images.last?.pngData(), "light and dark renders should differ")
    }

    func testConnectToYourMacRendersEveryStep() throws {
        let title = String(localized: "appleLink.title"), intro = String(localized: "appleLink.intro")
        let steps: [(PairingModel.Step, String)] = [
            (.idle, "apple-link-idle"), (.confirm(machineName: "MacBook Pro"), "apple-link-confirm"),
            (.waitingForMac(machineName: "MacBook Pro"), "apple-link-waiting"), (.failed(.network), "apple-link-failed"),
        ]
        for (step, name) in steps {
            try assertRenders(PairingSheetContent(step: step, camera: .unavailable, title: title, intro: intro), name: name)
        }
    }

    func testInstructionsNoLongerNameTheIPhoneMenuItem() {
        XCTAssertFalse(String(localized: "pairing.instructions").contains("iPhone…"))
    }
}
```

- [ ] **Step 2: Run them to see them fail.** Run: `shellx-ios/scripts/dev.sh test app`. Expected: `error: extra arguments at positions #3, #4 in call` (or `incorrect argument labels`), then `==> test app: FAILED`.
- [ ] **Step 3: Implement** the protocol, the generic sheet, the two properties, the RootView case and the strings.
- [ ] **Step 4: Run them to see them pass.** Run: `python3 shellx-ios/scripts/check-strings.py` then `shellx-ios/scripts/dev.sh test app`. Expected: `check-strings: ok (N keys)`; `==> test app: passed` (`MachinesRenderTests` keeps calling `PairingSheetContent(step:camera:)`).
- [ ] **Step 5: Commit.**

```bash
git add shellx-ios/ShellX/UI/Pairing/PairingFlow.swift shellx-ios/ShellX/UI/Pairing/PairingSheet.swift shellx-ios/ShellX/UI/RootView.swift shellx-ios/ShellX/Localizable.xcstrings shellx-ios/ShellXTests/AppleLinkRenderTests.swift
git commit -m "feat(shellx-ios): Connect to Your Mac after Sign in with Apple; pairing names the Mac's Pair Phone… item"
```

---

### Task 11: Settings › Account: switch to Google, Delete Account…, the one-time banner

**Files:**
- Create: `shellx-ios/ShellX/UI/Settings/AccountActions.swift`, `shellx-ios/ShellX/UI/Settings/DeleteAccountSheet.swift`, `shellx-ios/ShellX/UI/Home/SwitchToGoogleBanner.swift`
- Modify: `shellx-ios/ShellX/UI/Settings/AccountSection.swift` (whole file), `shellx-ios/ShellX/UI/Settings/SettingsView.swift:5-7,22,37`, `shellx-ios/ShellX/UI/SignedInView.swift:19,29-44,50`, `shellx-ios/ShellX/UI/RootView.swift:21-26`, `shellx-ios/ShellX/Localizable.xcstrings`
- Test: Modify `shellx-ios/ShellXTests/AccountRenderTests.swift:29-32`, `shellx-ios/ShellXTests/MicButtonRenderTests.swift:259,267`; Create `shellx-ios/ShellXTests/DeleteAccountRenderTests.swift`

**Interfaces:**
- Consumes: Task 7 (`switchToGoogle()`, `deleteAccount()`), Task 6 (`authMethod`), Task 9 (`SignInErrorText`).
- Produces:

```swift
/// What Settings › Account and the home's banner can do for the signed-in account; nil in the demo.
struct AccountActions {
    var authMethod: AccountAuthMethod
    var signOut: () async -> Void
    var switchToGoogle: () async throws -> Void
    var deleteAccount: () async throws -> Void
}
extension AccountActions {
    /// `authMethod` is `coordinator.authMethod ?? .google`.
    @MainActor init(coordinator: AppCoordinator)
}
struct SettingsView: View { let email: String; let account: AccountActions? }
struct AccountSection: View { let email: String; let account: AccountActions? }
struct DeleteAccountSheet: View {
    enum Step: Equatable { case confirm, switchFirst, working, failed(String) }
    let step: Step
    var delete: () -> Void = {}
    var switchToGoogle: () -> Void = {}
    var close: () -> Void = {}
}
/// The one-time banner over the home of a password session (S1 §6.3b).
struct SwitchToGoogleBanner: View {
    /// Only for a password session, until "Not Now" or a switch.
    static func isShown(authMethod: AccountAuthMethod?, dismissed: Bool) -> Bool
    var switching = false
    var error: String? = nil
    let switchNow: () -> Void
    let dismiss: () -> Void
}
// SignedInView: `let account: AccountActions?` replaces `let signOut`; the banner goes in
// `.safeAreaInset(edge: .top, spacing: 0)` of the root Group (FirstMacView or WorkspaceListView) when
// `SwitchToGoogleBanner.isShown(authMethod: account?.authMethod, dismissed: bannerDismissed)`, with
// `@AppStorage("shellx.switchToGoogleBannerDismissed") private var bannerDismissed = false`; SettingsView(email: email, account: account).
// RootView: SignedInView(..., account: AccountActions(coordinator: coordinator)).
```

Account section, in order: the email row (as today); for a password session a "Switch to Google sign-in" row (a spinner while it runs, `SignInErrorText` below it in `StatusError` on failure, nothing for `.cancelled`) and the section footer `settings.account.switchToGoogle.detail`; "Sign out" (destructive, its alert as today); "Delete Account…" (destructive) opening `DeleteAccountSheet` at `.switchFirst` for a password session, else `.confirm`. With `account == nil` (the demo) only the email row shows.

`DeleteAccountSheet`: a warning symbol in `StatusError`; title `settings.account.delete.title`; text `settings.account.delete.message` (`.confirm`, `.working`, `.failed`) or `settings.account.delete.switchFirst` (`.switchFirst`); the failure text in `StatusError` above the buttons (`.failed`); primary button `settings.account.delete.button` with `SecondaryButtonStyle(color: Color("StatusError"))` running `delete`, or for `.switchFirst` `settings.account.switchToGoogle` with `PrimaryButtonStyle` running `switchToGoogle`; `common.cancel` running `close`; `.working` shows a spinner with `settings.account.delete.deleting` and disables the buttons; `.presentationDetents([.medium, .large])`. `AccountSection` drives the steps: delete or switch → `.working`; a thrown `SignInError` → `.failed(message)`, or back to the previous step for `.cancelled`; success needs nothing (the coordinator signs out or restarts the hub, and these screens go away).

Strings:

| Key | en | vi | comment |
| --- | --- | --- | --- |
| `settings.account.switchToGoogle` | Switch to Google sign-in | Chuyển sang đăng nhập Google | Settings › Account row and banner title for a password session (S1 §6.3b); same words as the Mac's `remote.signin.switch.title` (plan 1B). |
| `settings.account.switchToGoogle.detail` | Password sign-in is going away. Switching keeps your Macs and history. | Sắp bỏ đăng nhập bằng mật khẩu. Chuyển sang Google vẫn giữ các Mac và lịch sử của bạn. | Footer of the Account section and text of the banner for a password session. |
| `settings.account.delete` | Delete Account… | Xoá tài khoản… | Destructive Settings › Account row; opens the confirmation. |
| `settings.account.delete.title` | Delete your ShellX account? | Xoá tài khoản ShellX? | Title of the account deletion sheet. |
| `settings.account.delete.message` | This deletes your ShellX account for good. Every Mac and phone signed in to it is signed out, its pairings and shared sessions end, and this iPhone's history is removed. To confirm, you sign in once more. | Thao tác này xoá vĩnh viễn tài khoản ShellX của bạn. Mọi Mac và điện thoại đang đăng nhập bị đăng xuất, các ghép cặp và phiên chia sẻ kết thúc, lịch sử trên iPhone này bị xoá. Để xác nhận, bạn đăng nhập lại một lần. | What deleting the account does (S1 §6.8). |
| `settings.account.delete.button` | Delete Account | Xoá tài khoản | Destructive button of the deletion sheet. |
| `settings.account.delete.deleting` | Deleting… | Đang xoá… | While the account is being deleted. |
| `switchToGoogle.banner.switch` | Switch | Chuyển | Banner button: switch to Google sign-in now. |
| `switchToGoogle.banner.later` | Not Now | Để sau | Banner button: hide the banner for good (Settings keeps the row). |

- [ ] **Step 1: Write the failing tests.** In `AccountRenderTests` replace `testSettingsRenders` and add:

```swift
private func actions(_ method: AccountAuthMethod) -> AccountActions {
    AccountActions(authMethod: method, signOut: {}, switchToGoogle: {}, deleteAccount: {})
}

func testSettingsRenders() throws {
    try assertRenders(NavigationStack { SettingsView(email: "phu@example.com", account: actions(.google)) }, name: "settings")
}

func testSettingsOfAPasswordSessionOfferTheSwitch() throws {
    try assertRenders(NavigationStack { SettingsView(email: "phu@example.com", account: actions(.password)) }, name: "settings-password")
}

func testSettingsInTheDemoShowOnlyTheEmail() throws {
    try assertRenders(NavigationStack { SettingsView(email: "demo@shellx.pro", account: nil) }, name: "settings-demo")
}

func testSwitchBannerRenders() throws {
    try assertRenders(VStack(spacing: 0) { SwitchToGoogleBanner(switchNow: {}, dismiss: {}); Spacer() }, name: "switch-banner")
    try assertRenders(
        VStack(spacing: 0) { SwitchToGoogleBanner(error: SignInErrorText.message(for: .emailInUse), switchNow: {}, dismiss: {}); Spacer() },
        name: "switch-banner-error")
}

func testSwitchBannerShowsOnlyForPasswordSessionsUntilDismissed() {
    XCTAssertTrue(SwitchToGoogleBanner.isShown(authMethod: .password, dismissed: false))
    XCTAssertFalse(SwitchToGoogleBanner.isShown(authMethod: .password, dismissed: true))
    XCTAssertFalse(SwitchToGoogleBanner.isShown(authMethod: .google, dismissed: false))
    XCTAssertFalse(SwitchToGoogleBanner.isShown(authMethod: .apple, dismissed: false))
    XCTAssertFalse(SwitchToGoogleBanner.isShown(authMethod: nil, dismissed: false))
}
```

Create `DeleteAccountRenderTests.swift` (same `assertRenders` helper as `AccountRenderTests`):

```swift
func testDeleteSheetRendersEveryStep() throws {
    let steps: [(DeleteAccountSheet.Step, String)] = [
        (.confirm, "delete-account-confirm"), (.switchFirst, "delete-account-switch-first"), (.working, "delete-account-working"),
        (.failed(SignInErrorText.message(for: .reauthRequired) ?? ""), "delete-account-failed"),
    ]
    for (step, name) in steps { try assertRenders(DeleteAccountSheet(step: step), name: name) }
}
```

In `MicButtonRenderTests.swift:259,267` the calls become `SettingsView(email: "phu@example.com", account: nil)`.
- [ ] **Step 2: Run them to see them fail.** Run: `shellx-ios/scripts/dev.sh test app`. Expected: `error: cannot find 'AccountActions' in scope`, then `==> test app: FAILED`.
- [ ] **Step 3: Implement** the three files, the section, the view changes and the strings.
- [ ] **Step 4: Run them to see them pass.** Run: `python3 shellx-ios/scripts/check-strings.py` then `shellx-ios/scripts/dev.sh test app`. Expected: `check-strings: ok (N keys)`; `==> test app: passed`.
- [ ] **Step 5: Commit.**

```bash
git add shellx-ios/ShellX/UI/Settings/AccountActions.swift shellx-ios/ShellX/UI/Settings/DeleteAccountSheet.swift shellx-ios/ShellX/UI/Home/SwitchToGoogleBanner.swift shellx-ios/ShellX/UI/Settings/AccountSection.swift shellx-ios/ShellX/UI/Settings/SettingsView.swift shellx-ios/ShellX/UI/SignedInView.swift shellx-ios/ShellX/UI/RootView.swift shellx-ios/ShellX/Localizable.xcstrings shellx-ios/ShellXTests/AccountRenderTests.swift shellx-ios/ShellXTests/MicButtonRenderTests.swift shellx-ios/ShellXTests/DeleteAccountRenderTests.swift
git commit -m "feat(shellx-ios): Settings › Account switches to Google and deletes the account"
```

---

### Task 12: The demo's Mac moves to a ShellXDemo package target

Paths start at `shellx-ios/Packages/ShellXAppCore/` unless they start at the repo root.

**Files:**
- Modify: `Package.swift`, `scripts/shellx/check-ios-license.sh:51-62` (repo root)
- Move (`git mv`): `Sources/ShellXAppTestSupport/{FakeMac,FakeMacChat,FakeMacDemoScript,FakeMacFeed,FakeMacFleet,FakeMacSessions,FakeMacWorkspaces}.swift` → `Sources/ShellXDemo/`
- Create: `Sources/ShellXDemo/DemoRelay.swift`, `Sources/ShellXDemo/DemoSecretStore.swift`, `Sources/ShellXAppTestSupport/Exports.swift`
- Test: Modify `Tests/ShellXAppCoreTests/LicenseBoundaryTests.swift`; Create `Tests/ShellXAppCoreTests/DemoRelayTests.swift`

**Interfaces:**
- Consumes: Task 4 `RelayAccountCalling` (all methods).
- Produces (module `ShellXDemo`; the moved `FakeMac`, `FakeMacFleet`, `FakeMacDemoScript` keep their names and APIs):

```swift
/// The demo's relay: no network. Lists the demo Macs it was given or paired, pairs a demo Mac's code after
/// `approvalDelay`, and refuses every account call.
public actor DemoRelay: RelayAccountCalling {
    public static let refusal = RelayAPIError.http(status: 403, code: "demo")
    public init(paired: [PairedMachine], pairableMachineIDs: Set<String>, approvalDelay: Duration,
                sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) })
}
/// The demo's secrets, in memory only: nothing reaches the Keychain.
public final class DemoSecretStore: SecretStore, @unchecked Sendable { public init() }
```

`DemoRelay`: `machines(token:)` lists one grant per paired Mac in pairing order (`grantID` `"grant-<machineID>"`, platform `"macos"`, online `true`, its `linkSlot`, fingerprint `"demo"`); `unpair` removes by `grantID`; `pair` parses the offer (its error is thrown), refuses a machine ID outside `pairableMachineIDs` with `RelayAPIError.http(status: 404, code: "machine_not_found")`, waits `approvalDelay`, lists the Mac and returns the `PairedMachine` of the offer; `logout` and `setPushToken` do nothing; `login`, `nonce`, `signInWithGoogle`, `linkGoogle`, `signInWithApple`, `linkApple`, `deleteAccount` throw `DemoRelay.refusal`.

`Package.swift`: product `.library(name: "ShellXDemo", targets: ["ShellXDemo"])` between the two existing products; target `ShellXDemo` depending on `"ShellXAppCore"` and the four shellx-link products, with the comment `// The in-app demo ("Try without an account", S1 §6.6): Macs running inside the app, a relay and a secret store that never leave memory. Ships in Release.`; `ShellXAppTestSupport` gains the dependency `"ShellXDemo"` and the comment `// Fakes for tests and previews; Release.xcconfig keeps it out of the App Store build.`

`Exports.swift`:

```swift
// The demo's Mac (FakeMac, FakeMacFleet, FakeMacDemoScript) lives in ShellXDemo, which ships in Release; tests
// keep reaching it through this module.
@_exported import ShellXDemo
```

`check-ios-license.sh`: above `ALLOWED_MODULES=` add `# ShellXDemo: the app's own demo target (shellx-ios/Packages/ShellXAppCore, "Try without an account").`; the last allowlist line becomes `ShellXAppCore ShellXDemo ShellXAppTestSupport ShellX`.

- [ ] **Step 1: Write the failing tests.** Add to `LicenseBoundaryTests`:

```swift
func testDemoModuleImportPasses() throws {
    let root = try makeCleanTree()
    try ScriptRunner.write("import ShellXDemo\n", to: "shellx-ios/ShellX/Demo.swift", under: root)
    let result = try check(root)
    XCTAssertEqual(result.status, 0, result.output)
}
```

Create `DemoRelayTests.swift`:

```swift
import Foundation
import ShellXAppTestSupport
import ShellXLinkAccount
import ShellXLinkCore
import XCTest
@testable import ShellXAppCore

final class DemoRelayTests: XCTestCase {
    private let a = PairedMachine(machineID: "mac-a", name: "Mac A", linkSlot: "slot-a", hostKey: Data(repeating: 1, count: 32))
    private func offer(_ id: String) -> PairingOffer {
        PairingOffer.make(machineID: id, linkSlot: "slot-\(id)", hostKey: Data(repeating: 2, count: 32), machineName: "Mac \(id)")
    }

    func testListsPairsAndUnpairsTheDemoMacs() async throws {
        let relay = DemoRelay(paired: [a], pairableMachineIDs: ["mac-b"], approvalDelay: .zero)
        let first = try await relay.machines(token: "demo-token")
        XCTAssertEqual(first.map(\.machineID), ["mac-a"])
        let paired = try await relay.pair(offerURI: offer("mac-b").uri, clientKey: Data(repeating: 3, count: 32), token: "demo-token")
        XCTAssertEqual(paired, PairedMachine(machineID: "mac-b", name: "Mac mac-b", linkSlot: "slot-mac-b", hostKey: Data(repeating: 2, count: 32)))
        let both = try await relay.machines(token: "demo-token")
        XCTAssertEqual(both.map(\.machineID), ["mac-a", "mac-b"])
        try await relay.unpair(grantID: "grant-mac-a", token: "demo-token")
        let left = try await relay.machines(token: "demo-token")
        XCTAssertEqual(left.map(\.machineID), ["mac-b"])
    }

    func testCodesOfOtherMacsAreRefused() async {
        let relay = DemoRelay(paired: [], pairableMachineIDs: ["mac-b"], approvalDelay: .zero)
        do { _ = try await relay.pair(offerURI: offer("mac-z").uri, clientKey: Data(repeating: 3, count: 32), token: "t"); XCTFail() } catch {
            XCTAssertEqual(error as? RelayAPIError, .http(status: 404, code: "machine_not_found"))
        }
    }

    func testEveryAccountCallIsRefused() async {
        let relay = DemoRelay(paired: [], pairableMachineIDs: [], approvalDelay: .zero)
        let key = Data(repeating: 3, count: 32)
        let calls: [(String, @Sendable () async throws -> Void)] = [
            ("login", { _ = try await relay.login(email: "a", password: "b", deviceName: "p", clientKey: key) }),
            ("nonce", { _ = try await relay.nonce() }),
            ("signInWithGoogle", { _ = try await relay.signInWithGoogle(idToken: "i", nonce: "n", deviceName: "p", clientKey: key) }),
            ("linkGoogle", { _ = try await relay.linkGoogle(idToken: "i", nonce: "n", token: "t") }),
            ("signInWithApple", { _ = try await relay.signInWithApple(identityToken: "i", authorizationCode: "c", nonce: "n", deviceName: "p", clientKey: key) }),
            ("linkApple", { _ = try await relay.linkApple(offerURI: "u", linkToken: "l", clientKey: key) }),
            ("deleteAccount", { try await relay.deleteAccount(idToken: "i", nonce: "n", token: "t") }),
        ]
        for (name, call) in calls {
            do { try await call(); XCTFail(name) } catch { XCTAssertEqual(error as? RelayAPIError, DemoRelay.refusal, name) }
        }
    }

    func testDemoSecretsStayInMemory() throws {
        let store = DemoSecretStore()
        try store.write(Data("x".utf8), for: .session)
        XCTAssertEqual(try store.read(.session), Data("x".utf8))
        try store.delete(.session)
        XCTAssertNil(try store.read(.session))
    }
}
```

- [ ] **Step 2: Run them to see them fail.** Run: `swift test --package-path shellx-ios/Packages/ShellXAppCore --filter 'DemoRelayTests|LicenseBoundaryTests'`. Expected: build error `cannot find 'DemoRelay' in scope` (with the target in place but before the allowlist line, `testDemoModuleImportPasses` and `testRepositoryPasses` fail with `imports ShellXDemo, which is not on the allowlist`).
- [ ] **Step 3: Implement**: the manifest, the moves, the two new types, `Exports.swift`, the allowlist line.
- [ ] **Step 4: Run them to see them pass.** Run: `bash scripts/shellx/check-ios-license.sh` (expected `check-ios-license: ok`), `shellx-ios/scripts/dev.sh test core` (expected `==> test core: passed`), `shellx-ios/scripts/dev.sh test app` (expected `==> test app: passed`: app tests reach `FakeMac` through `ShellXAppTestSupport`), `shellx-ios/scripts/dev.sh test release` (expected `==> test release: passed`: nothing in Release imports ShellXDemo yet).
- [ ] **Step 5: Commit.**

```bash
git add -A shellx-ios/Packages/ShellXAppCore/Sources/ShellXDemo shellx-ios/Packages/ShellXAppCore/Sources/ShellXAppTestSupport
git add shellx-ios/Packages/ShellXAppCore/Package.swift scripts/shellx/check-ios-license.sh shellx-ios/Packages/ShellXAppCore/Tests/ShellXAppCoreTests/LicenseBoundaryTests.swift shellx-ios/Packages/ShellXAppCore/Tests/ShellXAppCoreTests/DemoRelayTests.swift
git commit -m "refactor(shellx-ios): the demo's Mac moves to a ShellXDemo package target"
```

---

### Task 13: "Try without an account" in every build

**Files:**
- Move (`git mv`): `shellx-ios/ShellX/Debug/DemoComposition.swift` → `shellx-ios/ShellX/Demo/DemoComposition.swift`, `shellx-ios/ShellX/Debug/DemoScript.swift` → `shellx-ios/ShellX/Demo/DemoScript.swift` (drop their `#if DEBUG` / `#endif`; `import ShellXDemo` instead of `ShellXAppTestSupport`)
- Create: `shellx-ios/ShellX/Demo/DemoSession.swift`, `shellx-ios/ShellX/Demo/DemoRootView.swift`, `shellx-ios/ShellX/Demo/DemoBanner.swift`
- Modify: `shellx-ios/ShellX/AppGraph.swift:10-21`, `shellx-ios/ShellX/ShellXApp.swift:9,18-19`, `shellx-ios/ShellX/UI/RootView.swift`, `shellx-ios/ShellX/UI/SignedInView.swift`, `shellx-ios/ShellX/UI/Onboarding/FirstMacView.swift:6,39-46`, `shellx-ios/ShellX/UI/SignIn/SignInView.swift`, `shellx-ios/ShellX.xcodeproj/project.pbxproj`, `shellx-ios/Config/Release.xcconfig:16-20`, `release/mobile/ios.sh:30-31,140-143`, `release/mobile/README.md:32-35,67-69`, `shellx-ios/README.md:68-73,84-88`, `shellx-ios/ShellX/Localizable.xcstrings`, `shellx-ios/scripts/strings-identity.txt`
- Test: Create `shellx-ios/ShellXTests/DemoSessionTests.swift`, `shellx-ios/ShellXTests/DemoRenderTests.swift`; Modify `shellx-ios/Packages/ShellXAppCore/Tests/ShellXAppCoreTests/ReleaseCheckTests.swift`, `shellx-ios/ShellXTests/MachinesRenderTests.swift`, `shellx-ios/ShellXTests/AccountRenderTests.swift`

**Interfaces:**
- Consumes: Task 12 (`DemoRelay`, `DemoSecretStore`, `FakeMac`, `FakeMacFleet`), Task 11 (`SignedInView(account:)`), Task 9 (`SignInView`).
- Produces:

```swift
// AppGraph gains: /// Undoes `prepare` when the graph is dropped (the demo's Exit).
var teardown: @MainActor () async -> Void = {}
// DemoComposition (no longer Debug-only):
static func make(approvalDelay: Duration = .seconds(2), pasteboard: UIPasteboard? = .general, runsScript: Bool = true,
                 history historyDirectory: URL = defaultHistory) -> AppGraph
// vault over DemoSecretStore(); relay DemoRelay(paired: [first.machine], pairableMachineIDs: [second.machine.machineID],
// approvalDelay:); identity left at its default; prepare seeds StoredSession(..., email: "demo@shellx.pro", authMethod: .google)
// and the first Mac, and writes the second Mac's code only when `pasteboard` is non-nil; teardown stops the script and the hub.
// DemoScript gains: func stop()   // cancels the playing task
/// "Try without an account": the demo over the real app until Exit.
@MainActor @Observable final class DemoSession {
    private(set) var graph: AppGraph?
    init(make: @escaping @MainActor () -> AppGraph = { DemoComposition.make(pasteboard: nil) })
    func start() async   // no-op while one runs; graph = make(); await prepare(); await coordinator.launch()
    func exit() async    // graph = nil first, then await the old graph's teardown()
}
/// The "Demo · Exit" banner over the demo account's signed-in screens.
struct DemoRootView: View { let graph: AppGraph; let exit: () -> Void }
struct DemoBanner: View { let exit: () -> Void }
FirstMacView(pair: @escaping () -> Void, tryDemo: (() -> Void)? = nil)
SignInView(coordinator:expired:notice:startDemo: (() -> Void)? = nil, initialError:)
RootView: var startDemo: (() -> Void)? = nil       // to SignInView and SignedInView
SignedInView: var startDemo: (() -> Void)? = nil   // to FirstMacView(tryDemo:)
```

- `DemoRootView`: `VStack(spacing: 0) { DemoBanner(exit: exit); … }`; below the banner, while `graph.coordinator.phase` is `.signedIn(email)` and the hub is loaded with its scope, `SignedInView(scope:email:inbox: <its own PairingInbox()>, pushTaps: PushTapInbox(), push: nil, account: nil, startDemo: nil).id(ObjectIdentifier(hub))`, else `LaunchView()`.
- `DemoBanner`: `demo.banner.title` (headline, its accessibility label `demo.banner.label`), a `·`, and a button `demo.banner.exit`; `AccentText` on its 14 % tint (as `SecondaryButtonStyle`), min height 44, full width; ids `demo.banner`, `demo.exit`.
- `SignInView` adds, after the Apple button, a plain text button `signin.demo` (`AccentText`, min height 44, id `signin.demo`) when `startDemo` is non-nil; `FirstMacView` adds one `firstMac.demo` under its scan button (id `firstMac.demo`) when `tryDemo` is non-nil.
- `ShellXApp`: `@State private var demo = DemoSession()`; the window shows `DemoRootView(graph:exit: { Task { await demo.exit() } })` while `demo.graph` is set, else `RootView(…, startDemo: { Task { await demo.start() } })`, inside one `Group` that keeps today's modifiers. The `SHELLX_DEMO` switch of `AppComposition.make()` stays under `#if DEBUG`.

`project.pbxproj` (the app target links the new product):

```text
/* PBXBuildFile, after the ShellXAppTestSupport line (line 11) */
		5E11A0000000000000000029 /* ShellXDemo in Frameworks */ = {isa = PBXBuildFile; productRef = 5E11A0000000000000000028 /* ShellXDemo */; };
/* the app's Frameworks phase files (after line 54) */
				5E11A0000000000000000029 /* ShellXDemo in Frameworks */,
/* the ShellX target's packageProductDependencies (after line 122) */
				5E11A0000000000000000028 /* ShellXDemo */,
/* XCSwiftPackageProductDependency section, after the ShellXAppCore entry (line 322) */
		5E11A0000000000000000028 /* ShellXDemo */ = {
			isa = XCSwiftPackageProductDependency;
			package = 5E11A0000000000000000023 /* XCLocalSwiftPackageReference "Packages/ShellXAppCore" */;
			productName = ShellXDemo;
		};
```

`release/mobile/ios.sh`:

```bash
# Names that exist only in Debug builds: the test fakes and the Debug demo's launch switch. The in-app demo
# (ShellXDemo: FakeMac, DemoRelay, DemoComposition) ships on purpose ("Try without an account").
DEBUG_ONLY_NAMES='FakeRelayAccount|FakeIdentityProvider|InMemorySecretStore|FakeTranscriber|FakeVoicePermissions|SHELLX_DEMO|ShellXAppTestSupport'
```

and the comment at `:140-143` says: the test fakes stay out of the App Store build because `Release.xcconfig` leaves `ShellXAppTestSupport` out of the link and the `SHELLX_DEMO` switch is under `#if DEBUG`; Swift keeps type names in a stripped binary, so every Mach-O file is searched for them. `Release.xcconfig:16-20` says the same of `ShellXAppTestSupport` ("FakeRelayAccount, FakeIdentityProvider, InMemorySecretStore and the other test fakes serve tests and previews only; the in-app demo is ShellXDemo, which ships").

Docs, exact replacements:
- `release/mobile/README.md:32-35` → "   - any Mach-O file in it contains Debug-only code: a test fake (`FakeRelayAccount`, `FakeIdentityProvider`, `InMemorySecretStore`, `FakeTranscriber`, `FakeVoicePermissions`), anything from `ShellXAppTestSupport`, or the Debug demo switch `SHELLX_DEMO`. `Release.xcconfig` leaves `ShellXAppTestSupport` out of the link. The in-app demo (`ShellXDemo`, "Try without an account") ships on purpose."
- `release/mobile/README.md:67-69` → "- **App Review.** Sign-in is Google or Apple only, so there is no demo account to give. The review notes say: \"Without a Mac running ShellX, tap “Try without an account” on the sign-in screen: it opens a sample Mac with workspaces, agent sessions and requests waiting for you. Full use needs a Mac running ShellX (https://shellx.pro). To delete an account: Settings › Account › Delete Account….\""
- `shellx-ios/README.md:71-72`: the Debug-only list becomes "(the test fakes such as `FakeRelayAccount`, `FakeIdentityProvider` and `InMemorySecretStore`, anything from `ShellXAppTestSupport`, the `SHELLX_DEMO` switch)".
- `shellx-ios/README.md:84-88` (the "Demo mode" section body) → "\"Try without an account\" (sign-in screen) and \"Try with a sample Mac\" (first-Mac screen) open the demo in every build, App Store builds included: a fake account paired with \"Mac giả\", a Mac running inside the app (`Packages/ShellXAppCore/Sources/ShellXDemo`), with pending requests, agent sessions and chat. A \"Demo · Exit\" banner stays on top. The demo never calls the relay or the Keychain and keeps its history in `Application Support/ShellXDemo`. `dev.sh sim --demo` (or `device --demo`) launches a Debug build straight into it with `SHELLX_DEMO=1`, without the banner."

Strings (add `demo.banner.title` to `shellx-ios/scripts/strings-identity.txt`):

| Key | en | vi | comment |
| --- | --- | --- | --- |
| `signin.demo` | Try without an account | Xem thử không cần tài khoản | Text button of the sign-in screen: opens the demo with a sample Mac. |
| `firstMac.demo` | Try with a sample Mac | Xem thử với một Mac mẫu | Text button of the first-Mac screen: opens the demo. |
| `demo.banner.title` | Demo | Demo | Banner over every demo screen. Same word in Vietnamese. |
| `demo.banner.exit` | Exit | Thoát | Banner button: leaves the demo. |
| `demo.banner.label` | Demo with a sample Mac. Nothing is sent. | Bản xem thử với một Mac mẫu. Không gửi gì đi. | VoiceOver label of the demo banner. |

- [ ] **Step 1: Write the failing tests.** Add to `ReleaseCheckTests`:

```swift
func testDemoIsPartOfTheRelease() throws {
    let names = "FakeMac FakeMacFleet FakeMacDemoScript DemoComposition DemoScript DemoSession DemoRelay DemoSecretStore ShellXDemo"
    let result = try check(try makeApp(names: names))
    XCTAssertEqual(result.status, 0, result.output)
}

func testDebugOnlyNamesAreRefused() throws {
    for name in ["FakeRelayAccount", "FakeIdentityProvider", "InMemorySecretStore", "FakeTranscriber", "FakeVoicePermissions", "SHELLX_DEMO", "ShellXAppTestSupport"] {
        let result = try check(try makeApp(names: name))
        XCTAssertEqual(result.status, 1, name)
        XCTAssertTrue(result.output.contains("contains Debug-only code: \(name)"), result.output)
    }
}
```

Create `DemoSessionTests.swift`:

```swift
import ShellXAppCore
import ShellXLinkAccount
import XCTest
@testable import ShellX

@MainActor
final class DemoSessionTests: XCTestCase {
    private func eventually(_ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(10)
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }
    private func makeSession(runsScript: Bool = false) -> DemoSession {
        let history = FileManager.default.temporaryDirectory.appendingPathComponent("demo-session-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: history) }
        return DemoSession(make: { DemoComposition.make(approvalDelay: .zero, pasteboard: nil, runsScript: runsScript, history: history) })
    }

    func testStartSignsInToTheDemoAccountWithTheSampleMac() async throws {
        let session = makeSession()
        addTeardownBlock { @MainActor in await session.exit() }
        await session.start()
        let graph = try XCTUnwrap(session.graph)
        XCTAssertEqual(graph.coordinator.phase, .signedIn(email: "demo@shellx.pro"))
        XCTAssertEqual(graph.coordinator.authMethod, .google, "no switch banner in the demo")
        XCTAssertNil(graph.push)
        XCTAssertNil(graph.updatePrompt)
        let hub = try XCTUnwrap(graph.coordinator.hub)
        let online = await eventually { hub.machines.first?.state == .online }
        XCTAssertTrue(online, "\(hub.machines.map(\.state))")
        XCTAssertEqual(hub.machines.map(\.name), [DemoComposition.firstName])
    }

    func testStartingTwiceKeepsOneDemo() async throws {
        let session = makeSession()
        addTeardownBlock { @MainActor in await session.exit() }
        await session.start()
        let first = try XCTUnwrap(session.graph?.coordinator)
        await session.start()
        XCTAssertTrue(session.graph?.coordinator === first)
    }

    func testExitStopsTheDemo() async throws {
        let session = makeSession(runsScript: true)
        await session.start()
        let hub = try XCTUnwrap(session.graph?.coordinator.hub)
        await session.exit()
        XCTAssertNil(session.graph)
        do {
            try await hub.add(PairedMachine(machineID: "x", name: "x", linkSlot: "x", hostKey: Data(repeating: 0, count: 32)))
            XCTFail("the demo's hub still runs")
        } catch { XCTAssertEqual(error as? MachineHub.AddError, .notSignedIn) }
    }
}
```

Create `DemoRenderTests.swift` (same `assertRenders` helper as `AccountRenderTests`, with a `settle` argument passed to `SnapshotWriter().write(_:name:settle:)`):

```swift
func testDemoBannerRenders() throws {
    try assertRenders(VStack(spacing: 0) { DemoBanner(exit: {}); Spacer() }, name: "demo-banner")
}

func testDemoHomeRenders() async throws {
    let history = FileManager.default.temporaryDirectory.appendingPathComponent("demo-render-\(UUID().uuidString)", isDirectory: true)
    let session = DemoSession(make: { DemoComposition.make(approvalDelay: .zero, pasteboard: nil, runsScript: true, history: history) })
    addTeardownBlock { @MainActor in await session.exit(); try? FileManager.default.removeItem(at: history) }
    await session.start()
    let graph = try XCTUnwrap(session.graph)
    let hub = try XCTUnwrap(graph.coordinator.hub)
    let deadline = ContinuousClock.now + .seconds(10)
    while ContinuousClock.now < deadline, hub.workspaceRows(machineID: hub.machines.first?.id ?? "").count < 4 {
        try await Task.sleep(for: .milliseconds(10))
    }
    try assertRenders(DemoRootView(graph: graph, exit: {}), name: "demo-home", settle: 0.5)
}
```

Add `testFirstMacWithDemoRenders` to `MachinesRenderTests` (`NavigationStack { FirstMacView(pair: {}, tryDemo: {}) }`, name `first-mac-demo`) and `testSignInWithDemoRenders` to `AccountRenderTests` (`SignInView(coordinator: .preview(), expired: false, startDemo: {})`, name `signin-demo`).
- [ ] **Step 2: Run them to see them fail.** Run: `swift test --package-path shellx-ios/Packages/ShellXAppCore --filter ReleaseCheckTests` (expected: `testDemoIsPartOfTheRelease` fails with `contains Debug-only code: DemoComposition DemoScript FakeMac`, `testDebugOnlyNamesAreRefused` fails for `FakeIdentityProvider`) and `shellx-ios/scripts/dev.sh test app` (expected: `error: cannot find 'DemoSession' in scope`, `==> test app: FAILED`).
- [ ] **Step 3: Implement** everything listed above.
- [ ] **Step 4: Run them to see them pass.** Run the two commands of Step 2, then `python3 shellx-ios/scripts/check-strings.py`, `bash scripts/shellx/check-ios-license.sh` and `shellx-ios/scripts/dev.sh test release`. Expected: `with 0 failures`; `==> test app: passed` (the existing `DemoCompositionTests` stay green); `check-strings: ok (N keys)`; `check-ios-license: ok`; `==> test release: passed` with `no Debug-only code in N Mach-O files`.
- [ ] **Step 5: Commit.**

```bash
git add -A shellx-ios/ShellX/Demo   # `git mv` already staged the removal of ShellX/Debug
git add shellx-ios/ShellX/AppGraph.swift shellx-ios/ShellX/ShellXApp.swift shellx-ios/ShellX/UI/RootView.swift shellx-ios/ShellX/UI/SignedInView.swift shellx-ios/ShellX/UI/Onboarding/FirstMacView.swift shellx-ios/ShellX/UI/SignIn/SignInView.swift shellx-ios/ShellX.xcodeproj/project.pbxproj shellx-ios/Config/Release.xcconfig release/mobile/ios.sh release/mobile/README.md shellx-ios/README.md shellx-ios/ShellX/Localizable.xcstrings shellx-ios/scripts/strings-identity.txt shellx-ios/ShellXTests/DemoSessionTests.swift shellx-ios/ShellXTests/DemoRenderTests.swift shellx-ios/ShellXTests/MachinesRenderTests.swift shellx-ios/ShellXTests/AccountRenderTests.swift shellx-ios/Packages/ShellXAppCore/Tests/ShellXAppCoreTests/ReleaseCheckTests.swift
git commit -m "feat(shellx-ios): Try without an account opens the demo in every build"
```

---

### Task 14: Verify and hand off

- [ ] **Step 1: Full checks** (one simulator run at a time, see Global Constraints):
  - `swift test --package-path shellx-link` → `with 0 failures`
  - `bash scripts/shellx/check-link-license.sh` → exit 0
  - `bash scripts/shellx/check-ios-license.sh` → `check-ios-license: ok`
  - `python3 shellx-ios/scripts/check-strings.py` → `check-strings: ok (N keys)`
  - `shellx-ios/scripts/dev.sh test all` → `==> test all: passed` (the release part prints the placeholder note until Task 8 Step 5 is done)
  - `shellx-ios/scripts/dev.sh screenshots /tmp/shellx-1c-shots` → `screenshots written to /tmp/shellx-1c-shots`. Open every new PNG (`signin*`, `apple-link-*`, `settings*`, `switch-banner*`, `delete-account-*`, `demo-*`, `first-mac-demo`) in `en` and `vi`, light and dark; fix clipped or overlapping text, a missing translation or a button that cannot be read, then rerun.
  - `python3 scripts/verify-local.py` → last line starts with `PASSED:`.
- [ ] **Step 2: Localization audit** (CLAUDE.md, `skills/cmux-localization` checklist applied to the iPhone catalog): list every key added, changed or removed in Tasks 9–11 and 13; for each, show its `en` and `vi` with `python3 -c 'import json; d=json.load(open("shellx-ios/ShellX/Localizable.xcstrings")); [print(k, "|", v["localizations"]["en"]["stringUnit"]["value"], "|", v["localizations"]["vi"]["stringUnit"]["value"]) for k, v in d["strings"].items() if k.startswith(("signin.", "appleLink.", "settings.account.", "switchToGoogle.", "demo.", "firstMac.demo", "pairing.instructions"))]'`; run `grep -rnE '(Text|Button|Label)\(\s*"' shellx-ios/ShellX` (expected: no output). Put the result in the hand-off note.
- [ ] **Step 3: Review.** Dispatch a review subagent following `skills/cmux-review/SKILL.md` ("Default pre-merge review"): the intent (this plan and S1 §6.3–§6.8), the base `git merge-base develop HEAD`, the head SHA and `git diff develop...HEAD`; correctness first, then the repository rules of Global Constraints. Fix concrete findings, rerun the Step 1 commands that cover them, and get a fresh review of a non-trivial repair.
- [ ] **Step 4: Live checks are plan 1D's** (do not block the merge). They need relay plan 1A deployed (plan 1D Phase 1), the real client IDs and the Sign in with Apple key, and they run as plan 1D Task 7 Step 6 (simulator) and Task 12 (real devices, S1 §2.1 criteria 1, 3, 5). `dev.sh device` installs ShellX Dev (`com.shellx.dev`, its own Keychain), so it can never take over the App Store build's password session. Record "live checks: pending (plan 1D)" in the hand-off note.
- [ ] **Step 5: Land** (contracts §1): this plan changes app UI/runtime, so after the final review it waits for the USER device check and the user's merge directive (`merge`, `merge it` or `auto-merge`, CLAUDE.md "CI, review and merge"); if none was given, ask with the review summary. Only then merge into `develop` and push `develop` from the main checkout, never inside the worktree:

```bash
cd /Users/lehuuphu/Documents/myProjects/shellx   # the main checkout: develop is checked out there, so the worktree cannot check it out
git branch --show-current                                                  # must print develop; otherwise stop
git status --short --untracked-files=no -- shellx-ios shellx-link release scripts   # must print nothing; stop otherwise
git pull --ff-only origin develop
git merge --no-ff feat/shellx-signin-1c-ios -m "Merge branch 'feat/shellx-signin-1c-ios' into develop"
git push origin develop
```

  A merge conflict: abort it (`git merge --abort`), merge `develop` into the branch in the worktree, rerun the Step 1 checks, then retry. Then finish the worktree with `superpowers:finishing-a-development-branch`. Never `main`, never a deploy, a store upload or a release.
- [ ] **Step 6: Hand-off note** to the user: what landed; the localization audit; the live-check results or that they are pending; what waits for the user (Task 8 Steps 5–6 and Task 9 Step 6 if not done; until Task 9 Steps 6–8 are done the App Store check refuses the build; 1D's release); and that Task 15 runs only after 1D's cut-over.

---

### Task 15: After the cut-over: remove password sign-in

**Run only after plan 1D's cut-over step** (`PASSWORD_LOGIN=off` live on the relay and `npm run password-cutover` done). **USER** confirms in the chat that the cut-over is done; until then do not start this task. It runs later, in its own worktree: branch `feat/shellx-signin-1c-ios-cutover` from `develop` (`superpowers:using-git-worktrees`).

**Files:**
- Modify: `shellx-link/Sources/ShellXLinkAccount/RelayAPI.swift` (remove `login`, `:87-97`, and `LoginReply`, `:226-235`, when nothing else uses it), `shellx-link/Tests/ShellXLinkAccountTests/RelayAPITests.swift:16-75`, `shellx-link/Sources/shellx-link-probe/Account.swift:8-25`, `shellx-link/Sources/shellx-link-probe/main.swift:14,38,66-68`, `shellx-link/Sources/shellx-link-probe/Support.swift:9`, `shellx-link/Sources/shellx-link-probe/State.swift:198-215`, `shellx-link/README.md` (the probe's `login` lines)
- Modify: `shellx-ios/Packages/ShellXAppCore/Sources/ShellXAppCore/Account/RelayAccountCalling.swift`, `.../Account/AppCoordinator.swift` (remove `signIn(email:password:)`), `.../ShellXAppTestSupport/FakeRelayAccount.swift` (remove `login`, `setLogin`, `.login`), `.../ShellXDemo/DemoRelay.swift` (remove `login`), `.../Tests/ShellXAppCoreTests/AppCoordinatorTests.swift`, `.../Tests/ShellXAppCoreTests/DemoRelayTests.swift`

**Interfaces:**
- Consumes: everything of Tasks 1–7.
- Produces: no password path. Probe commands: `shellx-link-probe nonce --api <url>` prints a fresh relay nonce alone on stdout; `shellx-link-probe login --state <dir> --api <url> --nonce <nonce> --id-token-stdin [--device-name <name>]` signs in with `signInWithGoogle(idToken:nonce:deviceName:clientKey:)` using an ID token that carries that nonce (read from stdin like the password today, never printed). `PasswordInput` becomes `SecretInput.read(prompt:)`; the flag set swaps `password-stdin` for `id-token-stdin`.

- [ ] **Step 1: Move the tests off the password path.** In `RelayAPITests`: `testLoginSendsMobileDevice` and `testLoginUsesBase64URLAlphabetForPublicKey` become `testGoogleSignInIsTheMobileSignIn` and `testGoogleSignInUsesBase64URLAlphabetForPublicKey` (same assertions on `signInWithGoogle`, `/v1/auth/google` and its `device`); `testRedirectIsRefusedAndNotFollowed` uses `nonce()` instead of `login`. In `AppCoordinatorTests`: the private rig becomes `CoordinatorRig.make(self, ...)` with `relay.setGoogleSignIn(.success(AccountSignIn(session: account, email: "a@b.c")))`; every `signIn(email: "a@b.c", password: "pw")` becomes `signInWithGoogle()`; `testSignInMapsInvalidCredentialsAndRateLimit` uses `setGoogleSignIn(.failure(...))`; an expected `.login(email:deviceName:clientKey:)` call becomes `.nonce, .signInWithGoogle(idToken: "google-id-token", nonce: "nonce-1", deviceName: "Phu's iPhone", clientKey: key)`; the `relaunched` coordinators keep their direct `AppCoordinator(...)` construction. In `DemoRelayTests` drop the `login` entry.
- [ ] **Step 2: Run them.** Run: `swift test --package-path shellx-link` and `shellx-ios/scripts/dev.sh test core`. Expected: green (they no longer use the password path).
- [ ] **Step 3: Remove the password path** listed under Files and change the probe as described.
- [ ] **Step 4: Verify.** Run: `swift build --package-path shellx-link` (the probe builds), `swift test --package-path shellx-link`, `bash scripts/shellx/check-link-license.sh`, `shellx-ios/scripts/dev.sh test all`, then `grep -rnE 'func login\(|signIn\(email:|password-stdin' shellx-link/Sources shellx-ios/Packages/ShellXAppCore/Sources shellx-ios/ShellX`. Expected: green everywhere and no grep output. `AccountAuthMethod.password` stays: old stored sessions still decode, then meet the relay's 401 and the sign-in screen.
- [ ] **Step 5: Commit.**

```bash
git add shellx-link shellx-ios/Packages/ShellXAppCore
git commit -m "refactor(shellx): remove password sign-in from shellx-link and the iPhone app after the cut-over"
```

- [ ] **Step 6: Review and land** as Task 14 Steps 3, 5 and 6, with branch `feat/shellx-signin-1c-ios-cutover`.

---

## Contract additions

This plan does not edit the contracts file. Contracts §5 (B) and §11 (A, D, Google branding) now record these; C remains a pointer for 3D.

- **A. Amend §4 `AppleLinkStatus.approved`.** Use `case approved(AccountSignIn, machineID: String, name: String, linkSlot: String)` instead of `(AccountSignIn, PairedMachineListing)`. §2's status reply carries only `machine: {machine_id, name, link_slot}`; a `PairedMachineListing` needs `grant_id`, `platform`, `online` and `fingerprint`, which would mean a second request (`GET /v2/phone-grants`) right after the one reply that hands over the new session token. Most likely the relay hands that token over only once, so a failed second request would lose the session. The new shape mirrors `PhonePairingStatus.approved(machineID:name:linkSlot:)`. Only 1C uses it; Android has no Apple methods (§5).
- **B. §5 demo paths.** `shellx-ios/ShellX/Debug/DemoScript.swift` moves to `shellx-ios/ShellX/Demo/DemoScript.swift` (Task 13), and the demo's data (sessions, chat, requests), which 3C ports to `com.shellx.core.demo.DemoScript`, is in `shellx-ios/Packages/ShellXAppCore/Sources/ShellXDemo/FakeMacDemoScript.swift` (Task 12).
- **C. New iPhone string keys** that `import-strings.py` turns into Android names (§5); 3D can reuse them for the Android sign-in, demo and deletion screens: `signin.google`, `signin.demo`, `signin.error.switchFromSignedInDevice`, `signin.error.reauthRequired`, `signin.error.providerUnavailable`, `signin.error.providerFailed`, `firstMac.demo`, `demo.banner.title`, `demo.banner.exit`, `demo.banner.label`, `settings.account.delete`, `settings.account.delete.title`, `settings.account.delete.message`, `settings.account.delete.button`, `settings.account.delete.deleting`. iPhone-only (Apple, or the password-session switch Android never has): `signin.apple.*`, `appleLink.*`, `signin.error.emailInUse`, `signin.error.identityInUse`, `settings.account.switchToGoogle*`, `settings.account.delete.switchFirst`, `switchToGoogle.banner.*`. `signin.password` and `signin.button` are removed; `signin.subtitle` (it mentions Apple, so Android needs its own), `signin.error.invalidCredentials` and `pairing.instructions` change text.
- **D. iPhone Google client settings, for 1D.** Build setting `SHELLX_GOOGLE_IOS_CLIENT` (Debug.xcconfig: the `com.shellx.dev` client, Release.xcconfig: the `com.shellx.prod` client, both without `.apps.googleusercontent.com`, placeholder `0-shellx-placeholder`) feeding Info.plist `ShellXGoogleClientID`. The relay's `GOOGLE_CLIENT_IDS` must list both full iOS client IDs. `release/mobile/ios.sh` refuses a signed build with the placeholder, without `com.apple.developer.applesignin`, or without Google's branding (`GoogleG`, `GoogleSans.ttf`).

## Spec notes

- S1 §6.3 / §6.6: confirmed in code. `AppCoordinator.handleUnauthorized` (`AppCoordinator.swift:137-145`) only clears the session; the phone key and the Macs stay. Nothing in this plan changes that.
- S1 §5 asks to add AuthenticationServices to the licence allowlist "if needed": it is already there (with CryptoKit). The only new module is `ShellXDemo` (Task 12).
- S1 §6.4 step 3 / contracts §2: there is no route to withdraw an Apple link request (the bearer-based `/v2/phone-pairings/:id/deny` needs a token the phone does not have yet). A request the phone stops waiting for stays pending on the Mac until it expires; an Allow pressed after that links the Apple ID and leaves an unused iPhone device and token. A `POST /v1/auth/apple/link/cancel {link_token, pairing_id}` in 1A would close this gap; this plan does not depend on it.
- S1 §6.8 versus G1: the relay accepts only a fresh ID token of an identity of the account (or a password, which G1 removes from every app). A password session therefore cannot re-authenticate; "Delete Account…" asks it to switch to Google sign-in first (Task 11).
- S1 §6.6 asks for the Apple button "theo mẫu chuẩn của Apple": `ASAuthorizationAppleIDButton` (type `.signIn`, "Sign in with Apple", localized by iOS), used as a plain control so the relay nonce can be fetched before the request.
- Contracts §11, Google's button (Task 9): Google's bundle (`signin-assets.zip`, checked 2026-11-07) has only whole buttons with English text, no bare "G". The G therefore comes from cropping the centre of the official Light, no-text iOS icon. That keeps its size and colours and drops only the frame, as the page's "start with any of the logo sizes included in the download bundle" allows. The SVGs are not used: their gradient G is a `foreignObject`.
- Google's button uses its Light theme in both appearances. In dark mode Apple's button must be white (HIG: black is not for dark backgrounds), and Google's Dark theme beside it would look less prominent, against the page's "Sign in with Google and other third party sign-in options" and App Store 4.8. This also sidesteps the page's unclear rule for the G on the Dark theme; Google's own dark iOS icon draws it straight on `#131314`.
- The page prescribes Google Sans Medium 14/20. Google Sans is a 5 MB variable font (OFL 1.1, no Reserved Font Name, Vietnamese included), shipped unmodified for this one button.
- Google scope on the phone is `openid email`; the desktop uses `openid email profile` (contracts §3). The relay needs only `email` and `email_verified`.
- The reversed client ID is only the callback scheme of `ASWebAuthenticationSession`; no `CFBundleURLTypes` entry is needed or added.
- After "Switch to Google sign-in" the hub restarts, so the screens start again at the home: requests of the old hub may carry the token the relay just deleted.
- The spec marks "Xem thử không cần tài khoản" as not yet answered by the user; it is built as specified. Its demo Mac keeps the Debug demo's Vietnamese sample names ("Mac giả").
- The repo's testing skill prefers Swift Testing for Swift unit targets; the touched targets are all XCTest, and the task asks for the style of `RelayAPITests`, so new tests stay XCTest.
- Task 15: after the cut-over the probe can only sign in with an ID token carrying a relay nonce; how to mint one for a local relay with the test identity provider (`TEST_IDP_ISSUER`) is 1A's tooling.
