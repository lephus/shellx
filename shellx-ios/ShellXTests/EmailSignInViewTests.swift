import ShellXAppCore
import ShellXAppTestSupport
import ShellXLinkAccount
import SwiftUI
import UIKit
import XCTest
@testable import ShellX

/// The sign-in screen live in a window: what the fields ask of the keyboard, where the keyboard goes, and what typing
/// and the return key do. No relay is reached: the coordinator is a preview over `FakeRelayAccount`.
@MainActor
final class EmailSignInViewTests: XCTestCase {
    private func host(_ coordinator: AppCoordinator, size: CGSize = CGSize(width: 393, height: 852)) -> WindowHost {
        WindowHost(SignInView(coordinator: coordinator, expired: false, startDemo: {}, motion: .still), size: size, in: self)
    }

    /// Every text field in `view`, top to bottom as UIKit holds them.
    private static func textFields(in view: UIView) -> [UITextField] {
        var found: [UITextField] = []
        if let field = view as? UITextField { found.append(field) }
        for subview in view.subviews { found += textFields(in: subview) }
        return found
    }

    private func textFields(_ host: WindowHost) async -> [UITextField] {
        _ = await WorkspaceRig.eventually { !Self.textFields(in: host.window).isEmpty }
        return Self.textFields(in: host.window)
    }

    func testTheEmailFieldAsksForTheEmailKeyboardInEnglishAndWaitsForATap() async throws {
        let relay = FakeRelayAccount()
        let coordinator = AppCoordinator.preview(relay: relay)
        let host = host(coordinator)
        let fields = await textFields(host)
        XCTAssertEqual(fields.count, 1, "the first screen has one field: the email address")
        let field = try XCTUnwrap(fields.first as? EmailAddressTextField)
        XCTAssertEqual(field.keyboardType, .emailAddress)
        XCTAssertEqual(field.textContentType, .emailAddress, "iOS suggests the user's own addresses")
        XCTAssertEqual(field.autocapitalizationType, .none)
        XCTAssertEqual(field.autocorrectionType, .no)
        XCTAssertEqual(field.spellCheckingType, .no)
        XCTAssertEqual(field.smartQuotesType, .no)
        XCTAssertEqual(field.smartDashesType, .no)
        XCTAssertEqual(field.returnKeyType, .send)
        XCTAssertEqual(field.accessibilityIdentifier, "signin.email.field")
        XCTAssertEqual(field.placeholder, String(localized: "signin.email.field"))
        XCTAssertEqual(field.accessibilityLabel, String(localized: "signin.email.field"))

        // The keyboard it asks for: an English one, when the user has one (the simulator has).
        let languages = UITextInputMode.activeInputModes.map(\.primaryLanguage)
        if EmailKeyboard.preferred(among: languages) != nil {
            XCTAssertTrue(field.textInputMode?.primaryLanguage?.hasPrefix("en") ?? false, "\(languages)")
        }

        // Nothing takes the keyboard when the screen appears.
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertFalse(field.isFirstResponder, "no keyboard on arrival")
        XCTAssertEqual(coordinator.emailSignIn.step, .email, "the screen starts at the email step")

        // Typing reaches the model; the return key sends.
        XCTAssertTrue(field.becomeFirstResponder())
        field.insertText("phu@example.com")
        let typed = await WorkspaceRig.eventually { coordinator.emailSignIn.canSend }
        XCTAssertTrue(typed)
        XCTAssertEqual(coordinator.emailSignIn.email, "phu@example.com")
        XCTAssertEqual(field.delegate?.textFieldShouldReturn?(field), false)
        let sent = await WorkspaceRig.eventually { coordinator.emailSignIn.step == .code }
        XCTAssertTrue(sent)
        let calls = await relay.calls
        XCTAssertEqual(calls, [.requestEmailCode(email: "phu@example.com", locale: EmailCodeLocale.current)])
    }

    func testTheReturnKeySendsNothingForALetterOutsideASCII() async throws {
        let relay = FakeRelayAccount()
        let coordinator = AppCoordinator.preview(relay: relay)
        let host = host(coordinator)
        let fields = await textFields(host)
        let field = try XCTUnwrap(fields.first)
        XCTAssertTrue(field.becomeFirstResponder())
        field.insertText("phu@ẽample.com")
        let typed = await WorkspaceRig.eventually { coordinator.emailSignIn.email == "phu@ẽample.com" }
        XCTAssertTrue(typed)
        XCTAssertEqual(coordinator.emailSignIn.emailFieldError, .invalidEmail)
        _ = field.delegate?.textFieldShouldReturn?(field)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(coordinator.emailSignIn.step, .email)
        let calls = await relay.calls
        XCTAssertEqual(calls, [], "nothing goes to the relay")
        XCTAssertTrue(field.isFirstResponder, "the keyboard stays, to fix the address")
    }

    // MARK: - The code step

