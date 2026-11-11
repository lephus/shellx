import ShellXAppCore
import ShellXAppTestSupport
import ShellXLinkAccount
import SwiftUI
import UIKit
import XCTest
@testable import ShellX

@MainActor
final class DeleteAccountRenderTests: XCTestCase {
    private func assertRenders(_ view: some View, name: String) throws {
        let images = try SnapshotWriter().write(view, name: name)
        XCTAssertEqual(images.count, 2)
        for image in images { XCTAssertEqual(image.size, SnapshotWriter.size) }
        XCTAssertNotEqual(images.first?.pngData(), images.last?.pngData(), "light and dark renders should differ")
    }

    func testDeleteSheetRendersEveryStep() throws {
        let steps: [(DeleteAccountSheet.Step, String)] = [
            (.confirm, "delete-account-confirm"), (.switchFirst, "delete-account-switch-first"), (.working, "delete-account-working"),
            (.failed(SignInErrorText.message(for: .reauthRequired) ?? ""), "delete-account-failed"),
        ]
        for (step, name) in steps { try assertRenders(DeleteAccountSheet(step: step), name: name) }
    }

    /// A preview coordinator signed in with an emailed code (the fake relay's account, user@example.com), its hub
    /// stopped when the test ends, its relay's calls forgotten.
    private func emailSession(_ relay: FakeRelayAccount) async throws -> AppCoordinator {
        let coordinator = AppCoordinator.preview(relay: relay)
        addTeardownBlock { @MainActor in await coordinator.hub?.stopAll() }
        try await coordinator.signInWithEmailCode(challengeID: "challenge-0", code: "123456")
        XCTAssertEqual(coordinator.authMethod, .email)
        await relay.resetCalls()
        return coordinator
    }

    func testAnEmailSessionsDeleteAsksForACodeAndMailsNothingYet() async throws {
        let relay = FakeRelayAccount()
        let coordinator = try await emailSession(relay)
        let actions = AccountActions(coordinator: coordinator)
        XCTAssertEqual(actions.authMethod, .email)
        let model = try XCTUnwrap(actions.deleteCode?(), "an email session deletes with a code")
        XCTAssertFalse(model === coordinator.emailSignIn)
        XCTAssertEqual(model.step, .email)
        XCTAssertEqual(model.email, "user@example.com", "the account's own address")
        let calls = await relay.calls
        XCTAssertEqual(calls, [], "opening the sheet mails nothing")
    }

    func testDeleteByCodeRendersEveryStep() async throws {
        let relay = FakeRelayAccount()
        let coordinator = try await emailSession(relay)
        let model = coordinator.makeDeleteAccountCode()
        let surface = try XCTUnwrap(Bitmap.Colour(UIColor(named: "Surface"), style: .light))

        let confirm = try SnapshotWriter().write(DeleteAccountSheet(code: model, close: {}), name: "delete-account-code-confirm")
        await model.sendCode()
        XCTAssertEqual(model.step, .code)
        let code = try SnapshotWriter().write(DeleteAccountSheet(code: model, close: {}), name: "delete-account-code")
        await relay.setError(RelayAPIError.http(status: 401, code: "invalid_code"), for: .deleteAccountWithCode)
        model.setCode("123456")
        XCTAssertEqual(model.step, .code, "the sixth digit never deletes")
        await model.verify()
        XCTAssertEqual(model.error, .invalidCode)
        let wrong = try SnapshotWriter().write(DeleteAccountSheet(code: model, close: {}), name: "delete-account-code-error")
        XCTAssertEqual(coordinator.authMethod, .email, "a wrong code deletes nothing")

        XCTAssertNotEqual(confirm.first?.pngData(), code.first?.pngData())
        XCTAssertNotEqual(code.first?.pngData(), wrong.first?.pngData())
        let light = try [confirm, code].map { try XCTUnwrap(Bitmap($0[0])) }
        XCTAssertNil(light[0].band(of: surface), "no field before the code is mailed")
        XCTAssertNotNil(light[1].band(of: surface, atLeast: 60), "the code field once it is")
    }
}
