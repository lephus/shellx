import CMUXMobileCore
import Foundation
import ShellXLinkCore
import ShellXLinkSession
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@MainActor
@Suite("ShellX Link terminal view frames", .serialized, .timeLimit(.minutes(2)))
struct ShellXLinkTerminalViewFrameTests {
    /// A launched 20x5 terminal, reset, with the view's tests running inside the exclusive app context.
    private func withTerminal(
        columns: Int = 20, rows: Int = 5, _ body: @MainActor (ScrollbackTestTerminal) async throws -> Void
    ) async throws {
        try await AppContextSerialGate.withExclusiveAppContext {
            let terminal = try ScrollbackTestTerminal()
            defer { terminal.close() }
            try await terminal.launch()
            try await terminal.setGrid(columns: columns, rows: rows)
            try terminal.output("\u{1b}c")
            try await body(terminal)
        }
    }

    private func snapshot(of view: ShellXLinkTerminalView) async throws -> TerminalGridFrame {
        guard case let .frame(frame) = try await view.nextEvent() else {
            Issue.record("no frame")
            throw LinkViewTimeout()
        }
        return frame
    }

    @Test func theFirstFrameIsASnapshotWithTheHistory() async throws {
        try await withTerminal { terminal in
            try terminal.output("\u{1b}c" + (1...30).map { "line \($0)\r\n" }.joined())
            try await terminal.waitForScreen(containing: "line 30")
            let sizing = RecordingSizing()
            let view = terminal.openLinkView(cols: 20, rows: 5, sizing: sizing)
            let first = try await snapshot(of: view)
            #expect(first.head.kind == .snapshot && first.head.history >= 25 && sizing.calls == [.attach(cols: 20, rows: 5)])
            var screen = TerminalScreen()
            screen.apply(first)
            #expect((screen.historyText() + screen.screenText()).filter { !$0.isEmpty } == (1...30).map { "line \($0)" })
            await view.close()
        }
    }

    @Test func newOutputComesAsADelta() async throws {
        try await withTerminal { terminal in
            let view = terminal.openLinkView(cols: 20, rows: 5)
            var screen = TerminalScreen()
            screen.apply(try await snapshot(of: view))
            try terminal.output("hello")
            try await terminal.waitForScreen(containing: "hello")
            view.terminalSurfaceMayHaveChanged()
            let delta = try await snapshot(of: view)
            #expect(delta.head.kind == .delta)
            screen.apply(delta)
            #expect(screen.screenText().contains { $0.contains("hello") })
            await view.close()
        }
    }

    @Test func changesWhileThePumpIsBusyMergeIntoOneDelta() async throws {
        try await withTerminal { terminal in
            let view = terminal.openLinkView(cols: 20, rows: 5)
            var screen = TerminalScreen()
            screen.apply(try await snapshot(of: view))
            for chunk in ["a\r\n", "b\r\n", "c"] {
                try terminal.output(chunk)
                view.terminalSurfaceMayHaveChanged()
            }
            try await terminal.waitForScreen(containing: "c")
            let delta = try await snapshot(of: view)
            #expect(delta.head.kind == .delta)
            screen.apply(delta)
            #expect(Array(screen.screenText().prefix(3)) == ["a", "b", "c"])
            #expect(await view.returnsNothing(for: .milliseconds(300)))
            await view.close()
        }
    }

    @Test func anUnchangedTerminalSendsNothing() async throws {
        try await withTerminal { terminal in
            let view = terminal.openLinkView(cols: 20, rows: 5)
            _ = try await snapshot(of: view)
            view.terminalSurfaceMayHaveChanged()
            #expect(await view.returnsNothing(for: .milliseconds(300)))
            await view.close()
        }
    }

    @Test func aResyncWakesAWaitingViewWithASnapshot() async throws {
        try await withTerminal { terminal in
            let view = terminal.openLinkView(cols: 20, rows: 5)
            _ = try await snapshot(of: view)
            let pending = Task { @MainActor in await view.nextFrame() }
            await Task.yield()
            await view.requestSnapshot()
            let event = await pending.value
            guard case let .frame(frame) = event else { return Issue.record("no frame: \(event)") }
            #expect(frame.head.kind == .snapshot)
            await view.close()
        }
    }

