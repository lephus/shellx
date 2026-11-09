import ShellXAppCore
import ShellXAppTestSupport
import ShellXLinkCore
import SwiftUI
import UIKit
import XCTest
@testable import ShellX

/// The terminal page live in a window, against the fake Mac's `t-zsh`: who holds the keyboard, when the key bar
/// shows, and which terminal the keys reach.
@MainActor
final class TerminalPaneTests: XCTestCase {
    /// The rig and a model of its Mac that runs until the test ends and shows `t-zsh` (the page hosted gives the size).
    private func makeModel() async throws -> (WorkspaceRig, TerminalViewModel) {
        let rig = try await WorkspaceRig.make(in: self)
        let model = TerminalViewModel(machineID: rig.model.ref.machineID, link: rig.hub)
        let run = Task { await model.run() }
        addTeardownBlock { run.cancel() }
        model.show("t-zsh")
        return (rig, model)
    }

    private func eventually(_ condition: () async -> Bool) async -> Bool {
        await WorkspaceRig.eventually(condition)
    }

    /// A page that stops taking input (the Mac refused the view) gives the keyboard back and hides the key bar
    /// (final review, app I1).
    func testACoveredSurfaceGivesUpTheKeyboardAndTheKeyBar() async throws {
        let (rig, model) = try await makeModel()
        let host = WindowHost(TerminalPane(model: model, terminalId: "t-zsh", title: "zsh"), in: self)
        let surface = try await host.surface()
        let live = await eventually { model.phase == .live }
        XCTAssertTrue(live)
        let unfocused = surface.bounds.height
        XCTAssertTrue(surface.becomeFirstResponder())
        let keyBar = await eventually { surface.bounds.height < unfocused }
        XCTAssertTrue(keyBar, "the key bar takes room under the surface")

        await rig.mac.endTerminalView("t-zsh", reason: .refused)

        let covered = await eventually { model.phase == .unavailable(.refused) }
        XCTAssertTrue(covered)
        let released = await eventually { !surface.isFirstResponder && surface.bounds.height == unfocused }
        XCTAssertTrue(
            released, "first responder: \(surface.isFirstResponder), height \(surface.bounds.height) of \(unfocused)")
    }

    /// Keys typed into the surface of a page that is no longer the one shown are dropped: they never reach the terminal
    /// shown now (final review, app M3; base spec §4).
    func testAPageNoLongerShownSendsNoKeys() async throws {
        let (rig, model) = try await makeModel()
        let host = WindowHost(TerminalPane(model: model, terminalId: "t-zsh", title: "zsh"), in: self)
        let surface = try await host.surface()
        let live = await eventually { model.phase == .live }
        XCTAssertTrue(live)

        model.show("t-claude")
        surface.insertText("x")
        surface.insertText("\n")

        let opened = await eventually { await rig.mac.terminalViewOpens.contains { $0.terminalId == "t-claude" } }
        XCTAssertTrue(opened)
        try await Task.sleep(for: .milliseconds(300))
        let reached = await rig.mac.terminalViewInputs("t-claude")
        XCTAssertEqual(reached, [])
    }

    /// A text field that takes the keyboard keeps it while the terminal it took it from keeps changing (final review,
    /// app M2: the rename field while a dev server logs).
    func testATerminalNeverTakesTheKeyboardBack() async throws {
        let (_, model) = try await makeModel()
        let host = WindowHost(TerminalPane(model: model, terminalId: "t-zsh", title: "zsh"), in: self)
        let field = UITextField(frame: CGRect(x: 0, y: 700, width: 200, height: 40))
        host.window.addSubview(field)
        let surface = try await host.surface()
        let live = await eventually { model.phase == .live }
        XCTAssertTrue(live)
        let unfocused = surface.bounds.height
        XCTAssertTrue(surface.becomeFirstResponder())
        let focused = await eventually { surface.bounds.height < unfocused }
        XCTAssertTrue(focused, "the pane knows the surface has the keyboard")

        XCTAssertTrue(field.becomeFirstResponder())
        // The terminal changes in the same turn, before the pane hears the surface lost the keyboard.
        model.toggleCtrl()
        host.controller.view.setNeedsLayout()
        host.controller.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(300))

        XCTAssertTrue(field.isFirstResponder, "the field keeps the keyboard")
        XCTAssertFalse(surface.isFirstResponder)
    }
}
