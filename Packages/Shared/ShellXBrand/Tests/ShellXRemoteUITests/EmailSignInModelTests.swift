import Foundation
import Testing
import ShellXRemoteCore
@testable import ShellXRemoteUI

@MainActor @Suite("Email sign-in model") struct EmailSignInModelTests {
    private let labels = SignInErrorLabels.english
    private let t0 = SignInClock.t0

    @Test func theSheetStartsOnTheEmailStep() {
        let rig = EmailSignInRig()
        #expect(rig.model.step == .email)
        #expect(rig.model.email == "")
        #expect(rig.model.errorText == nil)
        #expect(rig.model.sentTo == nil)
        #expect(!rig.model.canSend)
    }

    @Test func plausibleEmailNeedsAsciiAnAtAndADotAfterIt() {
        for text in ["a@b.c", " a@b.co "] {
            #expect(EmailSignInModel.isPlausibleEmail(text), "\(text)")
        }
        for text in ["", "a@b", "a@.c", "a@b.", "@b.c", "a b@c.d", "phu@ẽample.com"] {
            #expect(!EmailSignInModel.isPlausibleEmail(text), "\(text)")
        }
    }

    @Test func aNonAsciiAddressShowsTheInvalidEmailSentenceAtOnce() {
        let rig = EmailSignInRig()
        rig.model.setEmail("phu@ẽ")
        #expect(rig.model.emailFieldError == labels.invalidEmail)
        #expect(!rig.model.canSend)
        #expect(rig.model.sendCode() == nil)
        #expect(rig.send.calls.isEmpty)
        rig.model.setEmail("phu@example.com")
        #expect(rig.model.emailFieldError == nil)
        #expect(rig.model.canSend)
    }

    @Test func sendCodeShowsSendingThenTheCodeStep() async {
        let rig = EmailSignInRig()
        let focus = rig.model.focusRequest
        rig.model.setEmail("  Foo@Bar.com ")
        let task = rig.model.sendCode()
        #expect(rig.model.step == .sending)
        #expect(rig.model.email == "Foo@Bar.com")
        #expect(await rig.send.pending())
        #expect(rig.send.calls == [["Foo@Bar.com"]])
        rig.send.resolve(EmailSignInRig.challenge("ch-1"))
        await task?.value
        #expect(rig.model.step == .code)
        #expect(rig.model.sentTo == "foo@bar.com")
        #expect(rig.model.errorText == nil)
        #expect(rig.model.code == "")
        #expect(rig.model.resendWait(at: rig.clock.now) == 60)
        #expect(rig.model.focusRequest > focus)
    }

    @Test func sendCodeTwiceSendsOnce() async {
        let rig = EmailSignInRig()
        rig.model.setEmail("Foo@Bar.com")
        let first = rig.model.sendCode()
        #expect(rig.model.sendCode() == nil)
        #expect(await rig.send.pending())
        rig.send.resolve(EmailSignInRig.challenge("ch-1"))
        await first?.value
        #expect(rig.send.calls.count == 1)
    }

    @Test func aRefusedAddressReturnsToTheEmailStepWithItsSentence() async {
        let rig = EmailSignInRig()
        rig.model.setEmail("foo@mailinator.com")
        let refusals = [("invalid_email", labels.invalidEmail), ("disposable_email", labels.disposableEmail),
                        ("email_send_failed", labels.emailSendFailed)]
        for (code, sentence) in refusals {
            let task = rig.model.sendCode()
            #expect(await rig.send.pending())
            rig.send.fail(code)
            await task?.value
            #expect(rig.model.step == .email, "\(code)")
            #expect(rig.model.errorText == sentence, "\(code)")
            #expect(rig.model.emailFieldError == sentence, "\(code)")
        }
        rig.model.setEmail("foo@bar.com")
        #expect(rig.model.errorText == nil)
        let task = rig.model.sendCode()
        #expect(await rig.send.pending())
        rig.send.resolve(EmailSignInRig.challenge("ch-1"))
        await task?.value
        #expect(rig.model.step == .code)
    }

    @Test func aRelayWithoutEmailSignInSaysUnavailable() async {
        let rig = EmailSignInRig()
        rig.model.setEmail("Foo@Bar.com")
        let send = rig.model.sendCode()
        #expect(await rig.send.pending())
        rig.send.fail("email_sign_in_disabled")
        await send?.value
        #expect(rig.model.step == .email)
        #expect(rig.model.errorText == labels.unavailable)

        await rig.toCodeStep()
        let verifying = rig.model.setCode("123456")
        #expect(await rig.verify.pending())
        rig.verify.fail("email_sign_in_disabled")
        await verifying?.value
        #expect(rig.model.step == .code)
        #expect(rig.model.errorText == labels.unavailable)
        #expect(rig.model.code == "123456")
        #expect(rig.model.codeIsLive)
        #expect(rig.model.canVerify)
        let again = rig.model.submitCode()
        #expect(again != nil)
        #expect(await rig.verify.pending())
        #expect(rig.verify.calls.last == ["ch-1", "123456"])
        rig.verify.resolve("foo@bar.com")
        await again?.value
    }

