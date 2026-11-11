import AppKit
import Foundation
import ShellXRemoteCore
import ShellXRemoteUI
import SwiftUI
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// Holds an injected call until the test answers it, and counts the calls.
@MainActor private final class SignInSheetGate<Value: Sendable> {
    private(set) var calls = 0
    private var continuation: CheckedContinuation<Value, any Error>?

    func wait() async throws -> Value {
        calls += 1
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }

    /// True once a call waits here (a bounded wait, so a missing call fails the test instead of hanging it).
    func pending() async -> Bool {
        var rounds = 0
        while continuation == nil && rounds < 10_000 {
            rounds += 1
            await Task.yield()
        }
        return continuation != nil
    }

    func resolve(_ value: Value) {
        continuation?.resume(returning: value)
        continuation = nil
    }

    func fail(_ code: String) {
        continuation?.resume(throwing: ShellXCoreError(code: code, message: ""))
        continuation = nil
    }
}

/// What a model's `onFinished` reported, in order.
@MainActor private final class SignInSheetReports {
    var values: [Bool] = []
}

/// The email-first sign-in sheet (D3): it lays out at the sheet's width in every state, the switch sheet has no email
/// path, the email field has the keyboard when the sheet opens and gets it back after Google, the code field never
/// keeps a typed letter, Cancel and Escape close both flows, and the DEBUG fixture signs in only with its code.
@MainActor @Suite("ShellX sign-in sheet", .serialized) struct ShellXSignInSheetTests {
    private func googleModel(
        labels: SignInErrorLabels = .english,
        signIn: @escaping @MainActor () async throws -> String = { "g@shellx.test" }
    ) -> GoogleSignInModel {
        GoogleSignInModel(purpose: .signIn, labels: labels, signIn: signIn, cancel: {})
    }

    private func emailModel(
        labels: SignInErrorLabels = .english,
        verify: @escaping @MainActor (String, String) async throws -> String = { _, _ in "foo@bar.com" }
    ) -> EmailSignInModel {
        EmailSignInModel(
            labels: labels,
            requestCode: { _ in EmailCodeChallenge(challengeID: "c", email: "foo@bar.com", expiresIn: 600, resendIn: 60) },
            verify: verify
        )
    }

    private func size(_ sheet: SignInSheet) -> NSSize {
        NSHostingView(rootView: sheet).fittingSize
    }

    /// Drives a fresh pair of models into each state the layout test measures and calls `visit` with the state's name
    /// and its sheet.
    private func visitEveryState(labels: SignInErrorLabels = .english, _ visit: (String, SignInSheet) -> Void) async {
        visit("first-screen", SignInSheet(model: googleModel(labels: labels), email: emailModel(labels: labels)))

        do {
            let google = googleModel(labels: labels), email = emailModel(labels: labels)
            SignInSheetFlows.setEmail(google: google, email: email, text: "phu@ẽ")
            #expect(SignInSheetFlows.emailFieldError(google: google, email: email) == labels.invalidEmail)
            visit("first-screen-invalid-email", SignInSheet(model: google, email: email))
        }

        do {
            let gate = SignInSheetGate<String>()
            let google = googleModel(labels: labels, signIn: { try await gate.wait() }), email = emailModel(labels: labels)
            let start = SignInSheetFlows.startGoogle(google: google, email: email)
            #expect(await gate.pending())
            #expect(google.phase == .waiting)
            visit("first-screen-google-waiting", SignInSheet(model: google, email: email))
            gate.resolve("g@shellx.test")
            await start?.value
        }

        do {
            let google = googleModel(labels: labels, signIn: { throw ShellXCoreError(code: "google_timeout", message: "") })
            let email = emailModel(labels: labels)
            await SignInSheetFlows.startGoogle(google: google, email: email)?.value
            #expect(google.errorText == labels.timeout)
            visit("first-screen-google-failed", SignInSheet(model: google, email: email))
        }

        do {
            let google = googleModel(labels: labels, signIn: { throw ShellXCoreError(code: "google_timeout", message: "") })
            let email = emailModel(labels: labels)
            SignInSheetFlows.setEmail(google: google, email: email, text: "phu@ẽ")
            await SignInSheetFlows.startGoogle(google: google, email: email)?.value
            #expect(google.errorText == labels.timeout)
            #expect(SignInSheetFlows.emailFieldError(google: google, email: email) == nil)
            visit("first-screen-invalid-email-then-google-failed", SignInSheet(model: google, email: email))
        }

        do {
            let google = googleModel(labels: labels), email = emailModel(labels: labels)
            email.setEmail("Foo@Bar.com")
            await SignInSheetFlows.sendCode(google: google, email: email)?.value
            #expect(email.step == .code)
            visit("code-step", SignInSheet(model: google, email: email))
        }

        do {
            let google = googleModel(labels: labels)
            let email = emailModel(labels: labels, verify: { _, _ in throw ShellXCoreError(code: "code_expired", message: "") })
            email.setEmail("Foo@Bar.com")
            await email.sendCode()?.value
            await email.setCode("123456")?.value
            #expect(email.step == .code)
            #expect(!email.codeIsLive)
            #expect(email.resendWait(at: Date()) == 0)
            visit("code-step-dead-code", SignInSheet(model: google, email: email))
        }

        do {
            let google = googleModel(labels: labels), email = emailModel(labels: labels)
            email.setEmail("Foo@Bar.com")
            await email.sendCode()?.value
            await email.setCode("123456")?.value
            #expect(email.step == .done(email: "foo@bar.com"))
            visit("done", SignInSheet(model: google, email: email))
        }
    }

