import ShellXAppCore
import ShellXAppTestSupport
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
}