    @Test func aRateLimitShowsItsSentenceAndSendWorksAgainAtOnce() async {
        let rig = EmailSignInRig()
        rig.model.setEmail("Foo@Bar.com")
        let task = rig.model.sendCode()
        #expect(await rig.send.pending())
        rig.send.fail("rate_limited")
        await task?.value
        #expect(rig.model.step == .email)
        #expect(rig.model.errorText == labels.rateLimited)
        let again = rig.model.sendCode()
        #expect(again != nil)
        #expect(await rig.send.pending())
        rig.send.resolve(EmailSignInRig.challenge("ch-1"))
        await again?.value
    }

    @Test func answersWithoutTheirOwnSentenceReadAsTheServerSentence() async {
        let rig = EmailSignInRig()
        rig.model.setEmail("Foo@Bar.com")
        for code in ["http_502", "http_503", "http_504", "server", "invalid_params"] {
            let task = rig.model.sendCode()
            #expect(await rig.send.pending())
            rig.send.fail(code)
            await task?.value
            #expect(rig.model.step == .email, "\(code)")
            #expect(rig.model.errorText == labels.server, "\(code)")
        }
        await rig.toCodeStep()
        var verifying = rig.model.setCode("123456")
        for code in ["http_503", "invalid_device"] {
            #expect(verifying != nil, "\(code)")
            #expect(await rig.verify.pending())
            rig.verify.fail(code)
            await verifying?.value
            #expect(rig.model.step == .code, "\(code)")
            #expect(rig.model.errorText == labels.server, "\(code)")
            #expect(rig.model.code == "123456", "\(code)")
            #expect(rig.model.canVerify, "\(code)")
            verifying = rig.model.submitCode()
        }
        #expect(await rig.verify.pending())
        rig.verify.resolve("foo@bar.com")
        await verifying?.value
    }

    @Test func offlineShowsTheNetworkMessageAndAllowsRetry() async {
        let rig = EmailSignInRig()
        rig.model.setEmail("Foo@Bar.com")
        let task = rig.model.sendCode()
        #expect(await rig.send.pending())
        rig.send.fail(URLError(.notConnectedToInternet))
        await task?.value
        #expect(rig.model.step == .email)
        #expect(rig.model.errorText == labels.network)
        let again = rig.model.sendCode()
        #expect(await rig.send.pending())
        rig.send.resolve(EmailSignInRig.challenge("ch-1"))
        await again?.value
        #expect(rig.model.step == .code)
    }

    @Test func pastedCodeKeepsOnlySixDigits() async {
        #expect(EmailSignInModel.digits(" 123 456\n") == "123456")
        #expect(EmailSignInModel.digits("12a34") == "1234")
        #expect(EmailSignInModel.digits("1234567890") == "123456")
        #expect(EmailSignInModel.digits("１２３４５６") == "123456")
        #expect(EmailSignInModel.digits("٠٠٤٢١٧") == "004217")
        #expect(EmailSignInModel.digits("Your ShellX sign-in code is 004217") == "004217")
        #expect(EmailSignInModel.digits("四五六") == "")
        let rig = EmailSignInRig()
        await rig.toCodeStep()
        #expect(rig.model.setCode("12 3") == nil)
        #expect(rig.model.code == "123")
    }

    @Test func aCodeWithLeadingZerosIsSentAsIs() async {
        let rig = EmailSignInRig()
        await rig.toCodeStep()
        let task = rig.model.setCode("004217")
        #expect(task != nil)
        #expect(await rig.verify.pending())
        #expect(rig.verify.calls == [["ch-1", "004217"]])
        rig.verify.resolve("foo@bar.com")
        await task?.value
    }

    @Test func sixDigitsSubmitByThemselvesOnce() async {
        let rig = EmailSignInRig()
        await rig.toCodeStep()
        let task = rig.model.setCode("123 456")
        #expect(task != nil)
        #expect(rig.model.step == .verifying)
        #expect(await rig.verify.pending())
        #expect(rig.verify.calls == [["ch-1", "123456"]])
        #expect(rig.model.setCode("123456") == nil)
        #expect(rig.model.submitCode() == nil)
        rig.verify.resolve("foo@bar.com")
        await task?.value
        #expect(rig.verify.calls.count == 1)
        #expect(rig.model.step == .done(email: "foo@bar.com"))
    }

