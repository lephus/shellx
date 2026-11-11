/// The input languages a sign-in field allows: the primary language of each of the person's own plain keyboard layouts
/// (enabled, ASCII-capable `kTISTypeKeyboardLayout` sources). Input modes and input methods never count.
///
/// The system's own "all Roman input sources" filter still offers Apple's Vietnamese Simple Telex, because Vietnamese is
/// written in a Latin script. A language filter withholds it, because Telex lists only `vi`. So ABC with Simple Telex gives `["en"]`,
/// a German layout gives `["de"]` (with Telex too), and ABC with a Japanese input method gives `["en"]`. With no plain
/// layout, or no answer from the system, there is no restriction (`nil`), and the ASCII rule of ``EmailSignInModel``
/// stands alone.
struct PlainLayoutLocales: Equatable, Sendable {
    /// For `NSTextInputContext.allowedInputSourceLocales`: each language once, in the system's order; nil sets no
    /// restriction.
    let locales: [String]?

    /// - Parameter sources: The enabled, selectable keyboard input sources; nil when the system gave no list.
    init(sources: [KeyboardInputSource]?) {
        var found: [String] = []
        for source in sources ?? [] where source.kind == .keyboardLayout && source.isASCIICapable {
            guard let primary = source.languages.first, !primary.isEmpty, !found.contains(primary) else { continue }
            found.append(primary)
        }
        locales = found.isEmpty ? nil : found
    }
}
