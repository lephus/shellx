import Foundation
import Testing
import ShellXRemoteCore
@testable import ShellXRemoteUI

@MainActor @Suite("Sign-in sheet flows") struct SignInSheetFlowsTests {
    private let labels = SignInErrorLabels.english

    /// A Google model whose sign-in waits on `gate`.
    private func googleModel(_ gate: CallGate<String>) -> GoogleSignInModel {
        GoogleSignInModel(purpose: .signIn, labels: .english, signIn: { try await gate.wait([]) }, cancel: {})
    }

    /// Starts Google through the flows and lets it fail with `google_timeout`.
    private func failGoogle(_ google: GoogleSignInModel, _ gate: CallGate<String>, email: EmailSignInModel) async {
        let task = SignInSheetFlows.startGoogle(google: google, email: email)
        #expect(task != nil)
        #expect(await gate.pending())
        gate.fail("google_timeout")
        await task?.value
        #expect(google.errorText == labels.timeout)
    }

    @Test func eachStartClearsTheOtherFlowsFailure() async {
        let gate = CallGate<String>(), rig = EmailSignInRig()
        let google = googleModel(gate)
        await failGoogle(google, gate, email: rig.model)
        rig.model.setEmail("Foo@Bar.com")
        #expect(google.errorText != nil)
        let send = SignInSheetFlows.sendCode(google: google, email: rig.model)
        #expect(send != nil)
        #expect(google.errorText == nil)
        #expect(await rig.send.pending())
        rig.send.fail("rate_limited")
        await send?.value
        #expect(rig.model.errorText == labels.rateLimited)
        let start = SignInSheetFlows.startGoogle(google: google, email: rig.model)
        #expect(start != nil)
        #expect(rig.model.errorText == nil)
        #expect(await gate.pending())
        gate.resolve("g@shellx.test")
        await start?.value
    }

    @Test func onlyOneFailureShowsWhileTyping() async {
        let gate = CallGate<String>(), rig = EmailSignInRig()
        let google = googleModel(gate)
        await failGoogle(google, gate, email: rig.model)
        SignInSheetFlows.setEmail(google: google, email: rig.model, text: "phu@ẽ")
        #expect(google.errorText == nil)
        #expect(rig.model.email == "phu@ẽ")
        #expect(SignInSheetFlows.emailFieldError(google: google, email: rig.model) == labels.invalidEmail)
        // "phu@ẽ" still typed, then Google fails again: only Google's failure shows.
        await failGoogle(google, gate, email: rig.model)
        #expect(google.errorText != nil)
        #expect(SignInSheetFlows.emailFieldError(google: google, email: rig.model) == nil)
        SignInSheetFlows.setEmail(google: google, email: rig.model, text: "phu@ẽx")
        #expect(SignInSheetFlows.emailFieldError(google: google, email: rig.model) == labels.invalidEmail)
        #expect(google.errorText == nil)
    }

    @Test func theTwoFlowsNeverRunTogether() async {
        let gate = CallGate<String>(), rig = EmailSignInRig()
        let google = googleModel(gate)
        rig.model.setEmail("Foo@Bar.com")
        let start = SignInSheetFlows.startGoogle(google: google, email: rig.model)
        #expect(start != nil)
        #expect(await gate.pending())
        // While Google waits.
        #expect(!SignInSheetFlows.emailEnabled(google: google))
        #expect(SignInSheetFlows.sendCode(google: google, email: rig.model) == nil)
        #expect(rig.send.calls.isEmpty)
        gate.fail("google_timeout")
        await start?.value
        // While a send is pending.
        #expect(SignInSheetFlows.emailEnabled(google: google))
        let send = SignInSheetFlows.sendCode(google: google, email: rig.model)
        #expect(send != nil)
        #expect(!SignInSheetFlows.googleEnabled(google: google, email: rig.model))
        #expect(SignInSheetFlows.startGoogle(google: google, email: rig.model) == nil)
        #expect(gate.calls.count == 1)
        #expect(await rig.send.pending())
        rig.send.resolve(EmailSignInRig.challenge("ch-1"))
        await send?.value
        // On the code step.
        #expect(rig.model.step == .code)
        #expect(!SignInSheetFlows.googleEnabled(google: google, email: rig.model))
    }
}
