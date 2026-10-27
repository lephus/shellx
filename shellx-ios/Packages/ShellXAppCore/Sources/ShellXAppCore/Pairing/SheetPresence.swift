import Foundation
import Observation

/// Seam for the final-review regression tests; the fix fills it in.
@MainActor @Observable
public final class SheetPresence {
    public init() {}

    public var isAnyOpen: Bool { false }

    public func opened() {}

    public func closed() {}
}
