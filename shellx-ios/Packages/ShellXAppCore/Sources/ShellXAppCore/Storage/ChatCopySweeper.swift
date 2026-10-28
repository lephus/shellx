import Foundation

/// Drops a session's stored chat copy when its Mac resets the transcript (`chat.reset`, PROTOCOL.md
/// section 4), whether or not an agent screen follows that session: the copy is the old transcript's,
/// and a screen opened later must show the new one only. (A screen that is open does the same itself.)
///
/// The signed-in view runs it for as long as it is on screen. It writes with a store writer of the
/// account that started it, so nothing is written after a sign-out wipe.
@MainActor
public final class ChatCopySweeper {
    private let hub: MachineHub
    private let store: ConversationStore

    public init(hub: MachineHub, store: ConversationStore) {
        self.hub = hub
        self.store = store
    }

    /// Watches the hub until cancelled (or the hub stops).
    public func run() async {
        // Subscribe first, so no reset falls between the subscription and the writer.
        let updates = hub.chatUpdates()
        let writer = await store.writer()
        for await update in updates {
            if case let .reset(ref) = update { await writer.remove(.thread(ref)) }
        }
    }
}
