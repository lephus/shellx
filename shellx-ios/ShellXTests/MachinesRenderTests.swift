import ShellXAppCore
import SwiftUI
import XCTest
@testable import ShellX

/// "Your Macs" in every link state, every step of the pairing sheet, and the first-Mac screen,
/// each in light and dark (`dev.sh screenshots` writes them out in en and vi).
@MainActor
final class MachinesRenderTests: XCTestCase {
    private func assertRenders(_ view: some View, name: String) throws {
        let images = try SnapshotWriter().write(view, name: name)
        XCTAssertEqual(images.count, 2)
        for image in images { XCTAssertEqual(image.size, SnapshotWriter.size) }
        XCTAssertNotEqual(images.first?.pngData(), images.last?.pngData(), "light and dark renders should differ")
    }

    private static let everyState: [MachineListItem] = [
        MachineListItem(id: "m1", name: "MacBook Pro", state: .online),
        MachineListItem(id: "m2", name: "Mac mini", state: .connecting),
        MachineListItem(id: "m3", name: "iMac", state: .reconnecting),
        MachineListItem(id: "m4", name: "Mac Studio", state: .offline(since: Date(timeIntervalSince1970: 1_700_000_000))),
        MachineListItem(id: "m5", name: "Mac của Lan", state: .revoked),
        MachineListItem(id: "m6", name: "Mac Pro", state: .hostKeyChanged),
        MachineListItem(id: "m7", name: "MacBook Air", state: .needsUpdate),
    ]

    private func list(_ items: [MachineListItem]) -> some View {
        NavigationStack {
            MachineList(items: items, defaultID: items.first?.id, makeDefault: { _ in }, unpair: { _ in }, pair: {})
        }
    }

    // MARK: - Your Macs

    func testMachineListRendersEveryState() throws {
        try assertRenders(list(Self.everyState), name: "machines")
    }

    func testMachineListRendersAtAccessibilityTextSize() throws {
        try assertRenders(
            list(Array(Self.everyState.prefix(3)) + [Self.everyState[5]])
                .environment(\.dynamicTypeSize, .accessibility3),
            name: "machines-ax3")
    }

    func testEveryStateHasWordsAndAColor() {
        let styles = Self.everyState.map { MachineStateStyle($0.state, machineName: $0.name) }
        for style in styles { XCTAssertFalse(style.text.isEmpty) }
        XCTAssertEqual(styles[0].colorName, "StatusDone")
        XCTAssertEqual(styles[1], styles[2], "connecting and reconnecting read the same")
        XCTAssertTrue(styles[3].text.contains("Mac Studio"), "offline names the Mac")
        XCTAssertEqual(Set(styles.map(\.text)).count, 6)
    }

    func testMakeDefaultOfferedOnlyForUsableMacs() {
        let offered = Self.everyState.map { $0.offersMakeDefault(defaultID: "m2") }
        // online, the default itself, reconnecting, offline, revoked, key changed, needs update
        XCTAssertEqual(offered, [true, false, true, true, false, false, true])
    }

    func testFirstMacWithDemoRenders() throws {
        try assertRenders(NavigationStack { FirstMacView(pair: {}, tryDemo: {}) }, name: "first-mac-demo")
    }

    func testFirstMacRenders() throws {
        try assertRenders(NavigationStack { FirstMacView(pair: {}) }, name: "first-mac")
    }

    // MARK: - Pairing sheet

    func testPairingScanStepRendersForEveryCameraAccess() throws {
        for (camera, label) in [
            (CameraAccess.unavailable, "unavailable"), (.denied, "denied"), (.authorized, "scanner"),
        ] {
            try assertRenders(PairingSheetContent(step: .idle, camera: camera), name: "pairing-idle-\(label)")
        }
    }

    func testPairingConfirmRenders() throws {
        try assertRenders(
            PairingSheetContent(step: .confirm(machineName: "MacBook Pro"), camera: .unavailable),
            name: "pairing-confirm")
    }

    func testPairingWaitingRenders() throws {
        try assertRenders(
            PairingSheetContent(step: .waitingForMac(machineName: "MacBook Pro"), camera: .unavailable),
            name: "pairing-waiting")
    }

    func testPairingPairedRenders() throws {
        try assertRenders(
            PairingSheetContent(step: .paired(machineName: "MacBook Pro"), camera: .unavailable),
            name: "pairing-paired")
    }

    func testPairingFailuresRender() throws {
        let failures: [(PairingFailure, String)] = [
            (.notShellXCode, "not-shellx"), (.needsUpdate, "needs-update"), (.damagedCode, "damaged"),
            (.denied, "denied"), (.expired, "expired"), (.otherAccount, "other-account"), (.network, "network"),
            (.server(code: "internal"), "server"),
        ]
        var messages: Set<String> = []
        for (failure, label) in failures {
            messages.insert(PairingSheetContent.message(for: failure))
            try assertRenders(
                PairingSheetContent(step: .failed(failure), camera: .unavailable), name: "pairing-failed-\(label)")
        }
        XCTAssertEqual(messages.count, failures.count, "each failure says something different")
    }

    func testAnnouncementsFollowTheStep() {
        XCTAssertNil(PairingSheetContent.announcement(for: .idle))
        XCTAssertNil(PairingSheetContent.announcement(for: .confirm(machineName: "Mac")))
        XCTAssertEqual(
            PairingSheetContent.announcement(for: .failed(.denied)), PairingSheetContent.message(for: .denied))
        XCTAssertTrue(PairingSheetContent.announcement(for: .waitingForMac(machineName: "Studio"))?.contains("Studio") ?? false)
    }
}