    @Test func aNewSizeComesAsASnapshot() async throws {
        try await withTerminal { terminal in
            let view = terminal.openLinkView(cols: 20, rows: 5)
            _ = try await snapshot(of: view)
            try await terminal.setGrid(columns: 30, rows: 6)
            view.terminalSurfaceMayHaveChanged()
            let frame = try await snapshot(of: view)
            #expect(frame.head.kind == .snapshot && frame.head.cols == 30 && frame.head.rows == 6)
            await view.close()
        }
    }

    @Test func theAlternateScreenComesAsASnapshotWithoutHistory() async throws {
        try await withTerminal { terminal in
            let view = terminal.openLinkView(cols: 20, rows: 5)
            _ = try await snapshot(of: view)
            try terminal.output("\u{1b}[?1049hvim")
            try await terminal.waitForScreen(containing: "vim")
            view.terminalSurfaceMayHaveChanged()
            let frame = try await snapshot(of: view)
            #expect(frame.head.kind == .snapshot && frame.head.alt && frame.head.history == 0)
            await view.close()
        }
    }

    @Test func aPaletteChangeComesAsASnapshot() async throws {
        try await withTerminal { terminal in
            let view = terminal.openLinkView(cols: 20, rows: 5)
            _ = try await snapshot(of: view)
            try terminal.output("\u{1b}]4;1;rgb:12/34/56\u{1b}\\")
            view.terminalSurfaceMayHaveChanged()
            let frame = try await snapshot(of: view)
            #expect(frame.head.kind == .snapshot && frame.head.palette?.colors[1] == "#123456")
            await view.close()
        }
    }

    @Test func aBurstKeepsTheHistoryContiguous() async throws {
        try await withTerminal(columns: 20, rows: 3) { terminal in
            try terminal.output("\u{1b}ca1\r\na2\r\na3")
            try await terminal.waitForScreen(containing: "a3")
            let view = terminal.openLinkView(cols: 20, rows: 3)
            var screen = TerminalScreen()
            screen.apply(try await snapshot(of: view))
            try terminal.output((1...10).map { "\r\nb\($0)" }.joined())
            try await terminal.waitForScreen(containing: "b10")
            view.terminalSurfaceMayHaveChanged()
            let delta = try await snapshot(of: view)
            #expect(delta.head.kind == .delta && delta.head.scroll > 3)
            screen.apply(delta)
            #expect(screen.historyText() == ["a1", "a2", "a3", "b1", "b2", "b3", "b4", "b5", "b6", "b7"])
            #expect(screen.screenText() == ["b8", "b9", "b10"])
            await view.close()
        }
    }

