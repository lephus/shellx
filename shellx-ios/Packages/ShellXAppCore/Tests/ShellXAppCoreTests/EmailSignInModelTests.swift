import Foundation
import ShellXAppTestSupport
import ShellXLinkAccount
import XCTest
@testable import ShellXAppCore

/// The steps of sign-in with an emailed code, the Resend lock on a clock the test moves, and what each failure does.
@MainActor
final class EmailSignInModelTests: XCTestCase {
    private func http(_ status: Int, _ code: String) -> RelayAPIError { .http(status: status, code: code) }

    /// A launched rig with nobody signed in.
    private func signedOut() async -> CoordinatorRig {
        let rig = await CoordinatorRig.make(self)
        await rig.coordinator.launch()
        return rig
    }

    /// `signedOut()` after a code was sent to phu@example.com: the code step, "challenge-1", 60 seconds of lock.
    private func atCode() async -> CoordinatorRig {
        let rig = await signedOut()
        let model = rig.coordinator.emailSignIn
        model.begin()
        model.email = "phu@example.com"
        await model.sendCode()
        XCTAssertEqual(model.step, .code)
        return rig
    }

    /// The relay's verify calls, as "<challengeID> <code>".
    private func verifies(_ rig: CoordinatorRig) async -> [String] {
        await rig.relay.calls.compactMap { call -> String? in
            if case let .signInWithEmailCode(challengeID, code, _, _) = call { return "\(challengeID) \(code)" }
            return nil
        }
    }

    func testTheStepsFromTheButtonToTheSignedInAccount() async throws {
        let rig = await signedOut()
        let coordinator = rig.coordinator
        let model = coordinator.emailSignIn
        XCTAssertEqual(model.step, .idle)
        XCTAssertEqual(model.panel, .providers)
        XCTAssertTrue(coordinator.emailSignIn === coordinator.emailSignIn)

        model.begin()
        XCTAssertEqual(model.step, .email)
        XCTAssertTrue(model.isEntering)
        for text in ["", "phu", "phu@", "phu@example", "@example.com", "phu@.com", "phu@example."] {
            XCTAssertFalse(EmailSignInModel.looksLikeEmail(text), text)
        }
        XCTAssertTrue(EmailSignInModel.looksLikeEmail("  phu@example.com "))
        XCTAssertFalse(model.canSend)
        model.email = "phu@example.com"
        XCTAssertTrue(model.canSend)

        await model.sendCode()
        XCTAssertEqual(model.step, .code)
        XCTAssertEqual(model.sentTo, "phu@example.com")
        XCTAssertEqual(model.resendIn, 60)
        XCTAssertFalse(model.canVerify)

        model.setCode("123456")
        let signedIn = await eventually { coordinator.phase == .signedIn(email: "user@example.com") && model.step == .done }
        XCTAssertTrue(signedIn)
        XCTAssertEqual(coordinator.authMethod, .email)
        XCTAssertEqual(model.step, .done)
        XCTAssertEqual(model.panel, .providers)
        XCTAssertEqual(model.email, "")
        XCTAssertEqual(model.code, "")
        XCTAssertNil(model.sentTo)
        let calls = await rig.relay.calls
        XCTAssertEqual(calls.first, .requestEmailCode(email: "phu@example.com", locale: "vi"))
        let sent = await verifies(rig)
        XCTAssertEqual(sent, ["challenge-1 123456"])

        await coordinator.signOut()
        model.begin()
        XCTAssertEqual(model.step, .email)
        XCTAssertEqual(model.email, "")
    }

    func testTheEmailIsTrimmedAndOver254BytesIsRefusedWithoutARequest() async {
        let rig = await signedOut()
        let model = rig.coordinator.emailSignIn
        model.begin()
        model.email = "  Phu@Example.com \n"
        await model.sendCode()
        let first = await rig.relay.calls
        XCTAssertEqual(first, [.requestEmailCode(email: "Phu@Example.com", locale: "vi")])
        XCTAssertEqual(model.sentTo, "phu@example.com", "the relay's spelling")

        model.changeEmail()
        await rig.relay.resetCalls()
        model.email = String(repeating: "a", count: 243) + "@example.com"
        XCTAssertEqual(model.email.utf8.count, 255)
        XCTAssertTrue(model.canSend)
        await model.sendCode()
        XCTAssertEqual(model.step, .email)
        XCTAssertEqual(model.error, .invalidEmail)
        let second = await rig.relay.calls
        XCTAssertEqual(second, [])
    }

