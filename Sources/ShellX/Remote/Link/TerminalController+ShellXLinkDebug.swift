#if DEBUG
import Foundation
import ShellXRemoteCore

extension TerminalController {
    /// ShellX: `shellx.link.debug_invite {client_key_b64}` → `{relay_url, slot, ticket, expires_at_unix,
    /// host_key_b64}` (DEBUG spike pairing). Trusts the client key, then mints a link-lane connect ticket to this
    /// machine itself (D3).
    ///
    /// Runs on the socket worker (`ControlCommandExecutionPolicy.socketWorkerMethods`): the mint blocks on HTTP.
    /// It touches no window, workspace or focus; the controller's main-actor state is read in one short hop.
    /// The reply carries a ticket, so nothing here logs it or the key.
    nonisolated func v2ShellXLinkDebugInvite(id: Any?, params: [String: Any]) -> String {
        guard let raw = params["client_key_b64"] as? String,
              let clientKey = Self.shellXLinkKeyData(raw), clientKey.count == 32 else {
            return v2Error(id: id, code: "invalid_params",
                           message: "shellx.link.debug_invite requires client_key_b64 (a base64 32-byte key)")
        }
        return v2AsyncResultCall(id: id, timeoutSeconds: 30) {
            let host = await MainActor.run { ShellXRemoteService.shared.linkHost as? ShellXLinkHostController }
            guard let host else {
                return .err(code: "link_not_running", message: "this Mac is not serving ShellX Link", data: nil)
            }
            do {
                let invite = try await host.debugInvite(clientKey: clientKey)
                return .ok([
                    "relay_url": invite.relayURL,
                    "slot": invite.slot,
                    "ticket": invite.ticket,
                    "expires_at_unix": invite.expiresAtUnix,
                    "host_key_b64": invite.hostKeyB64,
                ])
            } catch {
                let core = error as? ShellXCoreError
                return .err(code: core?.code ?? "link_error", message: core?.message ?? "the invite failed", data: nil)
            }
        }
    }

    /// Standard or URL-safe base64, padded or not.
    nonisolated static func shellXLinkKeyData(_ text: String) -> Data? {
        var b64 = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        b64 += String(repeating: "=", count: (4 - b64.count % 4) % 4)
        return Data(base64Encoded: b64)
    }
}
#endif
