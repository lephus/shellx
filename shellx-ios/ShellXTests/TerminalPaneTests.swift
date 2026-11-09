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

    /// What the panes said to VoiceOver.
    private final class Lines {
        var items: [String] = []
    }

    /// Only the page shown says a paste is too large: a neighbour the pager keeps alive says nothing (final review,
    /// app M1).
    func testOnlyThePageShownSaysAPasteIsTooLarge() async throws {
        var screen = TerminalScreen()
        screen.apply(DemoTerminalScreens.shell.snapshot)
        let model = TerminalViewModel.fixed(terminalId: "t-zsh", screen: screen)
        let lines = Lines()
        _ = WindowHost(
            VStack(spacing: 0) {
                TerminalPane(model: model, terminalId: "t-zsh", title: "zsh", announce: { lines.items.append("t-zsh: \($0)") })
                TerminalPane(model: model, terminalId: "t-web", title: "zsh", announce: { lines.items.append("t-web: \($0)") })
            },
            in: self)
        try await Task.sleep(for: .milliseconds(200))

        model.paste(String(repeating: "x", count: TerminalInputBatcher.maxPasteBytes + 1))

        let said = await eventually { !lines.items.isEmpty }
        XCTAssertTrue(said)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(lines.items, ["t-zsh: \(String(localized: "terminal.paste.tooLarge"))"])
    }

    /// A shell the user is typing into stays shown when an agent of the workspace starts waiting for an answer: the
    /// keyboard is not pulled away mid-command (final review, app I2).
    func testTypingIntoAShellKeepsItShownWhenAnAgentAsks() async throws {
        let rig = try await WorkspaceRig.make(in: self)
        let host = WindowHost(NavigationStack { WorkspaceView(scope: rig.scope, ref: rig.model.ref, open: { _ in }) }, in: self)
        let surface = try await host.surface()
        let live = await eventually { surface.model.phase == .live && surface.model.terminalId == "t-zsh" }
        XCTAssertTrue(live, "the Mac's selection, a shell, is shown")
        XCTAssertTrue(surface.becomeFirstResponder())
        surface.insertText("ec")
        let typed = await eventually { await rig.mac.terminalViewInputs("t-zsh") == [[.text("ec")]] }
        XCTAssertTrue(typed)

        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        await rig.mac.upsertSession(
            AgentSession(
                sessionId: "s1", agent: "claude", workspaceId: "ws-shellx", workspaceTitle: "shellx-ios",
                state: .needsInput, stateSinceMs: nowMs, lastActivityMs: nowMs))
        let asking = await eventually { rig.hub.liveSessions.first?.session.state == .needsInput }
        XCTAssertTrue(asking)
        try await Task.sleep(for: .milliseconds(300))

        XCTAssertEqual(surface.model.terminalId, "t-zsh", "the shell being typed into stays shown")
    }

    /// A page that is reopening (its view ended `failed`; the last screen stays, uncovered) takes no input: the keyboard
    /// and the key bar go, so nothing typed is lost while it looks ready (final review, app I1 and core M1).
    func testAReopeningPageGivesUpTheKeyboardAndTheKeyBar() async throws {
        let (rig, model) = try await makeModel()
        let host = WindowHost(TerminalPane(model: model, terminalId: "t-zsh", title: "zsh"), in: self)
        let surface = try await host.surface()
        let live = await eventually { model.phase == .live }
        XCTAssertTrue(live)
        let unfocused = surface.bounds.height
        XCTAssertTrue(surface.becomeFirstResponder())
        let keyBar = await eventually { surface.bounds.height < unfocused }
        XCTAssertTrue(keyBar, "the key bar takes room under the surface")

        await rig.mac.endTerminalView("t-zsh", reason: .failed)

        let reopening = await eventually { model.phase == .connecting }
        XCTAssertTrue(reopening, "\(model.phase)")
        let released = await eventually { !surface.isFirstResponder && surface.bounds.height == unfocused }
        XCTAssertTrue(
            released, "first responder: \(surface.isFirstResponder), height \(surface.bounds.height) of \(unfocused)")
    }

    /// Only a live page takes input (final review, app I1): the key bar and the keyboard need an open view.
    func testOnlyALivePageTakesInput() {
        XCTAssertTrue(TerminalSurfaceView.takesInput(.live))
        let others: [TerminalViewPhase] = [
            .connecting, .offline, .unsupported, .unavailable(.gone), .unavailable(.refused), .unavailable(.failed),
        ]
        for phase in others { XCTAssertFalse(TerminalSurfaceView.takesInput(phase), "\(phase)") }
    }

    /// Review Focus 1 through the screen: after A → B → A there is exactly one surface, on the page shown, and keys typed
    /// into it reach A only (final review, app M8).
    func testSwipingBackAndForthLeavesOneSurfaceOnThePageShown() async throws {
        let rig = try await WorkspaceRig.make(in: self)
        let terminal = TerminalViewModel(machineID: rig.model.ref.machineID, link: rig.hub)
        let run = Task { await terminal.run() }
        addTeardownBlock { run.cancel() }
        let selection = Selection("t-zsh")
        terminal.show("t-zsh")
        let host = WindowHost(SwipeHarness(panes: rig.model.panes, selection: selection, terminal: terminal), in: self)
        func shows(_ id: String) async -> Bool {
            await eventually { terminal.phase == .live && host.surfaces.map(\.terminalId) == [id] }
        }
        let first = await shows("t-zsh")
        XCTAssertTrue(first, "\(host.surfaces.map(\.terminalId))")

        selection.id = "t-claude"; terminal.show("t-claude")
        let second = await shows("t-claude")
        XCTAssertTrue(second, "\(host.surfaces.map(\.terminalId))")
        selection.id = "t-zsh"; terminal.show("t-zsh")
        let back = await shows("t-zsh")
        XCTAssertTrue(back, "\(host.surfaces.map(\.terminalId)) \(terminal.phase)")

        let surface = try XCTUnwrap(host.surfaces.first)
        surface.insertText("ls")
        let typed = await eventually { await rig.mac.terminalViewInputs("t-zsh") == [[.text("ls")]] }
        XCTAssertTrue(typed)
        let elsewhere = await rig.mac.terminalViewInputs("t-claude")
        XCTAssertEqual(elsewhere, [])
    }
}

/// The chip shown, set by the test as a swipe would.
@MainActor @Observable
private final class Selection {
    var id: String
    init(_ id: String) { self.id = id }
}

/// `WorkspaceScreen` composed as `WorkspaceView` composes it: one terminal model for every page, a `TerminalPane` per
/// terminal page, `claude` shown as its terminal so both chips are terminals.
private struct SwipeHarness: View {
    let panes: [WorkspacePane]
    let selection: Selection
    let terminal: TerminalViewModel

    var body: some View {
        NavigationStack {
            WorkspaceScreen(
                title: "shellx-ios", panes: panes, selected: selection.id, shownAsTerminal: ["t-claude"],
                alert: .constant(nil), agent: { _ in Color.clear },
                shell: { pane in TerminalPane(model: terminal, terminalId: pane.id, title: pane.title) })
        }
    }
}