    /// A host whose model has sent a code to phu@example.com: the code step shows.
    private func hostAtCode(_ coordinator: AppCoordinator, size: CGSize = CGSize(width: 393, height: 852)) async -> WindowHost {
        let model = coordinator.emailSignIn
        model.begin()
        model.email = "phu@example.com"
        await model.sendCode()
        XCTAssertEqual(model.step, .code)
        return host(coordinator, size: size)
    }

    private func codeField(_ host: WindowHost, file: StaticString = #filePath, line: UInt = #line) async throws -> UITextField {
        let found = await WorkspaceRig.eventually { Self.textFields(in: host.window).contains { $0.keyboardType == .numberPad } }
        XCTAssertTrue(found, "the code field shows", file: file, line: line)
        let fields = Self.textFields(in: host.window)
        XCTAssertEqual(fields.count, 1, "the code step has one field", file: file, line: line)
        return try XCTUnwrap(fields.first, file: file, line: line)
    }

    func testTheCodeFieldAsksForDigitsTakesTheKeyboardAndTheSixthDigitSignsIn() async throws {
        let relay = FakeRelayAccount()
        let coordinator = AppCoordinator.preview(relay: relay)
        let host = await hostAtCode(coordinator)
        let field = try await codeField(host)
        XCTAssertEqual(field.keyboardType, .numberPad)
        XCTAssertEqual(field.textContentType, .oneTimeCode, "iOS offers the code from Mail")
        let focused = await WorkspaceRig.eventually { field.isFirstResponder }
        XCTAssertTrue(focused, "the code step takes the keyboard")

        field.insertText("123456")
        let signedIn = await WorkspaceRig.eventually { coordinator.phase == .signedIn(email: "user@example.com") }
        XCTAssertTrue(signedIn, "the sixth digit signs in")
        XCTAssertEqual(coordinator.authMethod, .email)
        let verifies = await relay.calls.filter { if case .signInWithEmailCode = $0 { true } else { false } }
        XCTAssertEqual(verifies.count, 1)
    }

    func testTheCodeFieldShowsOnlyDigitsAndAWrongCodeEmptiesItAndKeepsTheKeyboard() async throws {
        let relay = FakeRelayAccount()
        await relay.setError(RelayAPIError.http(status: 401, code: "invalid_code"), for: .signInWithEmailCode)
        let coordinator = AppCoordinator.preview(relay: relay)
        let model = coordinator.emailSignIn
        let host = await hostAtCode(coordinator)
        let field = try await codeField(host)
        let focused = await WorkspaceRig.eventually { field.isFirstResponder }
        XCTAssertTrue(focused)

        field.insertText("12 3-45")
        let digits = await WorkspaceRig.eventually { field.text == "12345" && model.code == "12345" }
        XCTAssertTrue(digits, "only the digits stay: \(field.text ?? "nil")")
        field.insertText("67")
        let wrong = await WorkspaceRig.eventually { model.error == .invalidCode && field.text == "" }
        XCTAssertTrue(wrong, "a wrong code empties the field: \(field.text ?? "nil")")
        XCTAssertTrue(field.isFirstResponder, "and the keyboard stays for the next try")
        let verifies = await relay.calls.compactMap { call -> String? in
            if case let .signInWithEmailCode(_, code, _, _) = call { return code }
            return nil
        }
        XCTAssertEqual(verifies, ["123456"], "one request, with the six digits")
    }

    func testTurningThePhoneInTheCodeStepKeepsTheDigitsAndTheKeyboard() async throws {
        let coordinator = AppCoordinator.preview()
        let model = coordinator.emailSignIn
        let host = await hostAtCode(coordinator)
        let field = try await codeField(host)
        model.setCode("123")
        let ready = await WorkspaceRig.eventually { field.isFirstResponder && field.text == "123" }
        XCTAssertTrue(ready)

        host.window.frame = CGRect(x: 0, y: 0, width: 852, height: 393)
        host.controller.view.frame = host.window.bounds
        host.window.layoutIfNeeded()
        let moved = await WorkspaceRig.eventually { field.convert(field.bounds, to: host.window).minX > 852 / 2 }
        XCTAssertTrue(moved, "the field went to the right column: \(field.convert(field.bounds, to: host.window))")
        XCTAssertTrue(Self.textFields(in: host.window).first === field, "turning did not rebuild the field")
        XCTAssertTrue(field.isFirstResponder)
        XCTAssertEqual(field.text, "123")
        XCTAssertEqual(model.step, .code)
    }

    func testADifferentEmailReturnsToTheFirstScreenWithTheAddressAndTheKeyboard() async throws {
        let coordinator = AppCoordinator.preview()
        let model = coordinator.emailSignIn
        let host = await hostAtCode(coordinator)
        _ = try await codeField(host)
        model.changeEmail()
        let back = await WorkspaceRig.eventually {
            Self.textFields(in: host.window).contains { $0 is EmailAddressTextField && $0.isFirstResponder }
        }
        XCTAssertTrue(back, "the email field is back, with the keyboard")
        let field = try XCTUnwrap(Self.textFields(in: host.window).first as? EmailAddressTextField)
        XCTAssertEqual(field.text, "phu@example.com", "the address stays")
        XCTAssertEqual(model.step, .email)
    }

