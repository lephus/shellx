import Foundation

/// Mints the host-side relay ticket (`register` on the share's own slot) for a share. A provider throws
/// `ShareTicketError.terminal` when the API says the share is gone; any other error is retried.
public protocol ShareTicketProvider: Sendable { func hostTicket(shareID: String) async throws -> (ticket: String, relayURL: URL, expiresAt: Date) }

/// The share no longer exists on the API: the host stops with `reason` instead of retrying.
public enum ShareTicketError: Error, Equatable, Sendable {
    case terminal(ShareByeReason)

    /// API codes that end a share: revoked, expired, and not found (treated as revoked).
    public static func terminalReason(forCode code: String) -> ShareByeReason? {
        switch code {
        case "share_revoked", "share_not_found": return .revoked
        case "share_expired": return .expired
        default: return nil
        }
    }
}

/// `ShareTicketProvider` backed by shellx-core `shares.host_ticket`. The FFI call blocks, so it runs on a global queue, never the caller's (main) thread.
public struct ShellXCoreShareTickets: ShareTicketProvider {
    private let core: ShellXCoreClient

    public init(core: ShellXCoreClient) { self.core = core }

    public func hostTicket(shareID: String) async throws -> (ticket: String, relayURL: URL, expiresAt: Date) {
        let core = self.core
        return try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                cont.resume(with: Result {
                    do { return try core.hostShareTicket(id: shareID) } catch let error as ShellXCoreError {
                        if let reason = ShareTicketError.terminalReason(forCode: error.code) {
                            throw ShareTicketError.terminal(reason)
                        }
                        throw error
                    }
                })
            }
        }
    }
}
