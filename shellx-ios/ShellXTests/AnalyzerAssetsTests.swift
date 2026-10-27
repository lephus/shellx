import XCTest
@testable import ShellX

/// Which analyzer module has a language is asked of iOS once per language (two `supportedLocale`
/// calls for vi-VN), not on every press: it sits on the way to the first word. Giving the analyzer
/// up for a language forgets the answer.
final class AnalyzerAssetsTests: XCTestCase {
    /// Counts the lookups and answers with a fixed module.
    private final class Lookups: @unchecked Sendable {
        private let lock = NSLock()
        private var asked: [String] = []
        var count: Int { lock.withLock { asked.count } }

        var lookup: @Sendable (Locale) async -> AnalyzerAssets.ModuleChoice {
            { [self] locale in
                lock.withLock { asked.append(locale.identifier) }
                return .dictation(locale)
            }
        }
    }

    private static let vietnamese = Locale(identifier: "vi-VN")
    private static let english = Locale(identifier: "en-US")

    func testModuleIsLookedUpOncePerLanguage() async {
        let assets = AnalyzerAssets()
        let lookups = Lookups()
        let first = await assets.module(for: Self.vietnamese, lookup: lookups.lookup)
        let again = await assets.module(for: Self.vietnamese, lookup: lookups.lookup)
        XCTAssertEqual(first, .dictation(Self.vietnamese))
        XCTAssertEqual(again, first)
        XCTAssertEqual(lookups.count, 1, "the second press reuses the answer")
        _ = await assets.module(for: Self.english, lookup: lookups.lookup)
        XCTAssertEqual(lookups.count, 2, "each language has its own")
    }

    func testGivingTheAnalyzerUpForgetsTheModule() async {
        let assets = AnalyzerAssets()
        let lookups = Lookups()
        _ = await assets.module(for: Self.vietnamese, lookup: lookups.lookup)
        await assets.markFailed(Self.vietnamese)
        _ = await assets.module(for: Self.vietnamese, lookup: lookups.lookup)
        XCTAssertEqual(lookups.count, 2)
    }
}