    func testAnAddressWithALetterOutsideASCIIIsRefusedAndTheFieldSaysWhy() async {
        // A Vietnamese keyboard (Telex) turns "ex" into "ẽ" even in an email field; the relay takes ASCII addresses
        // only, so the phone refuses them first. The last one has a full-width "ｅ".
        for text in ["phu@ẽample.com", "phú@example.com", "phu@example.cóm", "phu@\u{FF45}xample.com"] {
            XCTAssertFalse(EmailSignInModel.looksLikeEmail(text), text)
        }
        XCTAssertTrue(EmailSignInModel.looksLikeEmail("phu@example.com\u{00A0}"), "a no-break space at the end is trimmed")

        let rig = await signedOut()
        let model = rig.coordinator.emailSignIn
        model.begin()
        model.email = "phu@ẽample.com"
        XCTAssertFalse(model.canSend)
        XCTAssertNil(model.error, "nothing failed")
        XCTAssertEqual(model.emailFieldError, .invalidEmail, "the field says why Send code is off")
        await model.sendCode()
        XCTAssertEqual(model.step, .email)
        let calls = await rig.relay.calls
        XCTAssertEqual(calls, [], "nothing goes to the relay")

        model.email = "phu@exam"
        XCTAssertFalse(model.canSend)
        XCTAssertNil(model.emailFieldError, "an address still being typed is not wrong")
        model.email = "phu@example.com"
        XCTAssertTrue(model.canSend)
        XCTAssertNil(model.emailFieldError)

        await rig.relay.setError(http(400, "disposable_email"), for: .requestEmailCode)
        await model.sendCode()
        XCTAssertEqual(model.emailFieldError, .disposableEmail, "the relay's answer shows there too")
    }

    func testASendFailureStaysOnTheEmailStepAndTheSameTapRetries() async {
        let rig = await signedOut()
        let model = rig.coordinator.emailSignIn
        model.begin()
        model.email = "phu@example.com"
        let cases: [(any Error, SignInError)] = [
            (http(400, "invalid_email"), .invalidEmail),
            (http(400, "disposable_email"), .disposableEmail),
            (http(429, "rate_limited"), .rateLimited),
            (http(502, "email_send_failed"), .emailSendFailed),
            (http(503, "email_sign_in_disabled"), .providerUnavailable),
            (http(404, "not_found"), .providerUnavailable),
            (URLError(.notConnectedToInternet), .network),
        ]
        for (relayError, expected) in cases {
            await rig.relay.setError(relayError, for: .requestEmailCode)
            await model.sendCode()
            XCTAssertEqual(model.error, expected, "\(relayError)")
            XCTAssertEqual(model.step, .email, "\(relayError)")
            XCTAssertEqual(model.email, "phu@example.com", "\(relayError)")
        }
        await rig.relay.setError(nil, for: .requestEmailCode)
        await model.sendCode()
        XCTAssertEqual(model.step, .code)
        XCTAssertNil(model.error)
    }

