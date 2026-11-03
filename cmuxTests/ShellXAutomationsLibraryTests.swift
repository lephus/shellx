import Foundation
import ShellXAutomations
import XCTest

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@MainActor
final class ShellXAutomationsLibraryTests: XCTestCase {
    /// Waits for a change another task makes; tests only.
    private func waitUntil(timeout: Duration = .seconds(5), _ condition: () -> Bool) async {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while !condition(), clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    func testReloadsWhenStampChanges() async throws {
        let fixture = ShellXAutomationsFixture()
        defer { fixture.remove() }
        let library = fixture.library
        library.startWatching()
        defer { library.stopWatching() }
        await library.reload()
        XCTAssertEqual(library.count, 0)

        // Another process (here: the store directly) saves and replaces the change stamp.
        _ = try await fixture.store.save(fixture.cronDraft(), replacing: nil)

        await waitUntil { library.count == 1 }
        XCTAssertEqual(library.count, 1)
        XCTAssertEqual(library.automations.first?.name, "nightly")
    }

    func testFirstLoadSyncsSchedulesOnce() async throws {
        let fixture = ShellXAutomationsFixture()
        defer { fixture.remove() }
        _ = try await fixture.store.save(fixture.cronDraft(), replacing: nil)

        await fixture.library.reload()
        await fixture.library.reload()

        let bootstraps = fixture.log.all.filter { $0.hasPrefix("launchctl bootstrap") }
        XCTAssertEqual(bootstraps.count, 1)
    }

    func testUnreadCountCountsUnseenRuns() async throws {
        let fixture = ShellXAutomationsFixture()
        defer { fixture.remove() }
        let saved = try await fixture.store.save(fixture.cronDraft(), replacing: nil)
        let run = try XCTUnwrap(try await fixture.store.beginRun(id: saved.id, trigger: .manual, pid: 1))
        let record = ShellXRunRecord(status: .done, trigger: .manual, startedAt: Date(), finishedAt: Date(), summary: "ok")
        try await fixture.store.finishRun(id: saved.id, runDirectory: run, record: record, pid: 1)

        await fixture.library.reload()
        XCTAssertEqual(fixture.library.unreadCount, 1)

        try await fixture.store.markRead(id: saved.id)
        await fixture.library.reload()
        XCTAssertEqual(fixture.library.unreadCount, 0)
    }
}
