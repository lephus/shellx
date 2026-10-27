import Foundation
import Observation

/// Counts the sheets open over the signed-in screens (the pending question, plan and full-text
/// sheets), so a pairing link opened meanwhile waits for them (`PairingInbox.take(over:)`): SwiftUI
/// shows one sheet at a time, and closing an answer sheet to make room would lose what was typed.
///
/// Each sheet calls `opened()` when it appears and `closed()` when it goes. The two may come in
/// either order when one sheet replaces another.
@MainActor @Observable
public final class SheetPresence {
    private var count = 0

    public init() {}

    /// True while any sheet is up.
    public var isAnyOpen: Bool { count > 0 }

    public func opened() {
        count += 1
    }

    /// Never goes below none (a disappear without its appear).
    public func closed() {
        count = max(0, count - 1)
    }
}
