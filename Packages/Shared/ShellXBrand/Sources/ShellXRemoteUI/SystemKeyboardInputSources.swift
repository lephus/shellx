import Carbon

/// Reads the enabled, selectable keyboard input sources through the Text Input Sources API (HIToolbox; every call
/// used here exists since macOS 10.5). It only reads: nothing is selected, enabled or changed.
struct SystemKeyboardInputSources {
    /// The enabled, selectable keyboard input sources, in the system's order.
    ///
    /// - Returns: The sources, or nil when the system gives no list. A source without an id or a type is left out.
    @MainActor
    func enabled() -> [KeyboardInputSource]? {
        let filter = [
            kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String,
            kTISPropertyInputSourceIsSelectCapable as String: true
        ] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource] else {
            return nil
        }
        return list.compactMap(Self.record)
    }

    private static func record(_ source: TISInputSource) -> KeyboardInputSource? {
        guard let identifier = string(source, kTISPropertyInputSourceID),
              let type = string(source, kTISPropertyInputSourceType) else { return nil }
        let isASCIICapable = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsASCIICapable)
            .map { CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque($0).takeUnretainedValue()) } ?? false
        let languages = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages)
            .flatMap { Unmanaged<CFArray>.fromOpaque($0).takeUnretainedValue() as? [String] } ?? []
        return KeyboardInputSource(identifier: identifier, kind: kind(type), isASCIICapable: isASCIICapable,
                                   languages: languages)
    }

    private static func kind(_ type: String) -> KeyboardInputSource.Kind {
        if type == kTISTypeKeyboardLayout as String { return .keyboardLayout }
        if type == kTISTypeKeyboardInputMode as String { return .inputMode }
        let methods = [kTISTypeKeyboardInputMethodWithoutModes as String, kTISTypeKeyboardInputMethodModeEnabled as String]
        return methods.contains(type) ? .inputMethod : .other
    }

    private static func string(_ source: TISInputSource, _ key: CFString) -> String? {
        TISGetInputSourceProperty(source, key).map { Unmanaged<CFString>.fromOpaque($0).takeUnretainedValue() as String }
    }
}
