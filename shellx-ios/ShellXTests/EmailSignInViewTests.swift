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
}