    /// Each state lays out at the sheet's width with the field it should show: the first screen one email field (off
    /// only while Google waits), the code step one code field (off only for a dead code), done none. The sheet pins
    /// its width, so the fields and one height carry the weight: with "phu@ẽ" typed and then a Google failure the
    /// sheet is exactly as tall as with only the Google failure, so only one failure line is on screen (D3).
    @Test func everyStateLaysOutAtTheSheetWidth() async {
        var heights: [String: CGFloat] = [:]
        await visitEveryState { name, sheet in
            let size = size(sheet)
            heights[name] = size.height
            #expect(abs(size.width - 340) <= 1, "\(name): width \(size.width)")
            #expect(size.height > 0, "\(name): height \(size.height)")
            let fields = Self.laidOutFields(of: sheet)
            if name.hasPrefix("first-screen") {
                #expect(fields.map(\.contentType) == [.emailAddress], "\(name): \(fields.map(\.contentType))")
                #expect(fields.first?.isEnabled == (name != "first-screen-google-waiting"), "\(name): the email field")
            } else if name.hasPrefix("code-step") {
                #expect(fields.map(\.contentType) == [.oneTimeCode], "\(name): \(fields.map(\.contentType))")
                #expect(fields.first?.isEnabled == (name != "code-step-dead-code"), "\(name): the code field")
            } else {
                #expect(fields.isEmpty, "\(name): \(fields.count) fields")
            }
        }
        #expect(heights.count == 8)
        let googleFailed = heights["first-screen-google-failed"] ?? 0
        let bothTyped = heights["first-screen-invalid-email-then-google-failed"] ?? -1
        #expect(abs(bothTyped - googleFailed) < 0.5, "one failure line: \(bothTyped) against \(googleFailed)")
    }

    @Test func theSwitchSheetHasNoEmailPath() {
        let link = SignInSheet(
            model: GoogleSignInModel(purpose: .link, labels: .english, signIn: { "g@shellx.test" }, cancel: {}),
            email: nil
        )
        let size = size(link)
        #expect(abs(size.width - 340) <= 1, "width \(size.width)")
        #expect(size.height > 0)
        #expect(Self.laidOutFields(of: link).isEmpty)
        #expect(Self.laidOutFields(of: SignInSheet(model: googleModel(), email: emailModel())).count == 1)
    }

    @Test func theFixtureSignsInOnlyWithItsCode() async throws {
        let fixture = ShellXRemoteFixtureService()
        let challenge = try await fixture.requestEmailCode(email: " Dev@Shellx.Dev ", locale: "en")
        #expect(challenge.email == "dev@shellx.dev")
        do {
            _ = try await fixture.signInWithEmailCode(challengeID: challenge.challengeID, code: "000000")
            Issue.record("a wrong code signed the fixture in")
        } catch let error as ShellXCoreError {
            #expect(error.code == "invalid_code")
        }
        #expect(!fixture.isSignedIn)
        let address = try await fixture.signInWithEmailCode(
            challengeID: challenge.challengeID, code: ShellXRemoteFixtureService.requestCode
        )
        #expect(address == "dev@shellx.dev")
        #expect(fixture.isSignedIn)
    }

