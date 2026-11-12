/// The input languages a sign-in field allows: one language for each of the person's own plain keyboard layouts
/// (enabled, ASCII-capable `kTISTypeKeyboardLayout` sources). Input modes and input methods never contribute one.
///
/// The system's own "all Roman input sources" filter still offers Apple's Vietnamese Simple Telex, because Vietnamese is
/// written in a Latin script. A language filter withholds it, because Telex lists only `vi`, and AppKit offers a source
/// only when its own language list holds one of the allowed languages.
///
/// Each layout gives its primary language (the first of its list). When an enabled input mode or method also lists
/// that language, allowing it would offer that mode too, so the layout gives another language of its own list that no
/// enabled mode or method lists, `en` first if it is one of them; with none, it keeps the primary. So:
/// - ABC with Simple Telex gives `["en"]`, and a German layout gives `["de"]` (with Telex too);
/// - ABC with a Japanese input method gives `["en"]`;
/// - Apple's Vietnamese layout with Telex gives `["en"]` (the layout lists `en`): the layout is offered, Telex is not.
///
/// With no plain layout, or no answer from the system, there is no restriction (`nil`), and the ASCII rule of
/// ``EmailSignInModel`` stands alone.
struct PlainLayoutLocales: Equatable, Sendable {
    /// For `NSTextInputContext.allowedInputSourceLocales`: each language once, in the system's order; nil sets no
    /// restriction.
    let locales: [String]?

    /// - Parameter sources: The enabled, selectable keyboard input sources; nil when the system gave no list.
    init(sources: [KeyboardInputSource]?) {
        let sources = sources ?? []
        let listedByModes = Set(sources.filter { $0.kind == .inputMode || $0.kind == .inputMethod }.flatMap(\.languages))
        var found: [String] = []
        for source in sources where source.kind == .keyboardLayout && source.isASCIICapable {
            guard let language = Self.language(of: source, listedByModes: listedByModes),
                  !found.contains(language) else { continue }
            found.append(language)
        }
        locales = found.isEmpty ? nil : found
    }

    /// The layout's primary language, or, when an enabled mode or method lists it, another language of the layout's
    /// own list that none lists (`en` first). Nil for a layout without a primary language (Unicode Hex Input lists `""`).
    private static func language(of layout: KeyboardInputSource, listedByModes: Set<String>) -> String? {
        guard let primary = layout.languages.first, !primary.isEmpty else { return nil }
        guard listedByModes.contains(primary) else { return primary }
        let free = layout.languages.filter { !$0.isEmpty && !listedByModes.contains($0) }
        if free.contains("en") { return "en" }
        return free.first ?? primary
    }
}
