import Foundation
import XCTest

@testable import ShellXAppCore

/// The App Store's answer about the app (iTunes lookup) and the versions it is compared with.
final class AppStoreUpdateTests: XCTestCase {
    func testNewerComparesEachNumber() {
        XCTAssertTrue(AppVersion.isNewer("1.0.1", than: "1.0.0"))
        XCTAssertTrue(AppVersion.isNewer("1.10.0", than: "1.9.9"), "numbers, not text")
        XCTAssertTrue(AppVersion.isNewer("2.0", than: "1.9.9"), "a missing part counts as 0")
        XCTAssertFalse(AppVersion.isNewer("1.0.0", than: "1.0.0"))
        XCTAssertFalse(AppVersion.isNewer("1.0", than: "1.0.0"))
        XCTAssertFalse(AppVersion.isNewer("0.9.9", than: "1.0.0"))
    }

    func testAVersionThatIsNotNumbersIsNeverNewer() {
        XCTAssertFalse(AppVersion.isNewer("1.0.1-beta", than: "1.0.0"))
        XCTAssertFalse(AppVersion.isNewer("1.0.1", than: ""))
        XCTAssertFalse(AppVersion.isNewer("", than: "1.0.0"))
    }

    func testLookupAsksTheStoreOfTheCountry() {
        XCTAssertEqual(
            AppStoreRelease.lookupURL(bundleID: "com.shellx.prod", country: "vn").absoluteString,
            "https://itunes.apple.com/lookup?bundleId=com.shellx.prod&country=vn")
        XCTAssertEqual(
            AppStoreRelease.lookupURL(bundleID: "com.shellx.prod", country: nil).absoluteString,
            "https://itunes.apple.com/lookup?bundleId=com.shellx.prod")
    }

    func testReadsTheVersionAndPageOfTheApp() throws {
        let answer = Data(
            #"{"resultCount":1,"results":[{"version":"1.0.1","trackViewUrl":"https://apps.apple.com/vn/app/shellx/id123?uo=4","bundleId":"com.shellx.prod"}]}"#
                .utf8)

        let release = try XCTUnwrap(AppStoreRelease.parse(answer))

        XCTAssertEqual(release.version, "1.0.1")
        XCTAssertEqual(release.storeURL.absoluteString, "https://apps.apple.com/vn/app/shellx/id123?uo=4")
    }

    func testAnAppNotOnTheStoreHasNoRelease() {
        XCTAssertNil(AppStoreRelease.parse(Data(#"{"resultCount":0,"results":[]}"#.utf8)))
    }

    func testAnAnswerMissingAFieldOrNotJSONHasNoRelease() {
        XCTAssertNil(AppStoreRelease.parse(Data(#"{"resultCount":1,"results":[{"version":"1.0.1"}]}"#.utf8)))
        XCTAssertNil(
            AppStoreRelease.parse(Data(#"{"resultCount":1,"results":[{"trackViewUrl":"https://apps.apple.com/x"}]}"#.utf8)))
        XCTAssertNil(AppStoreRelease.parse(Data("<html>503</html>".utf8)))
    }
}

/// What the update popup offers: a newer App Store version until the user picks Later, and again at
/// the next check.
@MainActor
final class UpdatePromptTests: XCTestCase {
    private nonisolated static let store = URL(string: "https://apps.apple.com/vn/app/shellx/id123")!

    private nonisolated static func answer(_ version: String) -> Data {
        Data(#"{"resultCount":1,"results":[{"version":"\#(version)","trackViewUrl":"\#(store.absoluteString)"}]}"#.utf8)
    }

    func testANewerVersionIsOffered() async {
        let prompt = UpdatePrompt(installedVersion: "1.0.0", fetch: { Self.answer("1.0.1") })

        await prompt.check()

        XCTAssertEqual(prompt.offered, AppStoreRelease(version: "1.0.1", storeURL: Self.store))
    }

    func testTheInstalledOrAnOlderVersionIsNotOffered() async {
        for version in ["1.0.0", "0.9.0"] {
            let prompt = UpdatePrompt(installedVersion: "1.0.0", fetch: { Self.answer(version) })
            await prompt.check()
            XCTAssertNil(prompt.offered, version)
        }
    }

    func testLaterHidesItUntilTheNextCheck() async {
        let prompt = UpdatePrompt(installedVersion: "1.0.0", fetch: { Self.answer("1.0.1") })
        await prompt.check()

        prompt.later()
        XCTAssertNil(prompt.offered)

        await prompt.check()
        XCTAssertEqual(prompt.offered?.version, "1.0.1", "the next time the app opens it asks again")
    }

    func testAFailedLookupShowsNothing() async {
        struct Offline: Error {}
        let prompt = UpdatePrompt(installedVersion: "1.0.0", fetch: { throw Offline() })

        await prompt.check()

        XCTAssertNil(prompt.offered)
    }

    func testAStoreThatNoLongerHasTheNewerVersionTakesTheOfferBack() async {
        let answers = Answers([Self.answer("1.0.1"), Self.answer("1.0.0")])
        let prompt = UpdatePrompt(installedVersion: "1.0.0", fetch: { await answers.next() })

        await prompt.check()
        await prompt.check()

        XCTAssertNil(prompt.offered)
    }

    func testAsksTheStoreOnceWhileALookupIsUnderWay() async {
        let answers = Answers([Self.answer("1.0.1")], holding: true)
        let prompt = UpdatePrompt(installedVersion: "1.0.0", fetch: { await answers.next() })

        // Launch and coming to the front both check, at about the same time.
        async let first: Void = prompt.check()
        async let second: Void = prompt.check()
        await answers.waitForAsk()
        await answers.release()
        _ = await (first, second)

        let asked = await answers.asked
        XCTAssertEqual(asked, 1)
        XCTAssertEqual(prompt.offered?.version, "1.0.1")
    }
}

/// The App Store's answers in turn; optionally held until `release()`.
private actor Answers {
    private var queue: [Data]
    private var holding: Bool
    private var held: [CheckedContinuation<Void, Never>] = []
    private var askWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var asked = 0

    init(_ answers: [Data], holding: Bool = false) {
        queue = answers
        self.holding = holding
    }

    func next() async -> Data {
        asked += 1
        askWaiters.forEach { $0.resume() }
        askWaiters = []
        if holding { await withCheckedContinuation { held.append($0) } }
        return queue.isEmpty ? Data() : queue.removeFirst()
    }

    func waitForAsk() async {
        if asked > 0 { return }
        await withCheckedContinuation { askWaiters.append($0) }
    }

    func release() {
        holding = false
        held.forEach { $0.resume() }
        held = []
    }
}