    @Test func aWrongCodeEmptiesTheFieldAndStaysOnTheCodeStep() async {
        let rig = EmailSignInRig()
        await rig.toCodeStep()
        let focus = rig.model.focusRequest
        let task = rig.model.setCode("123456")
        #expect(await rig.verify.pending())
        rig.verify.fail("invalid_code")
        await task?.value
        #expect(rig.model.step == .code)
        #expect(rig.model.errorText == labels.invalidCode)
        #expect(rig.model.code == "")
        #expect(rig.model.codeIsLive)
        #expect(rig.model.canEditCode)
        #expect(!rig.model.canVerify)
        #expect(rig.model.sentTo == "foo@bar.com")
        #expect(rig.model.resendWait(at: rig.clock.now) > 0)
        #expect(rig.model.focusRequest > focus)
        rig.model.setCode("6")
        #expect(rig.model.errorText == nil)
        let again = rig.model.setCode("654321")
        #expect(again != nil)
        #expect(await rig.verify.pending())
        #expect(rig.verify.calls.count == 2)
        rig.verify.resolve("foo@bar.com")
        await again?.value
    }

    @Test func aDeadCodeTurnsTheFieldOffAndUnlocksResend() async {
        let rig = EmailSignInRig()
        await rig.toCodeStep()
        let task = rig.model.setCode("123456")
        #expect(await rig.verify.pending())
        rig.verify.fail("code_expired")
        await task?.value
        #expect(rig.model.step == .code)
        #expect(rig.model.errorText == labels.codeExpired)
        #expect(rig.model.code == "")
        #expect(!rig.model.codeIsLive)
        #expect(!rig.model.canEditCode)
        #expect(rig.model.setCode("123456") == nil)
        #expect(rig.model.resendWait(at: rig.clock.now) == 0)
        let resend = rig.model.resend()
        #expect(resend != nil)
        #expect(await rig.send.pending())
        // The kept address, not sentTo ("foo@bar.com").
        #expect(rig.send.calls.last == ["Foo@Bar.com"])
        rig.send.resolve(EmailSignInRig.challenge("ch-2"))
        await resend?.value
        let verifying = rig.model.setCode("111111")
        #expect(await rig.verify.pending())
        #expect(rig.verify.calls.last == ["ch-2", "111111"])
        rig.verify.resolve("foo@bar.com")
        await verifying?.value
    }

    @Test func aSwitchAnswerGoesBackToTheEmailStepWithTheAddress() async {
        let rig = EmailSignInRig()
        await rig.toCodeStep()
        let focus = rig.model.focusRequest
        let task = rig.model.setCode("123456")
        #expect(await rig.verify.pending())
        rig.verify.fail("switch_from_signed_in_device")
        await task?.value
        #expect(rig.model.step == .email)
        #expect(rig.model.email == "Foo@Bar.com")
        #expect(rig.model.sentTo == nil)
        #expect(rig.model.code == "")
        #expect(rig.model.emailFieldError == labels.switchFromSignedInDevice)
        #expect(rig.model.resendWait(at: rig.clock.now) == 0)
        #expect(rig.model.focusRequest > focus)
        #expect(rig.model.submitCode() == nil)
        let send = rig.model.sendCode()
        #expect(send != nil)
        #expect(await rig.send.pending())
        #expect(rig.send.calls.last == ["Foo@Bar.com"])
        rig.send.resolve(EmailSignInRig.challenge("ch-2"))
        await send?.value
    }

    @Test(arguments: ["rate_limited", "offline"])
    func aResendRefusedForRateOrNetworkKeepsTheCode(_ failure: String) async {
        let rig = EmailSignInRig()
        await rig.toCodeStep()
        rig.clock.now = t0.addingTimeInterval(60)
        let resend = rig.model.resend()
        #expect(resend != nil)
        #expect(await rig.send.pending())
        if failure == "offline" {
            rig.send.fail(URLError(.notConnectedToInternet))
        } else {
            rig.send.fail(ShellXCoreError(code: failure, message: ""))
        }
        await resend?.value
        #expect(rig.model.step == .code)
        #expect(rig.model.errorText == (failure == "offline" ? labels.network : labels.rateLimited))
        #expect(rig.model.sentTo == "foo@bar.com")
        #expect(rig.model.codeIsLive)
        #expect(rig.model.resendWait(at: rig.clock.now) == 0)
        let verifying = rig.model.setCode("123456")
        #expect(await rig.verify.pending())
        #expect(rig.verify.calls.last == ["ch-1", "123456"])
        rig.verify.resolve("foo@bar.com")
        await verifying?.value
    }

