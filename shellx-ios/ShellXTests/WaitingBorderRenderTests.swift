import ShellXAppCore
import SwiftUI
import UIKit
import XCTest
@testable import ShellX

/// The multicolor border around an agent that waits for the user's answer (spec 6.7): when it shows
/// (needs-you cards, chips of an agent that asks), how it moves, and that a frame of it is really drawn
/// on a needs-you card and not on a running one. The frames are taken while the gradient turns (the
/// system's Reduce Motion setting cannot be set from a test), so they only check what holds at every
/// angle: the edge is coloured, in several colours.
@MainActor
final class WaitingBorderRenderTests: XCTestCase {
    private static let now = Date(timeIntervalSince1970: 1_700_000_000)
    private static let nowMs: Int64 = 1_700_000_000_000

    // MARK: - Fixtures

    private static func session(_ id: String, state: AgentState, online: Bool = true) -> MachineSession {
        MachineSession(
            machineID: "m1", machineName: "MacBook Pro", online: online,
            session: AgentSession(
                sessionId: id, agent: "claude", workspaceId: "ws", workspaceTitle: "shellx-ios", state: state,
                stateSinceMs: nowMs - 240_000, lastActivityMs: nowMs - 5_000))
    }

    private static func item(_ state: AgentState, online: Bool = true) -> FocusItem {
        FocusItem(session: session("s", state: state, online: online), name: "shellx-ios", question: nil)
    }

    private static func pane(_ state: AgentState?, online: Bool = true) -> WorkspacePane {
        WorkspacePane(id: "t", title: "claude", session: state.map { session("s", state: $0, online: online) })
    }

    private static let allKinds: [FocusRowView.Kind] = [.needsYou, .running, .justDone, .ended, .idle]

    // MARK: - When it shows

    func testOnlyAnAgentThatWaitsForTheUserHasTheBorder() {
        XCTAssertTrue(WaitingBorder.isActive(for: .needsInput))
        for state in [AgentState.working, .idle, .ended, .other("thinking")] {
            XCTAssertFalse(WaitingBorder.isActive(for: state), "\(state) does not wait for the user")
        }
        XCTAssertFalse(
            WaitingBorder.isActive(for: .needsInput, online: false),
            "a Mac that is not online cannot be answered: its card is grey, the chip says Offline")
    }

    func testOnlyANeedsYouCardHasTheBorder() {
        for kind in Self.allKinds {
            XCTAssertEqual(
                FocusRowView.showsWaitingBorder(item: Self.item(.needsInput), kind: kind), kind == .needsYou,
                "\(kind)")
        }
        // The group decides: a session with a request waiting is in "needs you" whatever state it reports.
        XCTAssertTrue(FocusRowView.showsWaitingBorder(item: Self.item(.working), kind: .needsYou))
        XCTAssertFalse(
            FocusRowView.showsWaitingBorder(item: Self.item(.needsInput, online: false), kind: .needsYou),
            "a card of a Mac that is not online fades and has no border")
    }

    func testOnlyTheChipOfAnAgentThatAsksHasTheBorder() {
        XCTAssertTrue(PaneChips.showsWaitingBorder(Self.pane(.needsInput)))
        for state in [AgentState.working, .idle, .ended, .other("thinking")] {
            XCTAssertFalse(PaneChips.showsWaitingBorder(Self.pane(state)), "\(state)")
        }
        XCTAssertFalse(PaneChips.showsWaitingBorder(Self.pane(nil)), "a shell asks nothing")
        XCTAssertFalse(PaneChips.showsWaitingBorder(Self.pane(.needsInput, online: false)))
    }

    // MARK: - How it looks and moves

    func testTheColoursAndStrokeAreTheSpecifiedOnes() {
        XCTAssertEqual(WaitingBorder.palette, [0x60A5FA, 0xA78BFA, 0xF472B6, 0xFBBF24, 0x60A5FA])
        XCTAssertEqual(WaitingBorder.palette.first, WaitingBorder.palette.last, "the turn closes without a seam")
        XCTAssertEqual(WaitingBorder.lineWidth, 2)
    }

    func testTheGradientTurnsOnceEveryThreeSecondsAtAConstantSpeed() {
        XCTAssertEqual(WaitingBorder.turn, 3)
        func angle(_ seconds: TimeInterval) -> Double {
            WaitingBorder.angle(at: Date(timeIntervalSinceReferenceDate: seconds))
        }
        XCTAssertEqual(angle(0), 0, accuracy: 0.001)
        XCTAssertEqual(angle(0.75), 90, accuracy: 0.001)
        XCTAssertEqual(angle(1.5), 180, accuracy: 0.001)
        XCTAssertEqual(angle(2.25), 270, accuracy: 0.001)
        XCTAssertEqual(angle(3), 0, accuracy: 0.001, "one turn, then again")
        XCTAssertEqual(angle(4.5), 180, accuracy: 0.001)
        XCTAssertEqual(angle(300.75), 90, accuracy: 0.001)
    }

    func testReduceMotionKeepsTheBorderStill() {
        XCTAssertTrue(WaitingBorder.animates(reduceMotion: false))
        XCTAssertFalse(WaitingBorder.animates(reduceMotion: true))
    }

    // MARK: - Frames

    /// The view `FocusRowView` is drawn in: a card at the top, 16 points in from the edges.
    private func cardScene(_ kind: FocusRowView.Kind, state: AgentState) -> some View {
        VStack(spacing: 0) {
            FocusRowView(item: Self.item(state), kind: kind, now: Self.now, showsMachineName: false)
                .padding(16)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.appBackground)
    }

