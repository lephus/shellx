import ShellXAppCore
import ShellXAppTestSupport
import ShellXLinkCore
import UIKit
import XCTest
@testable import ShellX

/// The terminal surface as the keyboard sees it: marked text stays on the phone until committed, Backspace edits the
/// composition first, Return is the enter key, the keyboard never corrects, Paste sends one paste unit, and the key bar
/// drives the model; all against the fake Mac's `t-zsh`.
@MainActor
final class TerminalSurfaceTests: XCTestCase {
    /// A live view of `t-zsh` (40 × 10) whose model runs until teardown, and a surface over it.
    private func makeSurface() async throws -> (WorkspaceRig, TerminalViewModel, TerminalSurfaceView) {
        let rig = try await WorkspaceRig.make(in: self)
        let model = TerminalViewModel(machineID: rig.model.ref.machineID, link: rig.hub)
        let run = Task { await model.run() }
        addTeardownBlock { run.cancel() }
        model.setPhoneGrid(cols: 40, rows: 10)
        model.show("t-zsh")
        let live = await WorkspaceRig.eventually { model.phase == .live }
        XCTAssertTrue(live)
        return (rig, model, TerminalSurfaceView(model: model))
    }

    func testMarkedTextStaysOnThePhoneUntilCommitted() async throws {
        let (rig, _, surface) = try await makeSurface()
        surface.setMarkedText("việ", selectedRange: NSRange(location: 3, length: 0))
        let marked = try XCTUnwrap(surface.markedTextRange)
        XCTAssertEqual(surface.text(in: marked), "việ")
        try await Task.sleep(for: .milliseconds(200))
        let early = await rig.mac.terminalViewInputs("t-zsh")
        XCTAssertEqual(early, [])
        surface.insertText("việt")
        XCTAssertNil(surface.markedTextRange)
        let sent = await WorkspaceRig.eventually { await rig.mac.terminalViewInputs("t-zsh") == [[.text("việt")]] }
        XCTAssertTrue(sent)
    }

    func testDeleteBackwardEditsTheCompositionThenSendsBackspace() async throws {
        let (rig, model, surface) = try await makeSurface()
        surface.setMarkedText("việ", selectedRange: NSRange(location: 3, length: 0))
        surface.deleteBackward()
        XCTAssertEqual(model.typing.markedText, "vi")
        surface.unmarkText()
        surface.deleteBackward()
        let sent = await WorkspaceRig.eventually {
            await rig.mac.terminalViewInputs("t-zsh") == [[.text("vi")], [.key(.backspace, mods: [])]]
        }
        XCTAssertTrue(sent)
    }

    func testReturnIsTheEnterKey() async throws {
        let (rig, _, surface) = try await makeSurface()
        surface.insertText("\n")
        let sent = await WorkspaceRig.eventually { await rig.mac.terminalViewInputs("t-zsh") == [[.key(.enter, mods: [])]] }
        XCTAssertTrue(sent)
    }

    func testTheKeyboardNeverCorrectsOrCapitalizes() async throws {
        let (_, _, surface) = try await makeSurface()
        XCTAssertEqual(surface.autocorrectionType, .no)
        XCTAssertEqual(surface.autocapitalizationType, UITextAutocapitalizationType.none)
        XCTAssertEqual(surface.spellCheckingType, .no)
        XCTAssertEqual(surface.smartQuotesType, .no)
        XCTAssertEqual(surface.smartDashesType, .no)
        XCTAssertEqual(surface.smartInsertDeleteType, .no)
        XCTAssertEqual(surface.inlinePredictionType, .no)
        XCTAssertEqual(surface.keyboardType, .default)
        XCTAssertTrue(surface.canBecomeFirstResponder)
        XCTAssertTrue(surface.hasText)
    }

    func testPasteSendsOnePasteUnit() async throws {
        let (rig, _, surface) = try await makeSurface()
        let board = UIPasteboard.withUniqueName()
        let name = board.name
        addTeardownBlock { @MainActor in UIPasteboard.remove(withName: name) }
        board.string = "echo a\necho b"
        surface.pasteboard = board
        XCTAssertTrue(surface.canPerformAction(#selector(UIResponderStandardEditActions.paste(_:)), withSender: nil))
        XCTAssertFalse(surface.canPerformAction(#selector(UIResponderStandardEditActions.copy(_:)), withSender: nil))
        surface.paste(nil)
        let sent = await WorkspaceRig.eventually { await rig.mac.terminalViewInputs("t-zsh") == [[.paste("echo a\necho b")]] }
        XCTAssertTrue(sent)
    }

    func testTheKeyBarDrivesTheModel() async throws {
        let (rig, model, _) = try await makeSurface()
        var hidden = false
        TerminalPane.perform(.key(.ctrl), on: model) {}
        XCTAssertTrue(model.typing.ctrlLatched)
        TerminalPane.perform(.key(.escape), on: model) {}
        TerminalPane.perform(.hideKeyboard, on: model) { hidden = true }
        XCTAssertTrue(hidden)
        let sent = await WorkspaceRig.eventually { await rig.mac.terminalViewInputs("t-zsh") == [[.key(.escape, mods: [.ctrl])]] }
        XCTAssertTrue(sent)
    }
}