    @Test(arguments: ["email_send_failed", "email_sign_in_disabled"])
    func aResendTheRelayCouldNotMailLeavesNoCodeToVerify(_ code: String) async {
        let rig = EmailSignInRig()
        await rig.toCodeStep()
        rig.model.setCode("12")
        rig.clock.now = t0.addingTimeInterval(60)
        let resend = rig.model.resend()
        #expect(await rig.send.pending())
        rig.send.fail(code)
        await resend?.value
        #expect(rig.model.step == .code)
        #expect(rig.model.errorText == (code == "email_send_failed" ? labels.emailSendFailed : labels.unavailable))
        #expect(!rig.model.codeIsLive)
        #expect(rig.model.code == "")
        #expect(!rig.model.canVerify)
        #expect(rig.model.setCode("123456") == nil)
        #expect(rig.model.resendWait(at: rig.clock.now) == 0)
        let again = rig.model.resend()
        #expect(again != nil)
        #expect(await rig.send.pending())
        rig.send.resolve(EmailSignInRig.challenge("ch-2"))
        await again?.value
        let verifying = rig.model.setCode("222222")
        #expect(await rig.verify.pending())
        #expect(rig.verify.calls.last == ["ch-2", "222222"])
        rig.verify.resolve("foo@bar.com")
        await verifying?.value
    }

    @Test func resendIsLockedForSixtySecondsAndCountsDown() async {
        let rig = EmailSignInRig()
        await rig.toCodeStep()
        #expect(rig.model.resendWait(at: t0) == 60)
        #expect(rig.model.resendWait(at: t0.addingTimeInterval(0.5)) == 60)
        #expect(rig.model.resendWait(at: t0.addingTimeInterval(59.2)) == 1)
        #expect(rig.model.resendWait(at: t0.addingTimeInterval(60)) == 0)
        rig.clock.now = t0.addingTimeInterval(30)
        #expect(rig.model.resend() == nil)
        rig.clock.now = t0.addingTimeInterval(60)
        let resend = rig.model.resend()
        #expect(resend != nil)
        #expect(rig.model.step == .sending)
        #expect(await rig.send.pending())
        #expect(rig.send.calls.count == 2)
        #expect(rig.send.calls.last == ["Foo@Bar.com"])
        rig.send.resolve(EmailSignInRig.challenge("ch-2"))
        await resend?.value
        #expect(rig.model.step == .code)
        #expect(rig.model.resendWait(at: rig.clock.now) == 60)
    }

    @Test func useADifferentEmailGoesBackWithTheAddress() async {
        let rig = EmailSignInRig()
        await rig.toCodeStep()
        rig.model.setCode("12")
        let focus = rig.model.focusRequest
        rig.model.useDifferentEmail()
        #expect(rig.model.step == .email)
        #expect(rig.model.email == "Foo@Bar.com")
        #expect(rig.model.sentTo == nil)
        #expect(rig.model.code == "")
        #expect(rig.model.errorText == nil)
        #expect(rig.model.resendWait(at: rig.clock.now) == 0)
        #expect(rig.model.focusRequest > focus)
        #expect(rig.model.submitCode() == nil)
    }

    @Test func cancelWhileSendingIgnoresTheLateChallenge() async {
        let rig = EmailSignInRig()
        rig.model.setEmail("Foo@Bar.com")
        let task = rig.model.sendCode()
        #expect(await rig.send.pending())
        rig.model.cancel()
        #expect(rig.reports.values == [false])
        rig.send.resolve(EmailSignInRig.challenge("ch-1"))
        await task?.value
        #expect(rig.model.step != .code)
        #expect(rig.reports.values == [false])
    }

    @Test func cancelWhileVerifyingClosesOnceAndIgnoresTheResult() async {
        let rig = EmailSignInRig()
        await rig.toCodeStep()
        let task = rig.model.setCode("123456")
        #expect(await rig.verify.pending())
        rig.model.cancel()
        #expect(rig.reports.values == [false])
        rig.verify.resolve("foo@bar.com")
        await task?.value
        if case .done = rig.model.step { Issue.record("a closed sheet reached .done") }
        #expect(rig.reports.values == [false])
        rig.model.finish()
        #expect(rig.reports.values == [false])
        // The request ran to its end, so the account keeps the session it created.
        #expect(rig.verify.cancelledAfterOpening == [false])
    }

    @Test func doneReportsOnceWhenThePersonConfirms() async {
        let rig = EmailSignInRig()
        await rig.toCodeStep()
        let task = rig.model.setCode("123456")
        #expect(await rig.verify.pending())
        rig.verify.resolve("foo@bar.com")
        await task?.value
        #expect(rig.model.step == .done(email: "foo@bar.com"))
        #expect(rig.reports.values.isEmpty)
        rig.model.finish()
        #expect(rig.reports.values == [true])
        rig.model.finish()
        rig.model.cancel()
        #expect(rig.reports.values == [true])
    }
}