    /// D3 through the presenter, on a host window as the app shows it: the email field has the keyboard when the
    /// sheet opens; Google's wait turns it off and a failure gives the keyboard back; Return sends the code and never
    /// starts Google; the code field then has the keyboard, and Escape in it closes the sheet.
    @Test func theKeyboardFollowsTheSheet() async throws {
        _ = NSApplication.shared
        let host = NSWindow(
            contentRect: NSRect(x: -4000, y: -4000, width: 600, height: 480),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        host.identifier = NSUserInterfaceItemIdentifier("cmux.main.shellxSignInSheetTests")
        host.isReleasedWhenClosed = false
        host.orderFront(nil)
        defer { host.close() }
        let gate = SignInSheetGate<String>()
        let google = googleModel(signIn: { try await gate.wait() })
        let email = emailModel()
        let reports = SignInSheetReports()
        SignInSheetPresenter.shared.present(model: google, email: email, preferredWindow: host)
        defer {
            email.cancel()
            google.cancel()
        }
        let sheet = try #require(host.attachedSheet, "the sheet was not attached to its host window")
        let presented = (google.onFinished, email.onFinished)
        google.onFinished = { reports.values.append($0); presented.0?($0) }
        email.onFinished = { reports.values.append($0); presented.1?($0) }

        #expect(await Self.pump { Self.keyboardField(of: sheet) != nil }, "the email field has no keyboard on open")
        await Self.turns(10)
        #expect(Self.keyboardField(of: sheet) != nil, "the email field lost the keyboard after the sheet opened")

        let start = SignInSheetFlows.startGoogle(google: google, email: email)
        #expect(await gate.pending())
        #expect(await Self.pump { Self.fields(in: sheet).first?.isEnabled == false }, "the email field stayed on")
        #expect(Self.keyboardField(of: sheet) == nil, "a field that is off kept the keyboard")
        gate.fail("google_timeout")
        await start?.value
        #expect(google.errorText != nil)
        #expect(
            await Self.pump { Self.keyboardField(of: sheet) != nil },
            "the email field did not get the keyboard back after Google failed"
        )

        let editor = try #require(sheet.firstResponder as? NSTextView)
        editor.insertText("Foo@Bar.com", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(email.email == "Foo@Bar.com")
        editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        #expect(gate.calls == 1)
        #expect(google.errorText == nil)
        #expect(await Self.pump { email.step == .code })
        #expect(gate.calls == 1)
        #expect(google.phase == .ready)
        #expect(
            await Self.pump { Self.keyboardField(of: sheet)?.contentType == .oneTimeCode },
            "the code field has no keyboard on the code step"
        )

        let codeEditor = try #require(sheet.firstResponder as? NSTextView)
        codeEditor.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        #expect(host.attachedSheet == nil)
        #expect(reports.values == [false, false])
    }

