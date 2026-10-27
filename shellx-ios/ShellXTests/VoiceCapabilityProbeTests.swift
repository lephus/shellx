import ShellXAppCore
import UIKit
import XCTest
@testable import ShellX

/// The probe asks iOS what can recognise a language, and Settings › Voice says where the voice goes
/// for each answer.
@MainActor
final class VoiceCapabilityProbeTests: XCTestCase {
    func testProbeReturnsEngineForEnglish() async {
        let probe = VoiceCapabilityProbe(assets: AnalyzerAssets())
        let english = await probe.capabilities(for: .english)
        XCTAssertNotNil(english.engine, "en-US runs on the device or on Apple's servers: \(english)")

        // What this runtime offers for Vietnamese, for the ledger (locale support only, no speech).
        let vietnamese = await probe.capabilities(for: .vietnamese)
        var line = "voice probe: iOS \(UIDevice.current.systemVersion); en-US \(Self.describe(english));"
        line += " vi-VN \(Self.describe(vietnamese))"
        if #available(iOS 26, *) {
            let analyzer = await AnalyzerTranscriber.supports(VoiceLanguage.vietnamese.locale)
            line += "; SpeechTranscriber vi-VN \(analyzer.speech), DictationTranscriber vi-VN \(analyzer.dictation)"
        }
        print(line)
    }

    func testSettingsLineSaysWhereTheVoiceGoes() {
        let onDevice = VoiceSection.explanation(.onDevice, language: .vietnamese)
        XCTAssertEqual(VoiceSection.explanation(.analyzer, language: .vietnamese), onDevice)
        let server = VoiceSection.explanation(.server, language: .vietnamese)
        XCTAssertTrue(server.contains(String(localized: VoiceSection.name(.vietnamese))), server)
        XCTAssertTrue(server.contains("Apple"), server)
        let none = VoiceSection.explanation(nil, language: .english)
        XCTAssertEqual(Set([onDevice, server, none]).count, 3)
    }

    private static func describe(_ capabilities: VoiceCapabilities) -> String {
        let engine = capabilities.engine.map { "\($0)" } ?? "none"
        return "analyzer=\(capabilities.analyzerSupportsLocale) onDevice=\(capabilities.legacyOnDevice)"
            + " available=\(capabilities.legacyAvailable) -> \(engine)"
    }
}
