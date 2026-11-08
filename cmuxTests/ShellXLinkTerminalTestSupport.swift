import AppKit
import CMUXMobileCore
import CmuxSettings
import CmuxTerminal
import Foundation
import GhosttyKit
import ShellXLinkCore
import ShellXLinkSession
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

// MARK: - Real Ghostty helpers

extension ScrollbackTestTerminal {
    /// ghostty_surface_set_grid_size, then waits up to 5 s until a capture shows the size.
    func setGrid(columns: Int, rows: Int) async throws {
        let runtime = try #require(surface.surface)
        #expect(ghostty_surface_set_grid_size(runtime, UInt16(columns), UInt16(rows), nil))
        try await linkWaitUntil {
            let frame = self.surface.mobileRenderGridFrame(stateSeq: 0, scrollbackLines: 0, includeTheme: false)?.frame
            return frame?.columns == columns && frame?.rows == rows
        }
    }

    /// Waits up to 5 s until `surface.readText(region: .screen)` contains `text`.
    func waitForScreen(containing text: String) async throws {
        try await linkWaitUntil { self.surface.readText(region: .screen)?.contains(text) == true }
    }

    /// The full, screen-anchored capture of the terminal with `history` rows of scrollback.
    func capture(history: Int) -> MobileTerminalRenderGridFrame? {
        surface.mobileRenderGridFrame(
            stateSeq: 0, full: true, scrollbackLines: history, includeTheme: true, anchor: .screen
        )?.frame
    }

    private func linkWaitUntil(_ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(condition(), "Timed out waiting for the native terminal state")
    }
}

// MARK: - Recorders for the Link terminal view

@MainActor
final class RecordingFrameSinkRegistry: MobileTerminalFrameSinkRegistry {
    private(set) var sinks: [any MobileTerminalFrameSink] = []

    func addFrameSink(_ sink: any MobileTerminalFrameSink) {
        if !sinks.contains(where: { $0 === sink }) { sinks.append(sink) }
    }

    func removeFrameSink(_ sink: any MobileTerminalFrameSink) {
        sinks.removeAll { $0 === sink }
    }

    func notifyAll() {
        for sink in sinks { sink.terminalSurfaceMayHaveChanged() }
    }
}

@MainActor
final class RecordingSizing {
    enum Call: Equatable {
        case attach(cols: Int, rows: Int)
        case resize(cols: Int, rows: Int)
        case input
        case detach
    }

    private(set) var calls: [Call] = []
    var expectedGrid: (columns: Int, rows: Int)?
    private(set) var isInsideInput = false

    var sizing: ShellXLinkTerminalView.Sizing {
        ShellXLinkTerminalView.Sizing(
            attach: { [self] cols, rows in
                calls.append(.attach(cols: cols, rows: rows))
                return expectedGrid
            },
            resize: { [self] cols, rows in calls.append(.resize(cols: cols, rows: rows)) },
            input: { [self] apply in
                calls.append(.input)
                isInsideInput = true
                apply()
                isInsideInput = false
            },
            detach: { [self] in calls.append(.detach) }
        )
    }
}

@MainActor
final class TestPolicy {
    var blocked = false
    let center = NotificationCenter()

    func change(blocked: Bool) {
        self.blocked = blocked
        center.post(name: ManagedDevicePolicy.didChangeNotification, object: nil)
    }
}

extension ScrollbackTestTerminal {
    var linkTerminal: ShellXLinkTerminalView.Terminal {
        let surface = self.surface
        return ShellXLinkTerminalView.Terminal(
            surface: { surface },
            type: { _ = surface.sendInputResult($0) },
            press: { surface.sendNamedKey($0).accepted },
            paste: { _ = surface.sendTextResult($0) },
            scroll: { lines, column, row in surface.mobileScroll(deltaLines: Double(lines), col: column, row: row) }
        )
    }

    func openLinkView(
        cols: Int, rows: Int, sizing: RecordingSizing? = nil, registry: RecordingFrameSinkRegistry? = nil,
        policy: TestPolicy? = nil
    ) -> ShellXLinkTerminalView {
        let sizing = sizing ?? RecordingSizing()
        let registry = registry ?? RecordingFrameSinkRegistry()
        let policy = policy ?? TestPolicy()
        let view = ShellXLinkTerminalView(
            surfaceID: surface.id, terminal: linkTerminal, sizing: sizing.sizing, frameSinks: registry,
            isBlocked: { policy.blocked }, notificationCenter: policy.center
        )
        view.open(cols: cols, rows: rows)
        return view
    }
}

@MainActor
private final class WaitFlag {
    var timedOut = false
}

struct LinkViewTimeout: Error {}

extension ShellXLinkTerminalView {
    /// The next event, or nil when `duration` passed first (the wait is then cancelled).
    func nextEventIfAny(within duration: Duration) async -> TerminalViewEvent? {
        let flag = WaitFlag()
        let pull = Task { @MainActor in await self.nextFrame() }
        let timer = Task { @MainActor in
            try? await Task.sleep(for: duration)
            if !Task.isCancelled {
                flag.timedOut = true
                pull.cancel()
            }
        }
        let event = await pull.value
        timer.cancel()
        if flag.timedOut, case .ended(.failed) = event { return nil }
        return event
    }

    func nextEvent(within duration: Duration = .seconds(5)) async throws -> TerminalViewEvent {
        guard let event = await nextEventIfAny(within: duration) else { throw LinkViewTimeout() }
        return event
    }

    func returnsNothing(for duration: Duration) async -> Bool {
        await nextEventIfAny(within: duration) == nil
    }
}

extension TerminalScreen {
    mutating func apply(_ event: TerminalViewEvent) {
        if case let .frame(frame) = event { apply(frame) }
    }
}
