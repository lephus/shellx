import Foundation
import ShellXLinkCore
import ShellXLinkSession
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@Suite("ShellX Link key chords")
struct ShellXLinkKeyChordTests {
    @Test(arguments: [
        (TerminalKey.enter, [TerminalModifier](), "enter"), (.letter("c"), [.ctrl], "ctrl+c"), (.tab, [.shift], "shift+tab"),
        (.left, [.shift, .alt, .ctrl], "ctrl+alt+shift+left"), (.pageUp, [], "page_up"), (.space, [.ctrl], "ctrl+space")
    ])
    func keyChordsUseTheMacNames(key: TerminalKey, mods: [TerminalModifier], name: String) {
        #expect(ShellXLinkKeyChord(key: key, mods: mods)?.macKeyName == name)
    }

    @Test func unknownKeysOrModifiersHaveNoChord() {
        #expect(ShellXLinkKeyChord(key: .other("f13"), mods: []) == nil)
        #expect(ShellXLinkKeyChord(key: .letter("c"), mods: [.other("hyper")]) == nil)
    }
}

@MainActor
@Suite("ShellX Link terminal view input", .serialized, .timeLimit(.minutes(2)))
struct ShellXLinkTerminalViewInputTests {
    private func withView(
        sizing: RecordingSizing? = nil, policy: TestPolicy? = nil,
        _ body: @MainActor (ScrollbackTestTerminal, ShellXLinkTerminalView) async throws -> Void
    ) async throws {
        let sizing = sizing ?? RecordingSizing()
        let policy = policy ?? TestPolicy()
        try await AppContextSerialGate.withExclusiveAppContext {
            let terminal = try ScrollbackTestTerminal()
            defer { terminal.close() }
            try await terminal.launch()
            try await terminal.setGrid(columns: 20, rows: 5)
            try terminal.output("\u{1b}c")
            let leaked = try await terminal.inputBytesBeforeBarrier()
            #expect(leaked.isEmpty)
            let view = terminal.openLinkView(cols: 20, rows: 5, sizing: sizing, policy: policy)
            _ = try await view.nextEvent()
            try await body(terminal, view)
            await view.close()
        }
    }

    @Test func inputReachesTheTerminalInOrder() async throws {
        try await withView { terminal, view in
            await view.input([.text("ls"), .key(.enter, mods: []), .key(.letter("c"), mods: [.ctrl])])
            let bytes = try await terminal.inputBytesBeforeBarrier()
            #expect(bytes == Data("ls\r\u{03}".utf8))
        }
    }

    @Test func pasteGoesThroughTheMacsPastePath() async throws {
        try await withView { terminal, view in
            try terminal.output("\u{1b}[?2004h")
            await view.input([.paste("a\nb")])
            let bytes = String(decoding: try await terminal.inputBytesBeforeBarrier(), as: UTF8.self)
            #expect(bytes.contains("\u{1b}[200~") && bytes.contains("a") && bytes.contains("b") && bytes.contains("\u{1b}[201~"))
        }
    }

    @Test func unknownUnitsAreSkippedAndTheRestApplied() async throws {
        try await withView { terminal, view in
            await view.input([
                .key(.other("f13"), mods: []), .key(.letter("c"), mods: [.other("hyper")]),
                .other(kind: "gesture"), .text("ok")
            ])
            let bytes = try await terminal.inputBytesBeforeBarrier()
            #expect(bytes == Data("ok".utf8))
        }
    }

    @Test func theWheelTurnsOnlyOnTheAlternateScreen() async throws {
        try await withView { terminal, view in
            await view.input([.scroll(lines: 3)])
            let leaked = try await terminal.inputBytesBeforeBarrier()
            #expect(leaked.isEmpty)
            try terminal.output("\u{1b}[?1049h\u{1b}[?1007h")
            view.terminalSurfaceMayHaveChanged()
            guard case let .frame(alt) = try await view.nextEvent(), alt.head.alt else {
                Issue.record("no alternate snapshot")
                return
            }
            await view.input([.scroll(lines: 3)])
            let up = String(decoding: try await terminal.inputBytesBeforeBarrier(), as: UTF8.self)
            #expect(up.contains("\u{1b}[A") || up.contains("\u{1b}OA"))
            await view.input([.scroll(lines: -2)])
            let down = String(decoding: try await terminal.inputBytesBeforeBarrier(), as: UTF8.self)
            #expect(down.contains("\u{1b}[B") || down.contains("\u{1b}OB"))
        }
    }

    @Test func inputIsThePhonesActivity() async throws {
        let sizing = RecordingSizing()
        try await withView(sizing: sizing) { terminal, _ in
            var recorded: [Bool] = []
            var instrumented = terminal.linkTerminal
            instrumented.type = { _ in recorded.append(sizing.isInsideInput) }
            let view = ShellXLinkTerminalView(
                surfaceID: terminal.surface.id, terminal: instrumented, sizing: sizing.sizing,
                frameSinks: RecordingFrameSinkRegistry(), isBlocked: { false }, notificationCenter: NotificationCenter()
            )
            view.open(cols: 20, rows: 5)
            await view.input([.text("x")])
            #expect(recorded == [true] && sizing.calls.contains(.input))
            await view.close()
        }
    }

    @Test func resizeReportsThePhonesSize() async throws {
        let sizing = RecordingSizing()
        try await withView(sizing: sizing) { _, view in
            await view.resize(cols: 80, rows: 24)
            #expect(sizing.calls.last == .resize(cols: 80, rows: 24))
        }
    }

    @Test func deviceManagementEndsTheViewAsRefused() async throws {
        let policy = TestPolicy()
        try await withView(policy: policy) { terminal, view in
            let pending = Task { @MainActor in await view.nextFrame() }
            await Task.yield()
            policy.change(blocked: true)
            #expect(await pending.value == .ended(.refused))
            await view.input([.text("x")])
            let leaked = try await terminal.inputBytesBeforeBarrier()
            #expect(leaked.isEmpty)
        }
    }

    @Test func inputWhileBlockedIsNotApplied() async throws {
        let policy = TestPolicy()
        try await withView(policy: policy) { terminal, view in
            policy.blocked = true
            await view.input([.text("x")])
            let leaked = try await terminal.inputBytesBeforeBarrier()
            #expect(leaked.isEmpty)
            let ended = try await view.nextEvent()
            #expect(ended == .ended(.refused))
        }
    }

    @Test func inputAfterCloseIsNotApplied() async throws {
        try await withView { terminal, view in
            await view.close()
            await view.input([.text("x")])
            let leaked = try await terminal.inputBytesBeforeBarrier()
            #expect(leaked.isEmpty)
        }
    }
}