    @Test func floodEndsOnTheLastScreen() async throws {
        try await withTerminal { terminal in
            let view = terminal.openLinkView(cols: 20, rows: 5)
            var screen = TerminalScreen()
            screen.apply(try await snapshot(of: view))
            var frames = 0
            func pump() async {
                while let event = await view.nextEventIfAny(within: .milliseconds(300)) {
                    screen.apply(event)
                    frames += 1
                }
            }
            for chunk in 0..<20 {
                let lines = (1...100).map { String(format: "L%04d", chunk * 100 + $0) }
                try terminal.output("\r\n" + lines.joined(separator: "\r\n"))
                try await terminal.waitForScreen(containing: lines[99])
                view.terminalSurfaceMayHaveChanged()
                if chunk % 5 == 4 { await pump() }
            }
            await pump()
            let capture = try #require(terminal.capture(history: 4000))
            var expected = TerminalScreen()
            expected.apply(ShellXLinkGridConverter(theme: try #require(capture.terminalTheme)).snapshot(capture))
            #expect(screen.screenText() == expected.screenText())
            #expect(screen.historyText() == expected.historyText())
            #expect(frames <= 10)
            await view.close()
        }
    }

    @Test func aTerminalWithoutALiveSurfaceShowsOnceItStarts() async throws {
        try await AppContextSerialGate.withExclusiveAppContext {
            let terminal = try ScrollbackTestTerminal()
            defer { terminal.close() }
            let view = terminal.openLinkView(cols: 20, rows: 5)
            #expect(await view.returnsNothing(for: .milliseconds(300)))
            try await terminal.launch()
            try terminal.output("\u{1b}cready")
            try await terminal.waitForScreen(containing: "ready")
            view.terminalSurfaceMayHaveChanged()
            let frame = try await snapshot(of: view)
            var screen = TerminalScreen()
            screen.apply(frame)
            #expect(frame.head.kind == .snapshot && screen.screenText().contains { $0.contains("ready") })
            await view.close()
        }
    }

    @Test func theFirstSnapshotWaitsForTheDecidedSize() async throws {
        try await withTerminal { terminal in
            let sizing = RecordingSizing()
            sizing.expectedGrid = (30, 6)
            let view = terminal.openLinkView(cols: 30, rows: 6, sizing: sizing)
            let pending = Task { @MainActor in await view.nextFrame() }
            await Task.yield()
            try await terminal.setGrid(columns: 30, rows: 6)
            view.terminalSurfaceMayHaveChanged()
            guard case let .frame(frame) = await pending.value else { return Issue.record("no frame") }
            #expect(frame.head.kind == .snapshot && frame.head.cols == 30 && frame.head.rows == 6)
            await view.close()
        }
    }

    @Test func theFirstSnapshotStopsWaitingAfterTheFence() async throws {
        try await withTerminal { terminal in
            let sizing = RecordingSizing()
            sizing.expectedGrid = (30, 6)
            let view = terminal.openLinkView(cols: 30, rows: 6, sizing: sizing)
            let frame = try await snapshot(of: view)
            #expect(frame.head.kind == .snapshot && frame.head.cols == 20 && frame.head.rows == 5)
            await view.close()
        }
    }

    @Test func closeEndsAWaitingViewAndLeavesOnce() async throws {
        try await withTerminal { terminal in
            let sizing = RecordingSizing()
            let registry = RecordingFrameSinkRegistry()
            let view = terminal.openLinkView(cols: 20, rows: 5, sizing: sizing, registry: registry)
            _ = try await snapshot(of: view)
            let pending = Task { @MainActor in await view.nextFrame() }
            await Task.yield()
            await view.close()
            _ = await pending.value
            #expect(sizing.calls.last == .detach && registry.sinks.isEmpty)
            let count = sizing.calls.count
            await view.close()
            #expect(sizing.calls.count == count)
        }
    }

    @Test func cancellingAWaitReturnsPromptly() async throws {
        try await withTerminal { terminal in
            let view = terminal.openLinkView(cols: 20, rows: 5)
            _ = try await snapshot(of: view)
            #expect(await view.returnsNothing(for: .milliseconds(200)))
            try terminal.output("later")
            try await terminal.waitForScreen(containing: "later")
            view.terminalSurfaceMayHaveChanged()
            let delta = try await snapshot(of: view)
            #expect(delta.head.kind == .delta)
            await view.close()
        }
    }

    @Test func aGoneTerminalEnds() async throws {
        try await withTerminal { terminal in
            let view = terminal.openLinkView(cols: 20, rows: 5)
            view.end(.gone)
            #expect(try await view.nextEvent() == .ended(.gone))
            await view.close()

            var gone = terminal.linkTerminal
            gone.surface = { nil }
            let other = ShellXLinkTerminalView(
                surfaceID: UUID(), terminal: gone, sizing: RecordingSizing().sizing, frameSinks: RecordingFrameSinkRegistry(),
                isBlocked: { false }, notificationCenter: NotificationCenter()
            )
            other.open(cols: 20, rows: 5)
            #expect(try await other.nextEvent() == .ended(.gone))
            await other.close()
        }
    }

    @Test func theViewLeavesIrohStateAlone() async throws {
        try await withTerminal { terminal in
            let observer = MobileTerminalRenderObserver.shared
            defer {
                observer.stop()
                observer.start()
            }
            let seeded = try #require(terminal.capture(history: 0))
            observer.adoptReplayBaseline(seeded, surfaceID: terminal.surface.id)
            let before = observer.debugRenderGridStateSurfaceCountForTesting
            let view = terminal.openLinkView(cols: 20, rows: 5)
            _ = try await snapshot(of: view)
            try terminal.output("delta")
            try await terminal.waitForScreen(containing: "delta")
            view.terminalSurfaceMayHaveChanged()
            _ = try await snapshot(of: view)
            #expect(observer.terminalThemesBySurfaceID[terminal.surface.id] == seeded.terminalTheme)
            #expect(observer.debugRenderGridStateSurfaceCountForTesting == before)
            await view.close()
        }
    }
}
