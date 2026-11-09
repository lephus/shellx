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
}
