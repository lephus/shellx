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

    /// Unicode Hex Input lists `""` first (`["", "af", …]` on this Mac): it has no primary language and adds none.
    @Test func aLayoutWhoseFirstLanguageIsEmptyAddsNone() {
        let hexInput = Self.source("com.apple.keylayout.UnicodeHexInput", .keyboardLayout, ["", "af", "en"])
        #expect(PlainLayoutLocales(sources: [hexInput]).locales == nil)
        #expect(PlainLayoutLocales(sources: [hexInput, Self.abc]).locales == ["en"])
    }

    /// Apple's Vietnamese layout lists `vi` first and `en` later; Telex lists only `vi`. Allowing `vi` would offer
    /// Telex, so the layout's own `en` is allowed instead, and the layout is still offered.
    @Test func aLayoutWhosePrimaryLanguageAnInputModeListsGivesAnotherOfItsLanguages() {
        let vietnameseLayout = Self.source("com.apple.keylayout.Vietnamese", .keyboardLayout, ["vi", "af", "asa", "en", "de"])
        #expect(PlainLayoutLocales(sources: [vietnameseLayout, Self.simpleTelex]).locales == ["en"])
        #expect(PlainLayoutLocales(sources: [Self.simpleTelex, vietnameseLayout, Self.abc]).locales == ["en"])
        // An input method counts like an input mode.
        let vietnameseMethod = Self.source("com.example.inputmethod.Vietnamese", .inputMethod, ["vi"])
        #expect(PlainLayoutLocales(sources: [vietnameseLayout, vietnameseMethod]).locales == ["en"])
        // Without `en`, the layout's first language no mode or method lists.
        let noEnglish = Self.source("com.example.keylayout.NoEnglish", .keyboardLayout, ["vi", "af", "de"])
        #expect(PlainLayoutLocales(sources: [noEnglish, Self.simpleTelex]).locales == ["af"])
        let englishTaken = Self.source("com.example.inputmode.English", .inputMode, ["en", "af"])
        #expect(PlainLayoutLocales(sources: [vietnameseLayout, Self.simpleTelex, englishTaken]).locales == ["asa"])
        // A layout with nothing else to offer keeps its primary language.
        let onlyVietnamese = Self.source("com.example.keylayout.OnlyVietnamese", .keyboardLayout, ["vi"])
        #expect(PlainLayoutLocales(sources: [onlyVietnamese, Self.simpleTelex]).locales == ["vi"])
        // Without such a mode or method the primary language stands.
        #expect(PlainLayoutLocales(sources: [vietnameseLayout]).locales == ["vi"])
    }

    @Test func eachLanguageIsListedOnceInTheSystemsOrder() {
        let us = Self.source("com.apple.keylayout.US", .keyboardLayout, ["en"])
        #expect(PlainLayoutLocales(sources: [Self.abc, us]).locales == ["en"])
        #expect(PlainLayoutLocales(sources: [Self.german, Self.simpleTelex, Self.abc]).locales == ["de", "en"])
    }
}