    /// A letter typed into the code field leaves the model's digits as they were; the field must show those digits
    /// again at once, not keep the letter until the next digit.
    @Test func aLetterTypedIntoTheCodeFieldDoesNotStay() async throws {
        let google = googleModel(), email = emailModel()
        email.setEmail("Foo@Bar.com")
        await email.sendCode()?.value
        #expect(email.step == .code)
        let (window, hosting) = Self.offscreen(SignInSheet(model: google, email: email))
        defer { window.close() }
        #expect(await Self.pump { Self.keyboardField(of: window) != nil }, "the code field has no keyboard")
        let editor = try #require(window.firstResponder as? NSTextView)
        let field = try #require(Self.fields(in: hosting).first)
        // One key per host turn, as a person types, so SwiftUI has drawn "12" before the letter comes.
        for typed in ["1", "2"] {
            editor.insertText(typed, replacementRange: NSRange(location: NSNotFound, length: 0))
            await Self.turns(5)
        }
        #expect(field.stringValue == "12")
        editor.insertText("a", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(field.stringValue == "12a")
        #expect(email.code == "12")
        #expect(await Self.pump { field.stringValue == "12" }, "the code field shows \(field.stringValue)")
        editor.insertText("3", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(email.code == "123")
        #expect(await Self.pump { field.stringValue == "123" }, "the code field shows \(field.stringValue)")
    }

    /// Cancel (and Escape, which calls the same action) closes both flows: a verify or a Google sign-in already on
    /// its way runs to its end (Ruling 12), but its answer changes nothing in the closed sheet.
    @Test func cancelClosesBothFlowsSoNoLateAnswerReachesTheSheet() async {
        let verifyGate = SignInSheetGate<String>()
        let reports = SignInSheetReports()
        let google = googleModel(), email = emailModel(verify: { _, _ in try await verifyGate.wait() })
        google.onFinished = { reports.values.append($0) }
        email.onFinished = { reports.values.append($0) }
        email.setEmail("Foo@Bar.com")
        await email.sendCode()?.value
        let verify = email.setCode("123456")
        #expect(await verifyGate.pending())
        SignInSheet(model: google, email: email).cancel()
        #expect(reports.values == [false, false])
        verifyGate.resolve("foo@bar.com")
        await verify?.value
        if case .done = email.step { Issue.record("a closed sheet reached .done") }
        email.finish()
        #expect(reports.values == [false, false])

        let googleGate = SignInSheetGate<String>()
        let waiting = googleModel(signIn: { try await googleGate.wait() }), other = emailModel()
        let start = SignInSheetFlows.startGoogle(google: waiting, email: other)
        #expect(await googleGate.pending())
        let focus = other.focusRequest
        SignInSheet(model: waiting, email: other).cancel()
        googleGate.resolve("g@shellx.test")
        await start?.value
        #expect(waiting.phase == .ready)
        #expect(other.focusRequest == focus)
    }

    // MARK: - Hosting helpers (test scaffolding)

    /// The sheet in an off-screen window, laid out at its fitting size.
    private static func offscreen(_ sheet: SignInSheet) -> (NSWindow, NSHostingView<SignInSheet>) {
        _ = NSApplication.shared
        let hosting = NSHostingView(rootView: sheet)
        let size = hosting.fittingSize
        let window = NSWindow(
            contentRect: NSRect(x: -4000, y: -4000, width: size.width, height: size.height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        hosting.frame = NSRect(origin: .zero, size: size)
        window.orderBack(nil)
        hosting.layoutSubtreeIfNeeded()
        return (window, hosting)
    }

    /// The sheet's AppKit text fields once it is laid out in a window.
    private static func laidOutFields(of sheet: SignInSheet) -> [PlainLayoutTextField] {
        let (window, hosting) = offscreen(sheet)
        defer {
            window.contentView = nil
            window.close()
        }
        return fields(in: hosting)
    }

    private static func fields(in window: NSWindow) -> [PlainLayoutTextField] {
        window.contentView.map { fields(in: $0) } ?? []
    }

    private static func fields(in view: NSView) -> [PlainLayoutTextField] {
        var found: [PlainLayoutTextField] = []
        for subview in view.subviews {
            if let field = subview as? PlainLayoutTextField {
                found.append(field)
            } else {
                found += fields(in: subview)
            }
        }
        return found
    }

    /// The window's sign-in field whose editor has the keyboard, if any.
    private static func keyboardField(of window: NSWindow) -> PlainLayoutTextField? {
        fields(in: window).first { field in
            guard let editor = field.currentEditor() else { return false }
            return window.firstResponder === editor
        }
    }

    /// One turn of host work: the run loop (SwiftUI updates) and, by suspending, the main queue (the fields' focus
    /// hop and the sheet's resize run there).
    private static func turns(_ count: Int = 1) async {
        for _ in 0..<count {
            spinRunLoop()
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    /// Synchronous on purpose: `RunLoop.run(until:)` is unavailable directly in async code.
    private static func spinRunLoop() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }

    /// Runs host turns until `condition` holds or a bounded deadline passes (test scaffolding, not runtime
    /// synchronization); returns whether it holds.
    private static func pump(until condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !condition(), ContinuousClock.now < deadline {
            await turns()
        }
        return condition()
    }
}
