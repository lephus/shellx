/// One enabled, selectable keyboard input source, as the Text Input Sources API describes it (plain values, so the
/// choice of allowed languages in ``PlainLayoutLocales`` is testable without the system's list).
struct KeyboardInputSource: Equatable, Sendable {
    /// What kind of input source it is (`kTISPropertyInputSourceType`).
    enum Kind: Equatable, Sendable {
        /// A plain keyboard layout (`kTISTypeKeyboardLayout`), such as ABC or German.
        case keyboardLayout
        /// A mode of an input method (`kTISTypeKeyboardInputMode`), such as Vietnamese Simple Telex or Japanese Romaji.
        case inputMode
        /// An input method (`kTISTypeKeyboardInputMethodWithoutModes` or `kTISTypeKeyboardInputMethodModeEnabled`).
        case inputMethod
        /// Any other type.
        case other
    }

    /// `kTISPropertyInputSourceID`, for example `com.apple.keylayout.ABC`.
    let identifier: String
    let kind: Kind
    /// `kTISPropertyInputSourceIsASCIICapable`.
    let isASCIICapable: Bool
    /// `kTISPropertyInputSourceLanguages`: the languages it types, its primary language first.
    let languages: [String]
}
