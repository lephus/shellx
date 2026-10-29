import Foundation

/// A relay ticket for this account's ShellX Link lane (`tickets.mint {lane: "link"}`).
///
/// Its descriptions never print the ticket.
public struct ShellXLinkTicket: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    /// What the ticket allows on the relay.
    public enum Permission: Equatable, Sendable {
        /// Registers this machine's link slot (the host side).
        case register
        /// Connects to `targetMachineID`'s link slot (D3: a self-connect for this machine's own invite).
        case connect(targetMachineID: String)
    }

    /// The signed ticket (`v2.<claims>.<signature>`).
    public let ticket: String
    /// The relay the ticket is for, as shellx-core returns it (`wss://host/v2/relay`).
    public let relayURL: URL
    /// When the relay stops accepting the ticket.
    public let expiresAtUnix: Int64
    /// The slot the ticket's claims name, already checked against the expected link slot.
    public let slot: String

    public init(ticket: String, relayURL: URL, expiresAtUnix: Int64, slot: String) {
        self.ticket = ticket; self.relayURL = relayURL; self.expiresAtUnix = expiresAtUnix; self.slot = slot
    }

    public var description: String { "ShellXLinkTicket(slot: \(slot), expires: \(expiresAtUnix), <redacted>)" }
    public var debugDescription: String { description }

    /// The `slot` claim of a `v2.<base64url JSON claims>.<signature>` ticket, or nil when it has none.
    static func slotClaim(of ticket: String) -> String? {
        let parts = ticket.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "v2" else { return nil }
        var b64 = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        b64 += String(repeating: "=", count: (4 - b64.count % 4) % 4)
        guard let data = Data(base64Encoded: b64),
              let claims = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }
        return claims["slot"] as? String
    }
}

extension ShellXCoreClient {
    /// `tickets.mint {permission, lane: "link"}`, returned inline (never written to a file).
    ///
    /// The ticket's `slot` claim must equal `expectedSlot`. A relay that predates the link lane ignores
    /// `lane` and would mint a ticket for the cmux-tui slot; registering with it would replace the
    /// terminal daemon, so such a ticket is refused. Blocks on the FFI: never call it on the main thread.
    ///
    /// - Parameters:
    ///   - permission: Register this machine's link slot, or connect to a machine's link slot.
    ///   - expectedSlot: The link slot from `machines.register`.
    /// - Returns: The checked ticket.
    /// - Throws: ``ShellXCoreError``: the core's code, `bad_response` for an unusable reply, or
    ///   `link_slot_mismatch` when the ticket names another slot.
    public func mintLinkTicket(_ permission: ShellXLinkTicket.Permission, expectedSlot: String) throws -> ShellXLinkTicket {
        struct Reply: Decodable { let ticket: String; let expires_at_unix: Double; let relay_url: String }
        var params: [String: JSONValue] = ["lane": .string("link")]
        switch permission {
        case .register:
            params["permission"] = .string("register")
        case .connect(let target):
            params["permission"] = .string("connect")
            params["target_machine_id"] = .string(target)
        }
        let reply = try call("tickets.mint", params, as: Reply.self)
        guard !reply.ticket.isEmpty, let url = URL(string: reply.relay_url), url.scheme != nil else {
            throw ShellXCoreError(code: "bad_response", message: "core reply has no usable ticket or relay_url")
        }
        guard let slot = ShellXLinkTicket.slotClaim(of: reply.ticket) else {
            throw ShellXCoreError(code: "bad_response", message: "the link ticket has no slot claim")
        }
        guard slot == expectedSlot else {
            throw ShellXCoreError(code: "link_slot_mismatch", message: "the relay minted a ticket for another slot")
        }
        return ShellXLinkTicket(ticket: reply.ticket, relayURL: url, expiresAtUnix: Int64(reply.expires_at_unix), slot: slot)
    }
}
