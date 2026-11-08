import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@Suite("ShellX Link frame pacing")
struct ShellXLinkFramePacingTests {
    let t0 = ContinuousClock.now
    let floor = MobileTerminalFramePacer.floorPeriod

    @Test func aChangeRightAfterASnapshotWaitsForTheFloor() {
        var pacing = ShellXLinkFramePacing()
        pacing.noteSnapshot(now: t0, inputSequence: nil)
        #expect(pacing.changeArrived(now: t0 + .milliseconds(10), inputSequence: nil) == .hold(until: t0 + floor))
        #expect(pacing.changeArrived(now: t0 + .milliseconds(20), inputSequence: nil) == .hold(until: t0 + floor))
        #expect(pacing.holdEnded(now: t0 + floor))
    }

    @Test func aChangeAfterTheFloorIsCapturedAtOnce() {
        var pacing = ShellXLinkFramePacing()
        pacing.noteSnapshot(now: t0, inputSequence: nil)
        #expect(pacing.changeArrived(now: t0 + .milliseconds(100), inputSequence: nil) == .capture)
    }

    @Test func theEchoOfAnInputIsNeverHeld() {
        var pacing = ShellXLinkFramePacing()
        pacing.noteSnapshot(now: t0, inputSequence: nil)
        #expect(pacing.changeArrived(now: t0 + .milliseconds(10), inputSequence: 1) == .capture)
        #expect(pacing.changeArrived(now: t0 + .milliseconds(20), inputSequence: 1)
            == .hold(until: t0 + .milliseconds(10) + floor))
    }

    @Test func aHoldWithNothingHeldCapturesNothing() {
        var pacing = ShellXLinkFramePacing()
        #expect(pacing.changeArrived(now: t0 + .milliseconds(100), inputSequence: nil) == .capture)
        #expect(!pacing.holdEnded(now: t0 + .milliseconds(200)))
    }
}