    func testTheCountdownFollowsTheClockAlsoAfterTimeAway() async {
        let rig = await atCode()
        let model = rig.coordinator.emailSignIn
        XCTAssertFalse(model.canResend)
        await model.resend()
        let locked = await rig.relay.calls
        XCTAssertEqual(locked.count, 1, "a locked Resend sends nothing")

        rig.clock.advance(by: .seconds(1))
        let ticked = await eventually { model.resendIn == 59 }
        XCTAssertTrue(ticked)

        // The app was away for 45 seconds: one late tick, and the number is the time really left.
        model.setCode("12")
        rig.clock.advance(by: .seconds(45))
        let back = await eventually { model.resendIn == 14 }
        XCTAssertTrue(back)
        XCTAssertEqual(model.step, .code)
        XCTAssertEqual(model.code, "12")

        rig.clock.advance(by: .seconds(14))
        let unlocked = await eventually { model.canResend }
        XCTAssertTrue(unlocked)
        XCTAssertEqual(model.resendIn, 0)

        await model.resend()
        let calls = await rig.relay.calls
        XCTAssertEqual(calls.last, .requestEmailCode(email: "phu@example.com", locale: "vi"))
        XCTAssertEqual(calls.count, 2)
        XCTAssertEqual(model.resendIn, 60)
        XCTAssertEqual(model.code, "")

        model.setCode("654321")
        let done = await eventually { model.step == .done }
        XCTAssertTrue(done)
        let sent = await verifies(rig)
        XCTAssertEqual(sent, ["challenge-2 654321"], "the new challenge replaced the old one")
    }

    func testAPastedCodeIsCutToItsSixDigits() async {
        XCTAssertEqual(
            ["123 456", " 12-34 56\n", "1234567", "١٢٣٤٥٦", "abc", "Your ShellX sign-in code is 123456"].map(EmailSignInModel.digits),
            ["123456", "123456", "123456", "123456", "", "123456"])
        let rig = await atCode()
        let model = rig.coordinator.emailSignIn
        model.setCode(" 123 456\n")
        let done = await eventually { model.step == .done }
        XCTAssertTrue(done)
        let sent = await verifies(rig)
        XCTAssertEqual(sent, ["challenge-1 123456"])
    }

    func testVerifyTwiceSendsOneRequest() async {
        let rig = await atCode()
        let model = rig.coordinator.emailSignIn
        let gate = Gate()
        await rig.relay.setHook({ await gate.wait() }, for: .signInWithEmailCode)
        model.setCode("123456")
        let held = await eventually { gate.waiting == 1 }
        XCTAssertTrue(held)
        XCTAssertEqual(model.step, .verifying)

        await model.verify()
        model.setCode("999999")
        model.cancel()
        XCTAssertEqual(model.step, .verifying)

        gate.open()
        let done = await eventually { model.step == .done }
        XCTAssertTrue(done)
        let sent = await verifies(rig)
        XCTAssertEqual(sent, ["challenge-1 123456"])
    }

    func testAWrongCodeEmptiesTheFieldAndKeepsTheChallenge() async {
        let rig = await atCode()
        let model = rig.coordinator.emailSignIn
        await rig.relay.setError(http(401, "invalid_code"), for: .signInWithEmailCode)
        model.setCode("111111")
        let refused = await eventually { model.error == .invalidCode }
        XCTAssertTrue(refused)
        XCTAssertEqual(model.step, .code)
        XCTAssertEqual(model.code, "")

        await rig.relay.setError(nil, for: .signInWithEmailCode)
        model.setCode("2")
        XCTAssertNil(model.error, "typing again takes the message away")
        model.setCode("222222")
        let done = await eventually { model.step == .done }
        XCTAssertTrue(done)
        let sent = await verifies(rig)
        XCTAssertEqual(sent, ["challenge-1 111111", "challenge-1 222222"])
    }

    func testAnExpiredCodeUnlocksResendAtOnce() async {
        let rig = await atCode()
        let model = rig.coordinator.emailSignIn
        await rig.relay.setError(http(410, "code_expired"), for: .signInWithEmailCode)
        model.setCode("123456")
        let expired = await eventually { model.error == .codeExpired }
        XCTAssertTrue(expired)
        XCTAssertEqual(model.code, "")
        XCTAssertEqual(model.resendIn, 0)
        XCTAssertTrue(model.canResend)
        XCTAssertFalse(model.codeIsLive)

        // The dead field takes nothing, and Verify sends nothing.
        await rig.relay.setError(nil, for: .signInWithEmailCode)
        model.setCode("123456")
        XCTAssertEqual(model.code, "")
        XCTAssertFalse(model.canVerify)
        XCTAssertEqual(model.error, .codeExpired)
        await model.verify()
        let afterDead = await verifies(rig)
        XCTAssertEqual(afterDead.count, 1)

        await model.resend()
        XCTAssertTrue(model.codeIsLive)
        XCTAssertNil(model.error)
        model.setCode("123456")
        let done = await eventually { model.step == .done }
        XCTAssertTrue(done)
        let sent = await verifies(rig)
        XCTAssertEqual(sent.last, "challenge-2 123456")
    }

