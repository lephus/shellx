import Testing
@testable import ShellXRemoteUI

/// The languages the sign-in fields allow: the primary language of each enabled, ASCII-capable plain keyboard layout
/// (input modes and input methods never count), or no restriction when there is none.
@Suite("Plain keyboard layout locales") struct PlainLayoutLocalesTests {
    private static func source(
        _ identifier: String, _ kind: KeyboardInputSource.Kind, ascii: Bool = true, _ languages: [String]
    ) -> KeyboardInputSource {
        KeyboardInputSource(identifier: identifier, kind: kind, isASCIICapable: ascii, languages: languages)
    }

    // As this Mac lists them (ABC's language list is shortened).
    private static let abc = source("com.apple.keylayout.ABC", .keyboardLayout, ["en", "af", "de", "fr"])
    private static let simpleTelex = source("com.apple.inputmethod.VietnameseIM.VietnameseSimpleTelex", .inputMode, ["vi"])
    private static let german = source("com.apple.keylayout.German", .keyboardLayout, ["de"])
    private static let japaneseRomaji = source("com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese", .inputMode, ["ja"])
    private static let japaneseMethod = source("com.apple.inputmethod.Kotoeri.RomajiTyping", .inputMethod, ["ja"])

    @Test func abcAndSimpleTelexAllowEnglish() {
        #expect(PlainLayoutLocales(sources: [Self.abc, Self.simpleTelex]).locales == ["en"])
        #expect(PlainLayoutLocales(sources: [Self.simpleTelex, Self.abc]).locales == ["en"])
    }

    @Test func aGermanLayoutAloneAllowsGerman() {
        #expect(PlainLayoutLocales(sources: [Self.german]).locales == ["de"])
    }

    @Test func germanAndTelexAllowGerman() {
        #expect(PlainLayoutLocales(sources: [Self.german, Self.simpleTelex]).locales == ["de"])
    }

    @Test func abcAndAJapaneseInputMethodAllowEnglish() {
        #expect(PlainLayoutLocales(sources: [Self.abc, Self.japaneseMethod, Self.japaneseRomaji]).locales == ["en"])
    }

    @Test func withoutAPlainLayoutThereIsNoRestriction() {
        #expect(PlainLayoutLocales(sources: nil).locales == nil)   // the system gave no answer
        #expect(PlainLayoutLocales(sources: []).locales == nil)
        #expect(PlainLayoutLocales(sources: [Self.simpleTelex]).locales == nil)
        #expect(PlainLayoutLocales(sources: [Self.source("com.apple.keylayout.Russian", .keyboardLayout, ascii: false, ["ru"])])
            .locales == nil)
        #expect(PlainLayoutLocales(sources: [Self.source("com.example.keylayout.Bare", .keyboardLayout, [])]).locales == nil)
    }

    @Test func eachLanguageIsListedOnceInTheSystemsOrder() {
        let us = Self.source("com.apple.keylayout.US", .keyboardLayout, ["en"])
        #expect(PlainLayoutLocales(sources: [Self.abc, us]).locales == ["en"])
        #expect(PlainLayoutLocales(sources: [Self.german, Self.simpleTelex, Self.abc]).locales == ["de", "en"])
    }
}
