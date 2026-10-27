import Foundation
import ShellXLinkCore

/// One chat push from a Mac, as `MachineHub.chatUpdates()` hands it out, in the order it arrived:
/// new or changed entries of a session, or the reset of that session's transcript (PROTOCOL.md
/// section 4, `chat.entries` and `chat.reset`).
public enum ChatUpdate: Equatable, Sendable {
    /// New or changed entries (upserts by `ChatEntry.id`).
    case upsert(SessionRef, [ChatEntry])
    /// The transcript was replaced: every entry held for the session, its `seq` values and any
    /// history answer asked for before are void. Pushes after this one belong to the new transcript.
    case reset(SessionRef)

    /// The session the push is about.
    public var ref: SessionRef {
        switch self {
        case let .upsert(ref, _), let .reset(ref): ref
        }
    }

    /// The upserted entries; empty for a reset.
    public var entries: [ChatEntry] {
        switch self {
        case let .upsert(_, entries): entries
        case .reset: []
        }
    }
}
