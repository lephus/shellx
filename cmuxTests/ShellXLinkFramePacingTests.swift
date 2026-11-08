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
        let first = pacing.changeArrived(now: t0 + .milliseconds(10), inputSequence: nil)
        let second = pacing.changeArrived(now: t0 + .milliseconds(20), inputSequence: nil)
        let ended = pacing.holdEnded(now: t0 + floor)
        #expect(first == .hold(until: t0 + floor))
        #expect(second == .hold(until: t0 + floor))
        #expect(ended)
    }

    @Test func aChangeAfterTheFloorIsCapturedAtOnce() {
        var pacing = ShellXLinkFramePacing()
        pacing.noteSnapshot(now: t0, inputSequence: nil)
        let step = pacing.changeArrived(now: t0 + .milliseconds(100), inputSequence: nil)
        #expect(step == .capture)
    }

    @Test func theEchoOfAnInputIsNeverHeld() {
        var pacing = ShellXLinkFramePacing()
        pacing.noteSnapshot(now: t0, inputSequence: nil)
        let echo = pacing.changeArrived(now: t0 + .milliseconds(10), inputSequence: 1)
        let next = pacing.changeArrived(now: t0 + .milliseconds(20), inputSequence: 1)
        #expect(echo == .capture)
        #expect(next == .hold(until: t0 + .milliseconds(10) + floor))
    }

    @Test func aHoldWithNothingHeldCapturesNothing() {
        var pacing = ShellXLinkFramePacing()
        let step = pacing.changeArrived(now: t0 + .milliseconds(100), inputSequence: nil)
        let ended = pacing.holdEnded(now: t0 + .milliseconds(200))
        #expect(step == .capture)
        #expect(!ended)
    }
}
