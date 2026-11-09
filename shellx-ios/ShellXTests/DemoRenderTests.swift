import ShellXAppCore
import SwiftUI
import XCTest
@testable import ShellX

@MainActor
final class DemoRenderTests: XCTestCase {
    private func assertRenders(_ view: some View, name: String, settle: TimeInterval = 0.05) throws {
        let images = try SnapshotWriter().write(view, name: name, settle: settle)
        XCTAssertEqual(images.count, 2)
        for image in images { XCTAssertEqual(image.size, SnapshotWriter.size) }
        XCTAssertNotEqual(images.first?.pngData(), images.last?.pngData(), "light and dark renders should differ")
    }

    func testDemoBannerRenders() throws {
        try assertRenders(VStack(spacing: 0) { DemoBanner(exit: {}); Spacer() }, name: "demo-banner")
    }

    func testDemoHomeRenders() async throws {
        let history = FileManager.default.temporaryDirectory.appendingPathComponent("demo-render-\(UUID().uuidString)", isDirectory: true)
        let session = DemoSession(make: { DemoComposition.make(approvalDelay: .zero, pasteboard: nil, runsScript: true, history: history) })
        addTeardownBlock { @MainActor in await session.exit(); try? FileManager.default.removeItem(at: history) }
        await session.start()
        let graph = try XCTUnwrap(session.graph)
        let hub = try XCTUnwrap(graph.coordinator.hub)
        let deadline = ContinuousClock.now + .seconds(10)
        while ContinuousClock.now < deadline, hub.workspaceRows(machineID: hub.machines.first?.id ?? "").count < 4 {
            try await Task.sleep(for: .milliseconds(10))
        }
        try assertRenders(DemoRootView(graph: graph, exit: {}), name: "demo-home", settle: 0.5)
    }
}
