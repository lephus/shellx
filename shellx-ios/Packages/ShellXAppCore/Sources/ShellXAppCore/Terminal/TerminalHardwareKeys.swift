import Foundation
import ShellXLinkCore

/// The modifier flags of a hardware key press (`UIKeyModifierFlags`, without the app depending on UIKit here).
public struct TerminalHardwareModifiers: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let shift = TerminalHardwareModifiers(rawValue: 1)
    public static let control = TerminalHardwareModifiers(rawValue: 2)
    public static let alternate = TerminalHardwareModifiers(rawValue: 4)
    public static let command = TerminalHardwareModifiers(rawValue: 8)
}

public enum TerminalHardwareAction: Equatable, Sendable {
    case send(TerminalKey, mods: [TerminalModifier])
    /// Leave it to UIKit: text input, the input method, the system's ⌘ shortcuts.
    case system
}

/// Hardware keyboard presses → named keys (S2 §3.7). Plain letters, Return and Backspace go through the text system so
/// input methods keep working; ⌘ combinations go to the system (no app shortcuts).
public enum TerminalHardwareKeys {
    /// USB HID keyboard usages (`UIKeyboardHIDUsage` uses the same values) of the keys sent by name.
    private static let named: [Int: TerminalKey] = [
        0x29: .escape, 0x2B: .tab, 0x4F: .right, 0x50: .left, 0x51: .down, 0x52: .up,
        0x4A: .home, 0x4B: .pageUp, 0x4C: .delete, 0x4D: .end, 0x4E: .pageDown,
    ]

    /// `usage` is the USB HID keyboard usage (`UIKey.keyCode.rawValue`); `composing` is true while marked text exists.
    public static func action(usage: Int, modifiers: TerminalHardwareModifiers, composing: Bool) -> TerminalHardwareAction {
        if composing || modifiers.contains(.command) { return .system }
        var mods: [TerminalModifier] = []
        if modifiers.contains(.control) { mods.append(.ctrl) }
        if modifiers.contains(.alternate) { mods.append(.alt) }
        if modifiers.contains(.shift) { mods.append(.shift) }
        if let key = named[usage] { return .send(key, mods: mods) }
        let control = modifiers.contains(.control)
        let alternate = modifiers.contains(.alternate)
        switch usage {
        case 0x04...0x1D where control:                                       // a-z
            return .send(.letter(Character(Unicode.Scalar(UInt8(0x61 + usage - 0x04)))), mods: mods)
        case 0x28 where control || alternate: return .send(.enter, mods: mods)        // Return
        case 0x2A where control || alternate: return .send(.backspace, mods: mods)    // Delete (backspace)
        case 0x2C where control: return .send(.space, mods: mods)
        default: return .system   // letters, Return, Backspace, Space, alt+letter, F-keys: the text system or nothing
        }
    }
}

/// The key bar's keys, in its order (`allCases`).
public enum TerminalBarKey: CaseIterable, Sendable {
    case escape, tab, ctrl, left, up, down, right

    /// What it sends; nil for ctrl, which latches for the next key instead.
    public var key: TerminalKey? {
        switch self {
        case .escape: return .escape
        case .tab: return .tab
        case .ctrl: return nil
        case .left: return .left
        case .up: return .up
        case .down: return .down
        case .right: return .right
        }
    }
}
