import Foundation

/// Mints the host-side relay ticket (`register` on the share's own slot) for a share.
public protocol ShareTicketProvider: Sendable { func hostTicket(shareID: String) async throws -> (ticket: String, relayURL: URL, expiresAt: Date) }

/// `ShareTicketProvider` backed by shellx-core `shares.host_ticket`. The FFI call blocks, so it runs on a global queue, never the caller's (main) thread.
public struct ShellXCoreShareTickets: ShareTicketProvider {
    private let core: ShellXCoreClient

    public init(core: ShellXCoreClient) { self.core = core }

    public func hostTicket(shareID: String) async throws -> (ticket: String, relayURL: URL, expiresAt: Date) {
        let core = self.core
        return try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                cont.resume(with: Result { try core.hostShareTicket(id: shareID) })
            }
        }
    }
}
