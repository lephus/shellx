import Foundation
import XCTest

@testable import ShellXAppCore

/// Every press asks which recognizer can run; an answer with one is reused for a while, so the
/// question stays off the way to the first word. An answer without one is never reused: the next
/// press asks again (the network may be back).
final class VoiceCapabilityCacheTests: XCTestCase {
    /// Counts the questions and answers with what the test sets.
    private final class Asker: @unchecked Sendable {
        private let lock = NSLock()
        private var answer: VoiceCapabilities
        private var asked: [VoiceLanguage] = []

        init(_ answer: VoiceCapabilities) {
            self.answer = answer
        }

        var questions: [VoiceLanguage] { lock.withLock { asked } }

        func set(_ answer: VoiceCapabilities) {
            lock.withLock { self.answer = answer }
        }

        func ask(_ language: VoiceLanguage) -> VoiceCapabilities {
            lock.withLock {
                asked.append(language)
                return answer
            }
        }
    }

    private static let server = VoiceCapabilities(analyzerSupportsLocale: false, legacyOnDevice: false, legacyAvailable: true)
    private static let analyzer = VoiceCapabilities(analyzerSupportsLocale: true, legacyOnDevice: true, legacyAvailable: true)

    func testPositiveAnswerReusedWithinTheWindow() async {
        let clock = ManualClock()
        let asker = Asker(Self.server)
        let cache = VoiceCapabilityCache(reuse: .seconds(30), clock: clock) { asker.ask($0) }

        let first = await cache.capabilities(for: .vietnamese)
        XCTAssertEqual(first, Self.server)
        clock.advance(by: .seconds(29))
        asker.set(Self.analyzer)
        let second = await cache.capabilities(for: .vietnamese)
        XCTAssertEqual(second, Self.server, "still within 30 s")
        XCTAssertEqual(asker.questions, [.vietnamese])

        // Each language has its own answer.
        _ = await cache.capabilities(for: .english)
        XCTAssertEqual(asker.questions, [.vietnamese, .english])
    }

    func testAnswerExpiresAfterTheWindow() async {
        let clock = ManualClock()
        let asker = Asker(Self.server)
        let cache = VoiceCapabilityCache(reuse: .seconds(30), clock: clock) { asker.ask($0) }
        _ = await cache.capabilities(for: .vietnamese)
        clock.advance(by: .seconds(30))
        asker.set(Self.analyzer)
        let later = await cache.capabilities(for: .vietnamese)
        XCTAssertEqual(later, Self.analyzer, "asked again once 30 s passed")
        XCTAssertEqual(asker.questions.count, 2)
    }

    func testForgetAsksAgainAtOnce() async {
        // The analyzer failed to start and a press fell back: the next answer must name that path.
        let clock = ManualClock()
        let asker = Asker(Self.analyzer)
        let cache = VoiceCapabilityCache(reuse: .seconds(30), clock: clock) { asker.ask($0) }
        _ = await cache.capabilities(for: .vietnamese)
        asker.set(Self.server)
        await cache.forget(.vietnamese)
        let now = await cache.capabilities(for: .vietnamese)
        XCTAssertEqual(now, Self.server)
        XCTAssertEqual(asker.questions.count, 2)
    }

    func testNoRecognizerIsNeverReused() async {
        let clock = ManualClock()
        let asker = Asker(.none)
        let cache = VoiceCapabilityCache(reuse: .seconds(30), clock: clock) { asker.ask($0) }
        let offline = await cache.capabilities(for: .vietnamese)
        XCTAssertNil(offline.engine)
        asker.set(Self.server)
        let back = await cache.capabilities(for: .vietnamese)
        XCTAssertEqual(back, Self.server, "the next press asks again")
        XCTAssertEqual(asker.questions.count, 2)
    }
}
