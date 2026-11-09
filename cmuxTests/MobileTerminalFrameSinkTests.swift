import CmuxMobileRPC
import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@MainActor
private final class RecordingFrameSink: MobileTerminalFrameSink {
    let frameSinkSurfaceID: UUID
    private(set) var changes = 0
    init(surfaceID: UUID) { frameSinkSurfaceID = surfaceID }
    func terminalSurfaceMayHaveChanged() { changes += 1 }
}

@MainActor
@Suite("Mobile terminal frame sinks", .serialized, .timeLimit(.minutes(1)))
struct MobileTerminalFrameSinkTests {
    private var observer: MobileTerminalRenderObserver { MobileTerminalRenderObserver.shared }

    private func eventually(_ condition: @MainActor () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(2)
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    private func isolated(_ body: @MainActor () async throws -> Void) async throws {
        try await AppContextSerialGate.withExclusiveAppContext {
            MobileHostService.debugResetEventSubscriptionsForTesting()
            observer.stop()
            observer.start()
            defer {
                observer.stop()
                observer.start()
            }
            try await body()
        }
    }

    @Test func aSinkHoldsGhosttyNotificationsWithoutAnIrohSubscriber() async throws {
        try await isolated {
            #expect(!observer.debugIsRetainingNotificationDemandForTesting)
            let sink = RecordingFrameSink(surfaceID: UUID())
            observer.addFrameSink(sink)
            #expect(observer.debugIsRetainingNotificationDemandForTesting && observer.debugFrameSinkCountForTesting == 1)
            #expect(MobileTerminalByteTee.shared.hasOutputDemand)
            observer.removeFrameSink(sink)
            #expect(!observer.debugIsRetainingNotificationDemandForTesting && observer.debugFrameSinkCountForTesting == 0)
            #expect(!MobileTerminalByteTee.shared.hasOutputDemand)
        }
    }

    @Test func outputNotifiesOnlyTheSinksOfItsSurface() async throws {
        try await isolated {
            let a = RecordingFrameSink(surfaceID: UUID()), b = RecordingFrameSink(surfaceID: UUID())
            observer.addFrameSink(a)
            observer.addFrameSink(b)
            observer.debugFlushTerminalUpdatesForTesting()
            let before = (a.changes, b.changes)
            observer.noteTerminalBytes(surfaceID: a.frameSinkSurfaceID)
            #expect(observer.debugPendingSurfaceCountForTesting == 1)
            observer.debugFlushTerminalUpdatesForTesting()
            #expect(a.changes == before.0 + 1 && b.changes == before.1)
        }
    }

    @Test func aGlobalTickNotifiesEverySink() async throws {
        try await isolated {
            let a = RecordingFrameSink(surfaceID: UUID()), b = RecordingFrameSink(surfaceID: UUID())
            observer.addFrameSink(a)
            observer.addFrameSink(b)
            observer.debugFlushTerminalUpdatesForTesting()
            let before = (a.changes, b.changes)
            observer.debugEnqueueTerminalUpdateForTesting(surfaceID: nil)
            observer.debugFlushTerminalUpdatesForTesting()
            #expect(a.changes == before.0 + 1 && b.changes == before.1 + 1)
        }
    }

    @Test func aReleasedSinkStopsTheDemand() async throws {
        try await isolated {
            do {
                let sink = RecordingFrameSink(surfaceID: UUID())
                observer.addFrameSink(sink)
                #expect(observer.debugFrameSinkCountForTesting == 1)
            }
            observer.debugEnqueueTerminalUpdateForTesting(surfaceID: nil)
            observer.debugFlushTerminalUpdatesForTesting()
            #expect(observer.debugFrameSinkCountForTesting == 0)
            #expect(!observer.debugIsRetainingNotificationDemandForTesting)
            #expect(!MobileTerminalByteTee.shared.hasOutputDemand)
        }
    }

    @Test func withoutSinksOrSubscribersOutputIsIgnored() async throws {
        try await isolated {
            observer.noteTerminalBytes(surfaceID: UUID())
            #expect(observer.debugPendingSurfaceCountForTesting == 0 && !MobileTerminalByteTee.shared.hasOutputDemand)
        }
    }

    @Test func sinksAloneLeaveNoIrohState() async throws {
        try await isolated {
            let sink = RecordingFrameSink(surfaceID: UUID())
            observer.addFrameSink(sink)
            observer.noteTerminalBytes(surfaceID: sink.frameSinkSurfaceID)
            observer.debugFlushTerminalUpdatesForTesting()
            #expect(observer.debugRenderGridStateSurfaceCountForTesting == 0)
            observer.removeFrameSink(sink)
        }
    }

    @Test func anIrohSubscriberKeepsItsDemandWhenTheLastSinkLeaves() async throws {
        try await isolated {
            let session = MobileHostConnection(id: UUID(), transport: RecordingMobileHostByteTransport(),
                authorizeRequest: { _ in nil }, onAuthorizedRequest: { _ in },
                handleRequest: { _ in .ok([:]) }, onClose: { _ in })
            await session.subscribe(streamID: "events", topics: ["terminal.render_grid"])
            #expect(await eventually { observer.debugIsRetainingNotificationDemandForTesting })
            observer.debugFlushTerminalUpdatesForTesting()
            observer.noteTerminalBytes(surfaceID: UUID())
            #expect(observer.debugPendingSurfaceCountForTesting == 1)
            let sink = RecordingFrameSink(surfaceID: UUID())
            observer.addFrameSink(sink)
            observer.removeFrameSink(sink)
            #expect(observer.debugIsRetainingNotificationDemandForTesting && MobileTerminalByteTee.shared.hasOutputDemand)
            _ = await session.unsubscribe(streamID: "events")
            #expect(await eventually { !observer.debugIsRetainingNotificationDemandForTesting })
            await session.close(reason: "test complete")
        }
    }
}
