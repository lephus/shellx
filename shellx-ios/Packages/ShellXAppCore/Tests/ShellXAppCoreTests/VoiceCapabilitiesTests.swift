import Foundation
import XCTest

@testable import ShellXAppCore

/// Which recognizer the mic uses (plan D8): SpeechAnalyzer first, then SFSpeechRecognizer on the
/// device, then SFSpeechRecognizer on Apple's servers. The mic is off only when none can run; it is
/// never off just because the language cannot run on the device. And the spoken language.
final class VoiceCapabilitiesTests: XCTestCase {
    private func engine(analyzer: Bool, onDevice: Bool, available: Bool) -> VoiceEngine? {
        VoiceCapabilities(analyzerSupportsLocale: analyzer, legacyOnDevice: onDevice, legacyAvailable: available).engine
    }

    func testAnalyzerPreferredWhenItSupportsLocale() {
        XCTAssertEqual(engine(analyzer: true, onDevice: true, available: true), .analyzer)
        XCTAssertEqual(engine(analyzer: true, onDevice: false, available: true), .analyzer)
        XCTAssertEqual(engine(analyzer: true, onDevice: false, available: false), .analyzer)
    }

    func testOnDeviceBeforeServer() {
        XCTAssertEqual(engine(analyzer: false, onDevice: true, available: true), .onDevice)
        XCTAssertEqual(engine(analyzer: false, onDevice: true, available: false), .onDevice)
    }

    func testServerWhenNoOnDevice() {
        XCTAssertEqual(engine(analyzer: false, onDevice: false, available: true), .server)
    }

    func testNilOnlyWhenNothingAvailable() {
        for analyzer in [false, true] {
            for onDevice in [false, true] {
                for available in [false, true] {
                    let result = engine(analyzer: analyzer, onDevice: onDevice, available: available)
                    if analyzer || onDevice || available {
                        XCTAssertNotNil(result, "\(analyzer) \(onDevice) \(available): some path still runs")
                    } else {
                        XCTAssertNil(result)
                    }
                }
            }
        }
        XCTAssertNil(VoiceCapabilities.none.engine)
    }

    func testDefaultLanguageVietnameseWhenPreferred() {
        XCTAssertEqual(VoiceLanguage(preferredLanguages: ["en-US", "vi-VN"]), .vietnamese)
        XCTAssertEqual(VoiceLanguage(preferredLanguages: ["vi"]), .vietnamese)
        XCTAssertEqual(VoiceLanguage(preferredLanguages: ["fr-FR", "vi_VN"]), .vietnamese)
        XCTAssertEqual(VoiceLanguage(preferredLanguages: ["en-GB", "fr"]), .english)
        XCTAssertEqual(VoiceLanguage(preferredLanguages: []), .english)
        XCTAssertEqual(VoiceLanguage.vietnamese.locale.identifier, "vi-VN")
        XCTAssertEqual(VoiceLanguage.english.locale.identifier, "en-US")
    }

    func testSavedChoiceWinsOverPreferredLanguages() throws {
        let suite = "VoiceCapabilitiesTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(VoiceLanguage.saved(in: defaults, preferredLanguages: ["vi-VN"]), .vietnamese)
        VoiceLanguage.english.save(in: defaults)
        XCTAssertEqual(VoiceLanguage.saved(in: defaults, preferredLanguages: ["vi-VN"]), .english)
        // An unknown stored value falls back to the preferred languages.
        defaults.set("xx-YY", forKey: VoiceLanguage.defaultsKey)
        XCTAssertEqual(VoiceLanguage.saved(in: defaults, preferredLanguages: ["vi-VN"]), .vietnamese)
    }
}