    private func chipScene(_ state: AgentState) -> some View {
        VStack(spacing: 0) {
            PaneChips(panes: [Self.pane(state)], selected: nil, now: Self.now, select: { _ in })
                .padding(.top, 16)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.appBackground)
    }

    func testANeedsYouCardDrawsTheBorderAndARunningCardDoesNot() throws {
        let waiting = try SnapshotWriter().write(cardScene(.needsYou, state: .needsInput), name: "waiting-border-card")
        let running = try SnapshotWriter().write(cardScene(.running, state: .working), name: "waiting-border-card-running")
        for (waitingImage, runningImage) in zip(waiting, running) {
            let top = try XCTUnwrap(Pixels(waitingImage)).topEdge()
            XCTAssertGreaterThanOrEqual(
                top.filter { $0.chroma > 80 }.count * 10, top.count * 5,
                "most of the needs-you card's top edge is coloured, whatever the angle the gradient is at")
            XCTAssertGreaterThan(top.maxDistance, 100, "and it is several colours, not one")

            let quiet = try XCTUnwrap(Pixels(runningImage)).topEdge()
            XCTAssertEqual(quiet.filter { $0.chroma > 40 }.count, 0, "a running card keeps its grey outline")
        }
    }

    func testTheBorderOfAChipIsDrawnOnlyWhileItsAgentAsks() throws {
        let asking = try SnapshotWriter().write(chipScene(.needsInput), name: "waiting-border-chip")
        let done = try SnapshotWriter().write(chipScene(.idle), name: "waiting-border-chip-done")
        for (askingImage, doneImage) in zip(asking, done) {
            let withBorder = try XCTUnwrap(Pixels(askingImage)).count { $0.chroma > 80 }
            let without = try XCTUnwrap(Pixels(doneImage)).count { $0.chroma > 80 }
            let scale = Int(askingImage.scale)
            // The ring is 2 points wide around a chip some 100 x 34 points big: far more than the dot.
            XCTAssertGreaterThan(withBorder - without, 100 * scale * scale, "ring pixels: \(withBorder) vs \(without)")
        }
    }

    func testWithoutTheBorderTheModifierAddsNothing() throws {
        func sample(_ active: Bool) -> some View {
            Text(verbatim: "Needs you")
                .padding(24)
                .background(Color.appSurface)
                .waitingBorder(isActive: active, cornerRadius: 10)
                .padding(40)
                .background(Color.appBackground)
        }
        let off = try SnapshotWriter().write(sample(false), name: "waiting-border-modifier-off")
        let plain = try SnapshotWriter().write(
            Text(verbatim: "Needs you").padding(24).background(Color.appSurface).padding(40)
                .background(Color.appBackground),
            name: "waiting-border-modifier-plain")
        let on = try SnapshotWriter().write(sample(true), name: "waiting-border-modifier-on")
        XCTAssertEqual(off.map { $0.pngData() }, plain.map { $0.pngData() }, "inactive: no overlay at all")
        XCTAssertNotEqual(on.map { $0.pngData() }, plain.map { $0.pngData() }, "active: the ring is drawn")
    }
}

// MARK: - Pixels

/// The pixels of a rendered image, to look at the colour of a few of them (test-only).
private struct Pixels {
    struct Colour {
        let r: Int, g: Int, b: Int
        /// How far the colour is from grey: 0 for grey, 255 for a pure hue.
        var chroma: Int { max(r, g, b) - min(r, g, b) }
        func distance(to other: Colour) -> Int { abs(r - other.r) + abs(g - other.g) + abs(b - other.b) }
    }

    let width: Int
    let height: Int
    let scale: Int
    private let data: [UInt8]

    init?(_ image: UIImage) {
        guard let cgImage = image.cgImage, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let (w, h) = (cgImage.width, cgImage.height)
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard
                let context = CGContext(
                    data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
                    bytesPerRow: w * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }
        width = w
        height = h
        scale = Int(image.scale)
        data = bytes
    }

    func at(x: Int, y: Int) -> Colour {
        let i = (y * width + x) * 4
        return Colour(r: Int(data[i]), g: Int(data[i + 1]), b: Int(data[i + 2]))
    }

    /// How many pixels satisfy `test`.
    func count(where test: (Colour) -> Bool) -> Int {
        var total = 0
        for y in 0..<height {
            for x in 0..<width where test(at(x: x, y: y)) { total += 1 }
        }
        return total
    }

    /// The middle of the top outline of the first card under the top of the image: the first row, going
    /// down the middle column, that differs from the background is the card's edge, and the outline is
    /// 1 to 2 points thick, so one point further down is inside it. Sampled every 5 points along the
    /// straight part of the edge (past the 14-point corners).
    func topEdge() -> EdgeSamples {
        let background = at(x: 0, y: 0)
        var edge = 0
        while edge < height, at(x: width / 2, y: edge).distance(to: background) < 6 { edge += 1 }
        let y = min(height - 1, edge + scale)
        let samples = stride(from: 40, through: (width / scale) - 40, by: 5).map { at(x: $0 * scale, y: y) }
        return EdgeSamples(colours: samples)
    }
}

private struct EdgeSamples {
    let colours: [Pixels.Colour]
    var count: Int { colours.count }
    func filter(_ test: (Pixels.Colour) -> Bool) -> [Pixels.Colour] { colours.filter(test) }
    /// The largest difference between two of the samples.
    var maxDistance: Int {
        colours.flatMap { a in colours.map { a.distance(to: $0) } }.max() ?? 0
    }
}
