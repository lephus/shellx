import Foundation

/// Where the user's decision on one pending item stands. No status: nothing was sent.
public enum DecisionStatus: Equatable, Sendable {
    /// On its way to the Mac; other taps on the item are ignored.
    case sending
    /// The waiting agent took it: the card is gone.
    case done
    /// The item was decided before this decision arrived (on the Mac, another phone, or it
    /// expired). The card says so, then goes.
    case handledElsewhere
    /// Not taken; the card stays and says why.
    case failed(DecisionFailure)
}
