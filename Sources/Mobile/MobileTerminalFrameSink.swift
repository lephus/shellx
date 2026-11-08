import Foundation

/// A consumer of one terminal surface's render updates outside the iroh event lane (a ShellX Link terminal view).
/// The observer calls it on the main actor after the surface parsed output, drew, ticked or changed its theme; the
/// sink captures and diffs on its own schedule and returns at once (no capture inside the call).
@MainActor
protocol MobileTerminalFrameSink: AnyObject {
    /// The surface whose updates the sink receives; constant for the sink's lifetime.
    var frameSinkSurfaceID: UUID { get }
    /// The surface may have drawn new content.
    func terminalSurfaceMayHaveChanged()
}

/// Where frame sinks register (the app passes ``MobileTerminalRenderObserver/shared``; tests pass a recorder).
@MainActor
protocol MobileTerminalFrameSinkRegistry: AnyObject {
    func addFrameSink(_ sink: any MobileTerminalFrameSink)
    func removeFrameSink(_ sink: any MobileTerminalFrameSink)
}