    // MARK: - The box takes the tap (review fix round 1, finding 1)

    /// Whether a tap at `point` (window points) reaches `field`.
    private func tapReaches(_ field: UITextField, at point: CGPoint, in window: UIWindow) -> Bool {
        guard let hit = window.hitTest(point, with: nil) else { return false }
        return hit === field || hit.isDescendant(of: field)
    }

    /// The 50-point box drawn around `field`, as wide as its column: a tap near its top or bottom edge or in its left
    /// margin must reach the field, as one in its middle does. Nothing takes the keyboard on arrival, so the whole box is
    /// what the user aims at.
    private func assertTheWholeBoxTakesATap(
        _ field: UITextField, column: ClosedRange<CGFloat>, in window: UIWindow, _ what: String,
        file: StaticString = #filePath, line: UInt = #line
    ) async {
        _ = await WorkspaceRig.eventually { field.window != nil && field.bounds.height > 0 }
        try? await Task.sleep(for: .milliseconds(200))
        let frame = field.convert(field.bounds, to: window)
        let box = CGRect(x: column.lowerBound, y: frame.midY - 25, width: column.upperBound - column.lowerBound, height: 50)
        let places = [
            (CGPoint(x: box.midX, y: box.midY), "in its middle"), (CGPoint(x: box.midX, y: box.minY + 3), "near its top edge"),
            (CGPoint(x: box.midX, y: box.maxY - 3), "near its bottom edge"), (CGPoint(x: box.minX + 6, y: box.midY), "in its left margin"),
        ]
        for (point, place) in places {
            XCTAssertTrue(
                tapReaches(field, at: point, in: window), "\(what): a tap \(place) reaches the field (field \(frame), box \(box))",
                file: file, line: line)
        }
    }

    func testATapAnywhereInTheBoxOfTheEmailOrTheCodeFieldReachesIt() async throws {
        let coordinator = AppCoordinator.preview()
        let host = host(coordinator)
        let fields = await textFields(host)
        let email = try XCTUnwrap(fields.first as? EmailAddressTextField)
        await assertTheWholeBoxTakesATap(email, column: 16...377, in: host.window, "the email field")

        let model = coordinator.emailSignIn
        model.email = "phu@example.com"
        await model.sendCode()
        let code = try await codeField(host)
        await assertTheWholeBoxTakesATap(code, column: 16...377, in: host.window, "the code field")
    }

    func testATapAnywhereInTheBoxOfTheDeletionCodeFieldReachesIt() async throws {
        let coordinator = AppCoordinator.preview()
        addTeardownBlock { @MainActor in await coordinator.hub?.stopAll() }
        try await coordinator.signInWithEmailCode(challengeID: "challenge-0", code: "123456")
        let model = coordinator.makeDeleteAccountCode()
        await model.sendCode()
        XCTAssertEqual(model.step, .code)
        let host = WindowHost(DeleteAccountSheet(code: model, close: {}), size: CGSize(width: 393, height: 852), in: self)
        let code = try await codeField(host)
        await assertTheWholeBoxTakesATap(code, column: 20...373, in: host.window, "the deletion sheet's code field")
    }

    // MARK: - While the code is asked for (review fix round 1, finding 2)

    func testWhileTheCodeIsAskedForTheFieldTakesNoEditsAndKeepsTheKeyboard() async throws {
        let relay = FakeRelayAccount()
        let latch = Latch()
        await relay.setHook({ await latch.wait() }, for: .requestEmailCode)
        let coordinator = AppCoordinator.preview(relay: relay)
        let model = coordinator.emailSignIn
        let host = host(coordinator)
        let fields = await textFields(host)
        let field = try XCTUnwrap(fields.first as? EmailAddressTextField)
        XCTAssertTrue(field.becomeFirstResponder())
        field.insertText("phu@example.com")
        let typed = await WorkspaceRig.eventually { model.canSend }
        XCTAssertTrue(typed)
        _ = field.delegate?.textFieldShouldReturn?(field)
        let held = await WorkspaceRig.eventually { await latch.waiting == 1 }
        XCTAssertTrue(held)
        XCTAssertEqual(model.step, .sending)

        field.insertText("x")
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(field.text, "phu@example.com", "the field takes no edit while the code is asked for")
        XCTAssertEqual(model.email, "phu@example.com")
        XCTAssertTrue(field.isFirstResponder, "and it keeps the keyboard")

        await latch.release()
        let sent = await WorkspaceRig.eventually { model.step == .code }
        XCTAssertTrue(sent)
    }
}

/// Holds the relay's answer until the test releases it.
private actor Latch {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var released = false

    var waiting: Int { waiters.count }

    func wait() async {
        guard !released else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        released = true
        for waiter in waiters { waiter.resume() }
        waiters = []
    }
}