    func testAPasswordAccountGoesBackToTheEmailStep() async {
        let rig = await atCode()
        let model = rig.coordinator.emailSignIn
        await rig.relay.setError(http(409, "switch_from_signed_in_device"), for: .signInWithEmailCode)
        model.setCode("123456")
        let back = await eventually { model.step == .email }
        XCTAssertTrue(back)
        XCTAssertEqual(model.error, .switchFromSignedInDevice)
        XCTAssertEqual(model.email, "phu@example.com")
        XCTAssertNil(model.sentTo)
        XCTAssertEqual(model.resendIn, 0)
    }

    func testOfflineKeepsWhatWasTypedAndTheSameTapRetries() async {
        let rig = await atCode()
        let model = rig.coordinator.emailSignIn
        await rig.relay.setError(URLError(.notConnectedToInternet), for: .signInWithEmailCode)
        model.setCode("123456")
        let offline = await eventually { model.error == .network }
        XCTAssertTrue(offline)
        XCTAssertEqual(model.step, .code)
        XCTAssertEqual(model.code, "123456")
        XCTAssertTrue(model.canVerify)

        await rig.relay.setError(nil, for: .signInWithEmailCode)
        await model.verify()
        XCTAssertEqual(model.step, .done)
        XCTAssertEqual(rig.coordinator.authMethod, .email)
    }

    func testCancelAndChangeEmailDropTheCodeAndKeepTheAddress() async {
        let rig = await atCode()
        let model = rig.coordinator.emailSignIn
        model.setCode("12")
        model.changeEmail()
        XCTAssertEqual(model.step, .email)
        XCTAssertEqual(model.email, "phu@example.com")
        XCTAssertEqual(model.code, "")
        XCTAssertNil(model.sentTo)

        await model.sendCode()
        XCTAssertEqual(model.step, .code)
        model.cancel()
        XCTAssertEqual(model.step, .idle)
        XCTAssertEqual(model.panel, .providers)
        XCTAssertEqual(model.resendIn, 0)

        model.begin()
        XCTAssertEqual(model.email, "phu@example.com")
        // A code typed outside the code step goes nowhere.
        model.setCode("123456")
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(model.code, "")
        let sent = await verifies(rig)
        XCTAssertEqual(sent, [])
    }

    func testTheDeletionModelNeverSubmitsByItself() async throws {
        let rig = await CoordinatorRig.make(self)
        try await rig.vault.setSession(
            StoredSession(userID: "u1", deviceID: "d1", token: "tok-old", email: "phu@example.com", authMethod: .email))
        try await rig.vault.setMachines([], owner: "u1")
        await rig.coordinator.launch()

        let model = rig.coordinator.makeDeleteAccountCode()
        XCTAssertFalse(model === rig.coordinator.emailSignIn)
        XCTAssertEqual(model.step, .email)
        XCTAssertEqual(model.email, "phu@example.com")
        let opened = await rig.relay.calls
        XCTAssertEqual(opened, [], "opening the sheet mails nothing")

        await model.sendCode()
        model.setCode("123456")
        for _ in 0..<20 { await Task.yield() }
        let typed = await rig.relay.calls
        XCTAssertEqual(typed, [.requestEmailCode(email: "phu@example.com", locale: "vi")], "the sixth digit deletes nothing")
        XCTAssertTrue(model.canVerify)

        await model.verify()
        let calls = await rig.relay.calls
        XCTAssertEqual(calls.last, .deleteAccountWithCode(challengeID: "challenge-1", code: "123456", token: "tok-old"))
        XCTAssertEqual(model.step, .done)
        XCTAssertEqual(rig.coordinator.phase, .signedOut(expired: false))
    }
}
