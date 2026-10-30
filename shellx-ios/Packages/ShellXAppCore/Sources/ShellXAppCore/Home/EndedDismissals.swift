import Foundation
import Observation
import ShellXLinkCore

/// The ended sessions the user took off the phone's Ended list. Stub: nothing is hidden yet.
public struct EndedDismissals: Equatable, Sendable, Codable {
    public static let none = EndedDismissals()

    public init() {}

    public func hides(_ session: MachineSession) -> Bool { false }

    public mutating func dismiss(_ session: MachineSession) {}

    public func pruned(now: Date) -> EndedDismissals { self }
}

/// Keeps `EndedDismissals` in `UserDefaults`. Stub: nothing is kept yet.
@MainActor @Observable
public final class EndedDismissalStore {
    public private(set) var dismissals = EndedDismissals.none

    static let key = "shellx.dismissedEnded"

    public init(defaults: UserDefaults, now: @escaping @Sendable () -> Date = { Date() }) {}

    public func dismiss(_ session: MachineSession) {}
}
